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

    // Double-press Down detection for minimize
    private var lastDownTime: Date = .distantPast

    func start() {
        HotkeyManager.instance = self
        _ = dragSnap  // Initialize drag-snap monitor immediately
        attemptTapCreation()
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
        eventTap = nil
        runLoopSource = nil
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
        guard let window = windowManager.frontmostWindow(),
              let currentFrame = windowManager.getFrame(window) else { return }

        let winID = windowManager.windowID(window)
        let engine = TilingEngine.shared
        let state  = engine.stateFor(windowID: winID)

        // Down behavior: from floating requires double-press to minimize; from tiled states moves down
        if direction == .down {
            if state == .floating {
                let now = Date()
                let isDouble = now.timeIntervalSince(lastDownTime) < 0.4
                lastDownTime = now
                if isDouble { windowManager.minimize(window) }
                // Single Down from floating: no-op (consume event but don't move window)
                return
            }
            // From tiled states, Down moves to lower state as normal
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
