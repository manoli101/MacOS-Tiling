import AppKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController {

    static let shared = PreferencesWindowController()

    private init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Tyler Preferences"
        win.isReleasedWhenClosed = false
        win.titlebarAppearsTransparent = false
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

// MARK: - View Controller

@MainActor
private final class PreferencesViewController: NSViewController {

    // Controls
    private let gapControl   = NSSegmentedControl()
    private let loginCheck   = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let statusCheck  = NSButton(checkboxWithTitle: "Show status in menu", target: nil, action: nil)
    private let resetButton  = NSButton(title: "Reset All Settings", target: nil, action: nil)

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 260))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        syncFromSettings()
    }

    // MARK: - Build UI

    private func buildUI() {
        let v = view

        // ── Section label: Window Gap ──────────────────────────────────
        let gapLabel = label("Window Gap")
        gapControl.segmentCount = 4
        gapControl.setLabel("None", forSegment: 0)
        gapControl.setLabel("4 px",  forSegment: 1)
        gapControl.setLabel("8 px",  forSegment: 2)
        gapControl.setLabel("12 px", forSegment: 3)
        gapControl.target = self
        gapControl.action = #selector(gapChanged)

        // ── Section: Behavior ──────────────────────────────────────────
        let behaviorLabel = sectionHeader("Behavior")
        loginCheck.target  = self
        loginCheck.action  = #selector(loginChanged)
        statusCheck.target = self
        statusCheck.action = #selector(statusChanged)

        // ── Divider ────────────────────────────────────────────────────
        let line = NSBox()
        line.boxType = .separator

        // ── Reset button ───────────────────────────────────────────────
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .regular
        (resetButton.cell as? NSButtonCell)?.highlightsBy = .pushInCellMask
        resetButton.contentTintColor = .systemRed
        resetButton.target = self
        resetButton.action = #selector(resetAll)

        // ── Layout (manual, no AutoLayout magic needed at this size) ───
        let pad: CGFloat = 24
        let rowH: CGFloat = 24
        var y: CGFloat = 20

        // Reset at bottom
        resetButton.frame = CGRect(x: pad, y: y, width: 200, height: 28)
        v.addSubview(resetButton)
        y += 44

        // Divider
        line.frame = CGRect(x: pad, y: y, width: v.bounds.width - pad*2, height: 1)
        v.addSubview(line)
        y += 16

        // Behavior checkboxes
        statusCheck.frame = CGRect(x: pad, y: y, width: 300, height: rowH)
        v.addSubview(statusCheck)
        y += rowH + 8

        loginCheck.frame = CGRect(x: pad, y: y, width: 300, height: rowH)
        v.addSubview(loginCheck)
        y += rowH + 14

        behaviorLabel.frame = CGRect(x: pad, y: y, width: 300, height: 18)
        v.addSubview(behaviorLabel)
        y += 28

        // Gap divider
        let line2 = NSBox(); line2.boxType = .separator
        line2.frame = CGRect(x: pad, y: y, width: v.bounds.width - pad*2, height: 1)
        v.addSubview(line2)
        y += 16

        // Gap control
        gapControl.frame = CGRect(x: pad, y: y, width: 260, height: 28)
        v.addSubview(gapControl)
        y += 36

        gapLabel.frame = CGRect(x: pad, y: y, width: 300, height: 18)
        v.addSubview(gapLabel)
        y += 30

        // App title at top
        let title = NSTextField(labelWithString: "Tyler")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.frame = CGRect(x: pad, y: y, width: 200, height: 22)
        v.addSubview(title)
    }

    // MARK: - Sync

    private func syncFromSettings() {
        let gapValues = [0, 4, 8, 12]
        let idx = gapValues.firstIndex(of: Settings.windowGap) ?? 0
        gapControl.selectedSegment = idx

        loginCheck.state  = SMAppService.mainApp.status == .enabled ? .on : .off
        statusCheck.state = Settings.showStatusIndicators ? .on : .off
    }

    // MARK: - Actions

    @objc private func gapChanged() {
        let values = [0, 4, 8, 12]
        Settings.windowGap = values[gapControl.selectedSegment]
    }

    @objc private func loginChanged() {
        let svc = SMAppService.mainApp
        do {
            try loginCheck.state == .on ? svc.register() : svc.unregister()
        } catch {
            NSLog("[Tyler] LaunchAtLogin error: %@", error.localizedDescription)
            syncFromSettings()
        }
    }

    @objc private func statusChanged() {
        Settings.showStatusIndicators = statusCheck.state == .on
    }

    @objc private func resetAll() {
        let alert = NSAlert()
        alert.messageText     = "Reset All Settings?"
        alert.informativeText = "Window gap and other preferences will return to defaults."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Settings.reset()
        syncFromSettings()
    }

    // MARK: - Helpers

    private func label(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 13, weight: .medium)
        f.textColor = .labelColor
        return f
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let f = NSTextField(labelWithString: text.uppercased())
        f.font = .systemFont(ofSize: 11, weight: .semibold)
        f.textColor = .secondaryLabelColor
        return f
    }
}
