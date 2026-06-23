import AppKit
import ServiceManagement

// MARK: - Window controller

@MainActor
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Tyler Preferences"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.contentViewController = PreferencesViewController()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Flipped content view

private class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - View controller

@MainActor
private final class PreferencesViewController: NSViewController {

    private let gapControl   = NSSegmentedControl()
    private let loginCheck      = NSButton(checkboxWithTitle: "Launch at Login",             target: nil, action: nil)
    private let statusCheck     = NSButton(checkboxWithTitle: "Show status in menu",         target: nil, action: nil)
    private let layoutIconCheck = NSButton(checkboxWithTitle: "Show layout in menu bar icon",target: nil, action: nil)

    private let thirdsCheck   = NSButton(checkboxWithTitle: "Thirds layout  (⌥→→ cycles 1/2 → 2/3 → 1/3)", target: nil, action: nil)
    private let undoCheck     = NSButton(checkboxWithTitle: "Undo last snap  (⌥Z by default)",              target: nil, action: nil)
    private let overlayCheck  = NSButton(checkboxWithTitle: "Snap zone overlay on drag",                    target: nil, action: nil)
    private let customSCCheck = NSButton(checkboxWithTitle: "Custom keyboard shortcuts",                    target: nil, action: nil)

    private let resetButton = NSButton(title: "Reset All Settings", target: nil, action: nil)

    private let scActions: [(String, String)] = [
        ("left",  "Snap left"),
        ("right", "Snap right"),
        ("up",    "Snap up"),
        ("down",  "Snap down / center"),
        ("undo",  "Undo snap"),
    ]
    private var shortcutButtons: [String: ShortcutButton] = [:]
    private var shortcutViews:   [NSView] = []

    // Track y position of the shortcut section so we can measure content height
    private var scSectionY:      CGFloat = 0
    private var scSectionHeight: CGFloat = 0
    private weak var docView:    NSView?

