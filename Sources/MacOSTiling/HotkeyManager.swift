import AppKit

@MainActor
final class HotkeyManager {

    static var instance: HotkeyManager?

    private var eventTap:        CFMachPort?
    private var runLoopSource:   CFRunLoopSource?
    private var fallbackMonitor: Any?
    private var hidMonitor:      HIDKeyboardMonitor?

    var tapIsActive: Bool { eventTap != nil }

    private let windowManager = WindowManager()
    private lazy var dragSnap = DragSnapManager(windowManager: windowManager)

    private var lastTileTime: Double = 0
    private var lastDownTime: Double = 0

    // MARK: - Lifecycle

    func start() {
        HotkeyManager.instance = self
        _ = dragSnap

        attemptTapCreation()

        // Fallback: only fires when CGEventTap is unavailable (no Input Monitoring permission)
        fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.tapIsActive else { return }
            _ = self.handle(
                keyCode: CGKeyCode(event.keyCode),
                flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            )
        }

        let hid = HIDKeyboardMonitor()
        hid.onArrow = { [weak self] dir in
            // Only fire from HID when the CGEventTap is unavailable (no Input Monitoring permission)
            guard let self, !self.tapIsActive, !self.textFieldFocused() else { return }
            self.tile(direction: dir)
        }
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
        // Resolve active shortcuts
        let sc = activeShortcuts()

        // Check undo first (⌥Z by default)
        if Settings.enableUndo, let undoSC = sc["undo"] {
            if matchesShortcut(undoSC, keyCode: keyCode, flags: flags) {
                return handleUndo()
            }
        }

        // Arrow shortcuts — require exact modifier match (no forbidden extras)
        let actionMap: [(String, Direction)] = [
            ("left", .left), ("right", .right), ("up", .up), ("down", .down)
        ]
        for (action, direction) in actionMap {
            if let sc = sc[action], matchesShortcut(sc, keyCode: keyCode, flags: flags) {
                // Only respect text fields when the shortcut would otherwise navigate text
                // (Option = by word, Command = by line/doc). Control/Shift arrows never
                // navigate text on macOS, so tiling works even while editing (Notes, TextEdit…).
                if shortcutConflictsWithText(sc) && textFieldFocused() { return false }
                tile(direction: direction)
                return true
            }
        }
        return false
    }

    private func matchesShortcut(_ sc: Shortcut, keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard UInt16(keyCode) == sc.keyCode else { return false }
        let required  = CGEventFlags(rawValue: UInt64(sc.modifiers))
        let forbidden = CGEventFlags(rawValue: UInt64(
            (NSEvent.ModifierFlags.command.rawValue  |
             NSEvent.ModifierFlags.option.rawValue   |
             NSEvent.ModifierFlags.control.rawValue  |
             NSEvent.ModifierFlags.shift.rawValue)
        )).subtracting(required)
        return flags.intersection(required) == required &&
               flags.intersection(forbidden).isEmpty
    }

    private func activeShortcuts() -> [String: Shortcut] {
        var result: [String: Shortcut] = [:]
        for action in ["left", "right", "up", "down", "undo"] {
            result[action] = Settings.shortcut(for: action)
        }
        return result
    }

    // MARK: - Undo

    private func handleUndo() -> Bool {
        guard let window = windowManager.frontmostWindow() else { return false }
        let winID = windowManager.windowID(window)
        guard let prevFrame = TilingEngine.shared.undo(windowID: winID) else { return false }
        windowManager.setFrame(window, prevFrame, bottomAnchored: false)
        return true
    }

    // MARK: - Text field guard

    // A shortcut only collides with macOS text navigation when it uses Option (jump by
    // word) or Command (jump by line/doc). Control/Shift+arrows do not navigate text, so
    // they are safe to use for tiling even while a text field/area is focused.
    private func shortcutConflictsWithText(_ sc: Shortcut) -> Bool {
        let f = NSEvent.ModifierFlags(rawValue: sc.modifiers)
        if f.contains(.control) { return false }
        return f.contains(.option) || f.contains(.command)
    }

    // Returns true only when the user is typing in a real text input that ⌥+Arrow
    // would navigate (web content text fields, code editors, document text areas).
    // Browser URL bars are AXTextField children of an AXToolbar — NOT inside a web
    // area — so they are excluded, allowing Tyler to snap a freshly-opened window
    // even while the address bar has focus.
    private func textFieldFocused() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let elem = axApp.focusedUIElement else { return false }
        let r = elem.role ?? ""
        // Multi-line text areas (documents, code editors, terminals) — always block.
        if r == kAXTextAreaRole as String { return true }
        // Single-line text fields: only block when inside web content.
        guard r == kAXTextFieldRole as String else { return false }
        return isInsideWebArea(elem)
    }

    // Walks up the AX parent chain (max 10 levels) looking for AXWebArea.
    // Fast — each call is a local IPC to the app process, typically < 1 ms.
    private func isInsideWebArea(_ elem: AXUIElement) -> Bool {
        var current: AXUIElement = elem
        for _ in 0..<10 {
            guard let p = current.parent else { break }
            if p.role == "AXWebArea" { return true }
            current = p
        }
        return false
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
            if isDouble {
                switch engine.stateFor(windowID: winID) {
                case .floating, .centered:
                    windowManager.minimize(window); return
                default: break
                }
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
    let keyCode  = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let consumed = MainActor.assumeIsolated {
        HotkeyManager.instance?.handle(keyCode: keyCode, flags: event.flags) ?? false
    }
    return consumed ? nil : Unmanaged.passRetained(event)
}
