import AppKit

// Virtual key codes for arrow keys (stable across keyboard layouts)
private let kVKLeftArrow:  CGKeyCode = 123
private let kVKRightArrow: CGKeyCode = 124
private let kVKDownArrow:  CGKeyCode = 125
private let kVKUpArrow:    CGKeyCode = 126

@MainActor
final class HotkeyManager {

    // Bridging reference used by the C callback (must be set before tapCreate)
    static var instance: HotkeyManager?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var tapIsActive: Bool { eventTap != nil }

    private let windowManager = WindowManager()
    private lazy var dragSnap  = DragSnapManager(windowManager: windowManager)

    // NSEvent fallback — catches keys in VMs where CGEventTap misses them (requires Input Monitoring)
    private var keyFallbackMonitor: Any?
    // HID fallback — lowest level, works in UTM/QEMU VMs via virtio-input driver
    private var hidMonitor: HIDKeyboardMonitor?

    // Dedup: prevents double-fire when HID + tap/NSEvent both catch the same keypress
    private var lastTileTime: Double = 0
    // Double-press Down detection for minimize
    private var lastDownTime: Double = 0

    func start() {
        HotkeyManager.instance = self
        _ = dragSnap
        startKeyFallbackMonitor()
        startHIDMonitor()
        attemptTapCreation()
    }

    private func startKeyFallbackMonitor() {
        keyFallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = CGKeyCode(event.keyCode)
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            _ = self?.handle(keyCode: keyCode, flags: flags)
        }
    }

    private func startHIDMonitor() {
        let m = HIDKeyboardMonitor()
        m.onArrow = { [weak self] direction in self?.tile(direction: direction) }
        m.start()
        hidMonitor = m
    }

    private func attemptTapCreation() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else {
            // Retry every 2 s until permission is granted and tap succeeds
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.attemptTapCreation() }
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        NSLog("[MacOSTiling] Event tap active")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let monitor = keyFallbackMonitor { NSEvent.removeMonitor(monitor) }
        hidMonitor?.stop()
        eventTap = nil
        runLoopSource = nil
        keyFallbackMonitor = nil
        hidMonitor = nil
        HotkeyManager.instance = nil
    }

    func reenable() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // Returns true if the event was consumed (shortcut matched)
    func handle(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        // Require exactly Option, no other modifiers
        let required: CGEventFlags = [.maskAlternate]
        let forbidden: CGEventFlags = [.maskCommand, .maskShift, .maskControl]
        guard flags.intersection(required) == required,
              flags.intersection(forbidden).isEmpty else { return false }

        let direction: Direction
        switch keyCode {
        case kVKLeftArrow:  direction = .left
        case kVKRightArrow: direction = .right
        case kVKUpArrow:    direction = .up
        case kVKDownArrow:  direction = .down
        default:            return false
        }

        tile(direction: direction)
        return true
    }

    // MARK: - Tiling action

    private func tile(direction: Direction) {
        // Deduplicate: HID + tap/NSEvent can both fire for the same keypress within microseconds
        let now = CACurrentMediaTime()
        guard now - lastTileTime > 0.05 else { return }
        lastTileTime = now

        guard let window = windowManager.frontmostWindow(),
              let currentFrame = windowManager.getFrame(window) else {
            NSLog("[Tyler] tile: could not get frontmost window or frame")
            return
        }

        let winID = windowManager.windowID(window)
        let engine = TilingEngine.shared
        let state  = engine.stateFor(windowID: winID)

        // Down: double-press from unsnapped states minimizes; single press centers or moves down
        if direction == .down {
            let now = CACurrentMediaTime()
            let isDouble = now - lastDownTime < 0.4
            lastDownTime = now
            switch state {
            case .floating, .centered:
                if isDouble { windowManager.minimize(window); return }
            default:
                break
            }
        }

        let targetFrame = engine.handle(direction: direction, windowID: winID, currentFrame: currentFrame)
        let newState = engine.stateFor(windowID: winID)
        let bottomAnchored: Bool
        switch newState {
        case .bottomLeft, .bottomRight: bottomAnchored = true
        default: bottomAnchored = false
        }
        windowManager.setFrame(window, targetFrame, bottomAnchored: bottomAnchored)
    }
}

// MARK: - C callback (runs on main run loop — safe to use MainActor.assumeIsolated)

private func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        MainActor.assumeIsolated { HotkeyManager.instance?.reenable() }
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    let consumed = MainActor.assumeIsolated {
        HotkeyManager.instance?.handle(keyCode: keyCode, flags: flags) ?? false
    }

    return consumed ? nil : Unmanaged.passRetained(event)
}
