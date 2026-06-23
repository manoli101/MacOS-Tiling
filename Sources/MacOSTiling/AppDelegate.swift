import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()

    private let firstLaunchKey   = "firstLaunchDate"
    private let reminderShownKey = "donationReminderShown"

    // MARK: - App lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        requestPermissions()
        hotkeyManager.start()
        trackFirstLaunch()
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildMenu() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        if let img = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Tyler") {
            img.isTemplate = true
            button.image = img
        } else {
            button.title = "⊞"
        }
        button.toolTip = "Tyler"
        statusItem?.menu = buildMenu()
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let axOK    = AXIsProcessTrusted()
        let inputOK = CGPreflightListenEventAccess()
        let tapOK   = hotkeyManager.tapIsActive

        let menu = NSMenu()
        menu.addItem(header("Tyler"))
        menu.addItem(.separator())
        menu.addItem(status(axOK,    "Accessibility"))
        menu.addItem(status(inputOK, "Input Monitoring"))
        menu.addItem(status(tapOK,   "Event tap"))

        if !axOK {
            menu.addItem(.separator())
            menu.addItem(link("→ Accessibility Settings", #selector(openAccessibilitySettings)))
            menu.addItem(info("Toggle Tyler OFF then ON"))
        }
        if !inputOK {
            menu.addItem(.separator())
            menu.addItem(link("→ Input Monitoring Settings", #selector(openInputMonitoringSettings)))
        }

        menu.addItem(.separator())
        menu.addItem(header("⌥ + Arrow keys"))
        menu.addItem(info("→   Right half  →  next monitor"))
        menu.addItem(info("←   Left half   →  prev monitor"))
        menu.addItem(info("↑   Top half  →  maximize"))
        menu.addItem(info("↓   Center  →  restore  →  minimize"))

        menu.addItem(.separator())
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state  = SMAppService.mainApp.status == .enabled ? .on : .off
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(link("☕  Buy me a coffee", #selector(openSponsors)))
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @objc private func toggleLaunchAtLogin() {
        let svc = SMAppService.mainApp
        do {
            try svc.status == .enabled ? svc.unregister() : svc.register()
        } catch {
            NSLog("[Tyler] Launch at Login toggle failed: %@", error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func openSponsors() {
        open("https://github.com/sponsors/manoli101")
    }

    // MARK: - Permissions

    private func requestPermissions() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showAccessibilityAlert()
            }
        }
        if !CGPreflightListenEventAccess() { CGRequestListenEventAccess() }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText     = "Accessibility Permission Needed"
        alert.informativeText = "Tyler needs Accessibility to move and resize windows.\n\nGo to System Settings → Privacy & Security → Accessibility, then toggle Tyler OFF then ON."
        alert.alertStyle      = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
    }

    // MARK: - Donation reminder (once, after 7 days of use)

    private func trackFirstLaunch() {
        let d = UserDefaults.standard
        if d.object(forKey: firstLaunchKey) == nil {
            d.set(Date().timeIntervalSince1970, forKey: firstLaunchKey)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showReminderIfNeeded()
        }
    }

    private func showReminderIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: reminderShownKey),
              let ts = d.object(forKey: firstLaunchKey) as? Double,
              Date().timeIntervalSince1970 - ts >= 7 * 86_400 else { return }
        d.set(true, forKey: reminderShownKey)

        let alert = NSAlert()
        alert.messageText     = "¿Te está siendo útil Tyler?"
        alert.informativeText = "Si la app te ahorra tiempo, considera invitarme un café — me ayuda a seguir mejorándola ☕"
        alert.addButton(withTitle: "Claro que sí 🎉")
        alert.addButton(withTitle: "Ahora no")
        if alert.runModal() == .alertFirstButtonReturn { openSponsors() }
    }

    // MARK: - Menu helpers

    private func header(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func info(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: "  \(text)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func status(_ ok: Bool, _ label: String) -> NSMenuItem {
        info((ok ? "✅" : "❌") + " \(label)")
    }

    private func link(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "  \(title)", action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
