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

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildMenu()
                self?.updateLayoutIcon()
            }
        }
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuildMenu()
                self?.updateLayoutIcon()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLayoutIcon() }
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

        if Settings.showStatusIndicators {
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
        }

        menu.addItem(header("⌥ + Arrow keys"))
        menu.addItem(info("→   Right half  →  next monitor"))
        menu.addItem(info("←   Left half   →  prev monitor"))
        menu.addItem(info("↑   Top half  →  maximize"))
        menu.addItem(info("↓   Center  →  restore  →  minimize"))

        menu.addItem(.separator())
        menu.addItem(link("Preferences…", #selector(openPreferences)))
        menu.items.last?.keyEquivalent = ","
        menu.addItem(.separator())
        menu.addItem(link("☕  Buy me a coffee", #selector(openSponsors)))
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    // MARK: - Actions

    @objc private func openPreferences() {
        PreferencesWindowController.shared.show()
    }

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
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

    // MARK: - Layout icon

    private enum LayoutCell: Hashable { case topLeft, topRight, bottomLeft, bottomRight }

    private func updateLayoutIcon() {
        guard let button = statusItem?.button else { return }
        guard Settings.showLayoutInStatusIcon else {
            button.image = layoutIcon(cells: [.topLeft, .topRight, .bottomLeft, .bottomRight])
            return
        }
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let cells  = occupiedLayoutCells(on: screen)
        button.image = layoutIcon(cells: cells)
    }

    private func occupiedLayoutCells(on screen: NSScreen) -> Set<LayoutCell> {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let mainH = NSScreen.screens.first?.frame.height ?? 0
        var result = Set<LayoutCell>()

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int32, layer == 0,
                  let bd = info[kCGWindowBounds as String] as? [String: Any] else { continue }

            let x = (bd["X"] as? CGFloat) ?? 0
            let y = (bd["Y"] as? CGFloat) ?? 0
            let w = (bd["Width"]  as? CGFloat) ?? 0
            let h = (bd["Height"] as? CGFloat) ?? 0
            guard w > 150, h > 150 else { continue }

            // Convert from CG coords (y=0 top) to AppKit coords (y=0 bottom)
            let appKitFrame = CGRect(x: x, y: mainH - y - h, width: w, height: h)
            guard screen.frame.intersects(appKitFrame) else { continue }

            result.formUnion(cellsMatching(appKitFrame, on: screen))
        }
        return result
    }

    private func cellsMatching(_ frame: CGRect, on screen: NSScreen) -> Set<LayoutCell> {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        let t: CGFloat = 45  // pixel tolerance

        func close(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < t && abs(a.maxX - b.maxX) < t &&
            abs(a.minY - b.minY) < t && abs(a.maxY - b.maxY) < t
        }

        let maxF = g > 0 ? f.insetBy(dx: g, dy: g) : f
        if close(frame, maxF) { return [.topLeft, .topRight, .bottomLeft, .bottomRight] }

        let lh = CGRect(x: f.minX+g,   y: f.minY+g, width: f.width/2-g*1.5, height: f.height-g*2)
        if close(frame, lh) { return [.topLeft, .bottomLeft] }

        let rh = CGRect(x: f.midX+g/2, y: f.minY+g, width: f.width/2-g*1.5, height: f.height-g*2)
        if close(frame, rh) { return [.topRight, .bottomRight] }

        let th = CGRect(x: f.minX+g, y: f.midY+g/2, width: f.width-g*2, height: f.height/2-g*1.5)
        if close(frame, th) { return [.topLeft, .topRight] }

        let bh = CGRect(x: f.minX+g, y: f.minY+g, width: f.width-g*2, height: f.height/2-g*1.5)
        if close(frame, bh) { return [.bottomLeft, .bottomRight] }

        let tl = CGRect(x: f.minX+g,   y: f.midY+g/2, width: f.width/2-g*1.5, height: f.height/2-g*1.5)
        if close(frame, tl) { return [.topLeft] }

        let tr = CGRect(x: f.midX+g/2, y: f.midY+g/2, width: f.width/2-g*1.5, height: f.height/2-g*1.5)
        if close(frame, tr) { return [.topRight] }

        let bl = CGRect(x: f.minX+g,   y: f.minY+g, width: f.width/2-g*1.5, height: f.height/2-g*1.5)
        if close(frame, bl) { return [.bottomLeft] }

        let br = CGRect(x: f.midX+g/2, y: f.minY+g, width: f.width/2-g*1.5, height: f.height/2-g*1.5)
        if close(frame, br) { return [.bottomRight] }

        return []
    }

    private func layoutIcon(cells: Set<LayoutCell>) -> NSImage {
        let s: CGFloat = 16
        let m: CGFloat = 1     // margin
        let g: CGFloat = 1.5   // gap between cells
        let c: CGFloat = (s - 2*m - g) / 2   // cell size ≈ 6.75

        let positions: [(LayoutCell, CGRect)] = [
            (.topLeft,    CGRect(x: m,     y: m+c+g, width: c, height: c)),
            (.topRight,   CGRect(x: m+c+g, y: m+c+g, width: c, height: c)),
            (.bottomLeft, CGRect(x: m,     y: m,      width: c, height: c)),
            (.bottomRight,CGRect(x: m+c+g, y: m,      width: c, height: c)),
        ]

        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            for (cell, rect) in positions {
                let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
                if cells.contains(cell) {
                    NSColor.black.withAlphaComponent(0.85).setFill()
                    path.fill()
                } else {
                    NSColor.black.withAlphaComponent(0.28).setStroke()
                    path.lineWidth = 0.8
                    path.stroke()
                }
            }
            return true
        }
        img.isTemplate = true  // adapts to dark/light mode
        return img
    }
}