    // MARK: - View

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 540))
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .noBorder
        scrollView.drawsBackground       = true
        scrollView.backgroundColor       = .windowBackgroundColor

        // Document view is taller than window — scroll reveals the rest
        let doc = FlippedView(frame: NSRect(x: 0, y: 0, width: 420, height: 700))
        scrollView.documentView = doc
        docView = doc
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let doc = docView else { return }
        buildUI(in: doc)
        sync()
    }

    // MARK: - Build (top-down, FlippedView: y=0 at top)

    private func buildUI(in v: NSView) {
        let pad: CGFloat = 24
        var y:   CGFloat = 20

        // ── BEHAVIOR ──────────────────────────────────────────────────
        addHeader("Behavior", at: y, in: v); y += 26

        statusCheck.target     = self; statusCheck.action     = #selector(statusChanged)
        loginCheck.target      = self; loginCheck.action      = #selector(loginChanged)
        layoutIconCheck.target = self; layoutIconCheck.action = #selector(layoutIconChanged)
        for cb in [layoutIconCheck, statusCheck, loginCheck] {
            cb.font  = .systemFont(ofSize: 13)
            cb.frame = CGRect(x: pad, y: y, width: 370, height: 22)
            v.addSubview(cb); y += 28
        }

        y += 4; addSeparator(at: y, in: v); y += 20

        // ── WINDOW GAP ────────────────────────────────────────────────
        addHeader("Window Gap", at: y, in: v); y += 26

        gapControl.segmentCount = 4
        gapControl.setLabel("None", forSegment: 0)
        gapControl.setLabel("4 px",  forSegment: 1)
        gapControl.setLabel("8 px",  forSegment: 2)
        gapControl.setLabel("12 px", forSegment: 3)
        gapControl.target = self; gapControl.action = #selector(gapChanged)
        gapControl.frame  = CGRect(x: pad, y: y, width: 280, height: 28)
        v.addSubview(gapControl); y += 36

        y += 4; addSeparator(at: y, in: v); y += 20

        // ── FEATURES ──────────────────────────────────────────────────
        addHeader("Features", at: y, in: v); y += 26

        for cb in [thirdsCheck, undoCheck, overlayCheck, customSCCheck] {
            cb.target = self; cb.action = #selector(featureChanged(_:))
            cb.font   = .systemFont(ofSize: 13)
            cb.frame  = CGRect(x: pad, y: y, width: 370, height: 22)
            v.addSubview(cb); y += 28
        }

        y += 4; addSeparator(at: y, in: v); y += 20

        // ── KEYBOARD SHORTCUTS (collapsible) ──────────────────────────
        scSectionY = y

        let scHeader = addHeader("Keyboard Shortcuts", at: y, in: v)
        shortcutViews.append(scHeader); y += 26

        for (action, label) in scActions {
            let lbl = NSTextField(labelWithString: label)
            lbl.font  = .systemFont(ofSize: 13)
            lbl.frame = CGRect(x: pad, y: y, width: 160, height: 22)
            v.addSubview(lbl); shortcutViews.append(lbl)

            let btn = ShortcutButton(action: action)
            btn.frame = CGRect(x: pad + 165, y: y, width: 120, height: 22)
            btn.onChanged = { [weak self] in self?.sync() }
            v.addSubview(btn); shortcutViews.append(btn)
            shortcutButtons[action] = btn
            y += 30
        }

        let resetSC = NSButton(title: "Reset shortcuts", target: self, action: #selector(resetShortcuts))
        resetSC.bezelStyle = .inline
        resetSC.frame      = CGRect(x: pad, y: y, width: 130, height: 20)
        v.addSubview(resetSC); shortcutViews.append(resetSC)
        y += 30

        let scSep = addSeparator(at: y, in: v)
        shortcutViews.append(scSep)
        scSectionHeight = y + 20 - scSectionY   // includes separator
        y += 20

        // ── RESET ─────────────────────────────────────────────────────
        resetButton.bezelStyle        = .rounded
        resetButton.contentTintColor  = .systemRed
        resetButton.target = self; resetButton.action = #selector(doReset)
        resetButton.frame  = CGRect(x: pad, y: y, width: 180, height: 28)
        v.addSubview(resetButton)
        y += 28 + 20

        // Set document view height to match content
        v.frame = CGRect(x: 0, y: 0, width: 420, height: y)
    }

    // MARK: - Sync

    private func sync() {
        let gapValues = [0, 4, 8, 12]
        gapControl.selectedSegment = gapValues.firstIndex(of: Settings.windowGap) ?? 0
        loginCheck.state           = SMAppService.mainApp.status == .enabled ? .on : .off
        statusCheck.state          = Settings.showStatusIndicators      ? .on : .off
        layoutIconCheck.state      = Settings.showLayoutInStatusIcon     ? .on : .off
        thirdsCheck.state          = Settings.enableThirds          ? .on : .off
        undoCheck.state            = Settings.enableUndo            ? .on : .off
        overlayCheck.state         = Settings.enableSnapOverlay     ? .on : .off
        customSCCheck.state        = Settings.enableCustomShortcuts ? .on : .off

        let showSC = Settings.enableCustomShortcuts
        shortcutViews.forEach { $0.isHidden = !showSC }

        // Slide reset button and adjust document height
        updateDocumentHeight(shortcutsVisible: showSC)

        for (action, btn) in shortcutButtons {
            btn.display(shortcut: Settings.shortcut(for: action))
        }
    }

    private func updateDocumentHeight(shortcutsVisible: Bool) {
        guard let doc = docView else { return }
        // resetButton sits just after the SC section (or just after the separator before it)
        let resetY = shortcutsVisible
            ? scSectionY + scSectionHeight
            : scSectionY
        resetButton.frame.origin.y = resetY
        let totalH = resetY + 28 + 20
        doc.frame = CGRect(x: 0, y: 0, width: 420, height: totalH)
        // Scroll to top whenever layout changes
        (view as? NSScrollView)?.documentView?.scroll(.zero)
    }

    // MARK: - Actions

    @objc private func gapChanged() {
        Settings.windowGap = [0, 4, 8, 12][gapControl.selectedSegment]
    }
    @objc private func loginChanged() {
        let svc = SMAppService.mainApp
        do { try loginCheck.state == .on ? svc.register() : svc.unregister() }
        catch { NSLog("[Tyler] LaunchAtLogin: %@", error.localizedDescription); sync() }
    }
    @objc private func statusChanged() {
        Settings.showStatusIndicators = statusCheck.state == .on
    }
    @objc private func layoutIconChanged() {
        Settings.showLayoutInStatusIcon = layoutIconCheck.state == .on
    }
    @objc private func featureChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case thirdsCheck:   Settings.enableThirds          = on
        case undoCheck:     Settings.enableUndo            = on
        case overlayCheck:  Settings.enableSnapOverlay     = on
        case customSCCheck: Settings.enableCustomShortcuts = on
        default: break
        }
        sync()
    }
    @objc private func doReset() {
        let alert = NSAlert()
        alert.messageText     = "Reset All Settings?"
        alert.informativeText = "All preferences and custom shortcuts will return to defaults."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Reset"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Settings.reset()
        sync()
    }
    @objc private func resetShortcuts() {
        Settings.resetShortcuts()
        sync()
    }

    // MARK: - Helpers

    @discardableResult
    private func addHeader(_ text: String, at y: CGFloat, in parent: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: text.uppercased())
        lbl.font      = .systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.frame     = CGRect(x: 24, y: y, width: 300, height: 16)
        parent.addSubview(lbl)
        return lbl
    }

    @discardableResult
    private func addSeparator(at y: CGFloat, in parent: NSView) -> NSView {
        let line = NSBox(frame: CGRect(x: 24, y: y, width: parent.bounds.width - 48, height: 1))
        line.boxType = .separator
        parent.addSubview(line)
        return line
    }
}

// MARK: - ShortcutButton

@MainActor
final class ShortcutButton: NSButton {

    var onChanged: (() -> Void)?
    private let action_key: String
    private var isRecording = false
    private var monitor: Any?

    init(action: String) {
        self.action_key = action
        super.init(frame: .zero)
        bezelStyle  = .rounded
        font        = .monospacedSystemFont(ofSize: 12, weight: .regular)
        target      = self
        self.action = #selector(startRecording)
    }
    required init?(coder: NSCoder) { nil }

    func display(shortcut: Shortcut) {
        guard !isRecording else { return }
        title = shortcut.displayString
    }

    @objc private func startRecording() {
        guard !isRecording else { stopRecording(); return }
        isRecording = true
        title = "⌨ Press keys…"
        contentTintColor = .systemTeal

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return event }
            let sc = Shortcut(keyCode: event.keyCode, modifiers: mods.rawValue)
            Settings.setShortcut(sc, for: self.action_key)
            self.display(shortcut: sc)
            self.stopRecording()
            self.onChanged?()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        contentTintColor = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        display(shortcut: Settings.shortcut(for: action_key))
    }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}
