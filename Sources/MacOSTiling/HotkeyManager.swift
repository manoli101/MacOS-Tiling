import AppKit

private let kVKLeftArrow:  CGKeyCode = 123
private let kVKRightArrow: CGKeyCode = 124
private let kVKDownArrow:  CGKeyCode = 125
private let kVKUpArrow:    CGKeyCode = 126

@MainActor
final class HotkeyManager {

    static var instance: HotkeyManager?

    private var eventTap:       CFMachPort?
    private var runLoopSource:  CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var hidMonitor:     HIDKeyboardMonitor?

    var tapIsActive: Bool { eventTap != nil }

    private let windowManager = WindowManager()
    private lazy var dragSnap = DragSnapManager(windowManager: windowManager)

    // Prevents double-fire when multiple monitors (HID + tap) catch the same event
    private var lastTileTime: Double = 0
    private var lastDownTime: Double = 0

    // MARK: - Lifecycle

    func start() {
        HotkeyManager.instance = self
        _ = dragSnap

        // Layer 1: CGEventTap — primary path on real Macs (consumes event, prevents apps seeing it)
        attemptTapCreation()

        // Layer 2: NSEvent global monitor — secondary path, requires Input Monitoring permission
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(
                keyCode: CGKeyCode(event.keyCode),
                flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            )
        }

        // Layer 3: IOHIDManager — deepest intercept point for virtualized keyboards
        let hid = HIDKeyboardMonitor()
        hid.onArrow = { [weak self] dir in self?.tile(direction: dir) }
        hid.start()
        hidMonitor = hid
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        if let m = fallbackMonitor { NSEvent.removeMonitor(m) }
        hidMonitor?.stop()
        eventTap = nil; runLoopSource = nil; fallbackMonitor = nil; hidMonitor = nil
        HotkeyManager.instance = nil
    }

    func reenable() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    // MARK: - Event handling

    func handle(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let required: CGEventFlags  = [.maskAlternate]
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

    // MARK: - Tiling

    private func tile(direction: Direction) {
        let now = CACurrentMediaTime()
        guard now - lastTileTime > 0.05 else { return }
        lastTileTime = now

        guard let window = windowManager.frontmostWindow(),
              let frame  = windowManager.getFrame(window) else { return }

        let winID  = windowManager.windowID(window)
        let engine = TilingEngine.shared

        if direction == .down {
            let isDouble = now - lastDownTime < 0.4
            lastDownTime = now
            switch engine.stateFor(windowID: winID) {
            case .floating, .centered where isDouble:
                windowManager.minimize(window); return
            default: break
            }
        }

        let target   = engine.handle(direction: direction, windowID: winID, currentFrame: frame)
        let newState = engine.stateFor(windowID: winID)
        let bottomAnchored: Bool
        switch newState {
        case .bottomLeft, .bottomRight: bottomAnchored = true
        default:                        bottomAnchored = false
        }
        windowManager.setFrame(window, target, bottomAnchored: bottomAnchored)
    }

    // MARK: - CGEventTap

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
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.attemptTapCreation() }
            }
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }
}

// MARK: - C callback

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
    let consumed = MainActor.assumeIsolated {
        HotkeyManager.instance?.handle(keyCode: keyCode, flags: event.flags) ?? false
    }
    return consumed ? nil : Unmanaged.passRetained(event)
}
