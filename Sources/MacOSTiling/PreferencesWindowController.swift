import AppKit
import ServiceManagement

// MARK: - Window controller

@MainActor
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
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

// MARK: - View controller

@MainActor
private final class PreferencesViewController: NSViewController {

    // ── Gap ──────────────────────────────────────────────────────────
    private let gapControl = NSSegmentedControl()

    // ── Behavior checkboxes ──────────────────────────────────────────
    private let loginCheck  = NSButton(checkboxWithTitle: "Launch at Login",        target: nil, action: nil)
    private let statusCheck = NSButton(checkboxWithTitle: "Show status in menu",    target: nil, action: nil)

    // ── Feature toggles ──────────────────────────────────────────────
    private let thirdsCheck    = NSButton(checkboxWithTitle: "Thirds layout  (⌥→→ cycles 1/2 → 2/3 → 1/3)", target: nil, action: nil)
    private let undoCheck      = NSButton(checkboxWithTitle: "Undo last snap  (⌥Z by default)",              target: nil, action: nil)
    private let overlayCheck   = NSButton(checkboxWithTitle: "Snap zone overlay on drag",                    target: nil, action: nil)
    private let customSCCheck  = NSButton(checkboxWithTitle: "Custom keyboard shortcuts",                    target: nil, action: nil)

    // ── Shortcut rows (shown when customSCCheck is on) ───────────────
    private var shortcutSection: NSView?
    private var shortcutButtons: [String: ShortcutButton] = [:]
    private let scActions: [(String, String)] = [
        ("left",  "Snap left"),
        ("right", "Snap right"),
        ("up",    "Snap up"),
        ("down",  "Snap down / center"),
        ("undo",  "Undo snap"),
    ]

    // ── Reset ────────────────────────────────────────────────────────
    private let resetButton = NSButton(title: "Reset All Settings", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        sync()
    }

    // MARK: - Build

    private func buildUI() {
        let v = view
        let pad: CGFloat = 24
        var y: CGFloat = 20

        // ── Reset ──────────────────────────────────────────────────
        resetButton.bezelStyle = .rounded
        resetButton.contentTintColor = .systemRed
        resetButton.target = self; resetButton.action = #selector(doReset)
        resetButton.frame = CGRect(x: pad, y: y, width: 180, height: 28)
        v.addSubview(resetButton)
        y += 44

        addSeparator(at: y); y += 14

        // ── Behavior section ──────────────────────────────────────
        addSectionHeader("Behavior", at: y); y += 22
        statusCheck.target = self; statusCheck.action = #selector(statusChanged)
        statusCheck.frame = CGRect(x: pad, y: y, width: 340, height: 22); v.addSubview(statusCheck); y += 28
        loginCheck.target = self; loginCheck.action = #selector(loginChanged)
        loginCheck.frame = CGRect(x: pad, y: y, width: 340, height: 22); v.addSubview(loginCheck); y += 36

        addSeparator(at: y); y += 14

        // ── Gap ───────────────────────────────────────────────────
        addSectionHeader("Window Gap", at: y); y += 22
        gapControl.segmentCount = 4
        gapControl.setLabel("None", forSegment: 0)
        gapControl.setLabel("4 px",  forSegment: 1)
        gapControl.setLabel("8 px",  forSegment: 2)
        gapControl.setLabel("12 px", forSegment: 3)
        gapControl.target = self; gapControl.action = #selector(gapChanged)
        gapControl.frame = CGRect(x: pad, y: y, width: 280, height: 28); v.addSubview(gapControl); y += 42

        addSeparator(at: y); y += 14

        // ── Feature toggles ───────────────────────────────────────
        addSectionHeader("Features", at: y); y += 22

        for cb in [thirdsCheck, undoCheck, overlayCheck, customSCCheck] {
            cb.target = self; cb.action = #selector(featureChanged(_:))
            cb.font = .systemFont(ofSize: 13)
            cb.frame = CGRect(x: pad, y: y, width: 370, height: 22)
            v.addSubview(cb)
            y += 26
        }
        y += 4

        // ── Shortcut section (collapsible) ────────────────────────
        let scContainer = NSView(frame: CGRect(x: 0, y: y, width: 420, height: 0))
        scContainer.wantsLayer = true
        v.addSubview(scContainer)
        shortcutSection = scContainer

        var sy: CGFloat = 8
        addSectionHeader("Keyboard Shortcuts", at: y + sy, in: v); sy += 22

        for (action, label) in scActions {
            let lbl = makeLabel(label)
            lbl.frame = CGRect(x: pad, y: y + sy, width: 160, height: 22)
            v.addSubview(lbl)

            let btn = ShortcutButton(action: action)
            btn.frame = CGRect(x: pad + 165, y: y + sy, width: 120, height: 22)
            btn.onChanged = { [weak self] in self?.sync() }
            v.addSubview(btn)
            shortcutButtons[action] = btn
            sy += 28
        }

        let resetSC = NSButton(title: "Reset shortcuts", target: self, action: #selector(resetShortcuts))
        resetSC.bezelStyle = .inline
        resetSC.frame = CGRect(x: pad, y: y + sy, width: 130, height: 20)
        v.addSubview(resetSC)

        // Title at top
        let title = NSTextField(labelWithString: "Tyler")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = CGRect(x: pad, y: v.bounds.height - 36, width: 200, height: 22)
        v.addSubview(title)
    }

    // MARK: - Sync

    private func sync() {
        let gapValues = [0, 4, 8, 12]
        gapControl.selectedSegment = gapValues.firstIndex(of: Settings.windowGap) ?? 0
        loginCheck.state  = SMAppService.mainApp.status == .enabled ? .on : .off
        statusCheck.state = Settings.showStatusIndicators ? .on : .off
        thirdsCheck.state   = Settings.enableThirds          ? .on : .off
        undoCheck.state     = Settings.enableUndo             ? .on : .off
        overlayCheck.state  = Settings.enableSnapOverlay      ? .on : .off
        customSCCheck.state = Settings.enableCustomShortcuts  ? .on : .off

        let showSC = Settings.enableCustomShortcuts
        shortcutSection?.isHidden = !showSC
        for (action, btn) in shortcutButtons {
            btn.display(shortcut: Settings.shortcut(for: action))
        }
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
    @objc private func featureChanged(_ sender: NSButton) {
        let on = sender.state == .on
        switch sender {
        case thirdsCheck:   Settings.enableThirds         = on
        case undoCheck:     Settings.enableUndo           = on
        case overlayCheck:  Settings.enableSnapOverlay    = on
        case customSCCheck: Settings.enableCustomShortcuts = on
        default: break
        }
        sync()
    }
    @objc private func doReset() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText = "All preferences and custom shortcuts will return to defaults."
        alert.alertStyle = .warning
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
    private func addSeparator(at y: CGFloat) -> NSBox {
        let line = NSBox(frame: CGRect(x: 24, y: y, width: view.bounds.width - 48, height: 1))
        line.boxType = .separator
        view.addSubview(line)
        return line
    }

    private func addSectionHeader(_ text: String, at y: CGFloat, in parent: NSView? = nil) {
        let lbl = NSTextField(labelWithString: text.uppercased())
        lbl.font = .systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.frame = CGRect(x: 24, y: y, width: 300, height: 16)
        (parent ?? view).addSubview(lbl)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13)
        f.textColor = .labelColor
        return f
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
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        target = self
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
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // Escape cancels recording
            if event.keyCode == 53 { self.stopRecording(); return nil }
            // Require at least one modifier
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
