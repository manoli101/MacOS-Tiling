import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        checkAccessibility()
        hotkeyManager.start()
        // Refresh menu every 3 s so status updates after permission is granted
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
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
        button.title = "⊞"
        button.toolTip = "MacOS Tiling"
        statusItem?.menu = buildMenu()
    }

    private func rebuildMenu() {
        statusItem?.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let axOK  = AXIsProcessTrusted()
        let tapOK = hotkeyManager.tapIsActive

        let menu = NSMenu()
        menu.addItem(header("MacOS Tiling"))
        menu.addItem(.separator())
        menu.addItem(info(axOK  ? "✅ Accessibility: granted"      : "❌ Accessibility: NOT granted"))
        menu.addItem(info(tapOK ? "✅ Event tap: active"           : "⏳ Event tap: waiting for permission…"))
        if !axOK {
            menu.addItem(.separator())
            let fix = NSMenuItem(title: "  → Go to Accessibility Settings",
                                 action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
            menu.addItem(info("  Toggle OFF then ON for MacOSTiling"))
        }
        menu.addItem(.separator())
        menu.addItem(header("⌥ + Arrow keys"))
        menu.addItem(info("→   Right half  → next monitor"))
        menu.addItem(info("←   Left half   → prev monitor"))
        menu.addItem(info("↑   Top half → maximize"))
        menu.addItem(info("↓   Restore → minimize"))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

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

    // MARK: - Accessibility permission

    private func checkAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(opts) else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showAccessibilityAlert()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Needed"
        alert.informativeText = """
            MacOS Tiling needs Accessibility access to move and resize windows.

            Go to:  System Settings → Privacy & Security → Accessibility
            Then toggle MacOSTiling OFF then ON.

            The app will activate automatically — no restart needed.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }
}
