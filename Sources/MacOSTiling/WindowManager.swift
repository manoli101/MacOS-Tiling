import AppKit
import ApplicationServices

@MainActor
final class WindowManager {

    // MARK: - Window retrieval

    func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            NSLog("[Tyler] frontmostWindow: no frontmost application")
            return nil
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let win = axApp.focusedWindow ?? axApp.mainWindow
        if win == nil {
            NSLog("[Tyler] frontmostWindow: no AX window for %@ (pid=%d)", app.bundleIdentifier ?? "?", app.processIdentifier)
        }
        return win
    }

    func windowID(_ window: AXUIElement) -> String {
        "\(window.pid)|\(window.title ?? "")"
    }

    // MARK: - Frame  (AppKit coords: origin bottom-left of primary screen)

    func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let pt = window.axPosition, let sz = window.axSize else { return nil }
        return axToAppKit(point: pt, size: sz)
    }

    /// - bottomAnchored: anchors the window's bottom edge to `appKitFrame.minY`.
    ///   Use for bottom-half/quarter snaps so the Dock never clips content.
    func setFrame(_ window: AXUIElement, _ appKitFrame: CGRect, bottomAnchored: Bool = false) {
        let targetSize = CGSize(width: appKitFrame.width, height: appKitFrame.height)

        if bottomAnchored {
            window.setSize(targetSize)
            // Read back actual height — app may enforce a larger minimum.
            let actualH = window.axSize?.height ?? appKitFrame.height
            let origin = CGPoint(x: appKitFrame.minX,
                                 y: primaryH - appKitFrame.minY - actualH)
            window.setPosition(origin)
        } else {
            // Position first keeps macOS anchoring correct on Retina built-in displays.
            window.setPosition(appKitToAX(appKitFrame))
            window.setSize(targetSize)
        }
    }

    func minimize(_ window: AXUIElement) {
        window.set(kAXMinimizedAttribute, true)
    }

    func raise(_ window: AXUIElement) {
        window.set(kAXMainAttribute, true)
        NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    }

    // MARK: - Window search (used by SnapAssist, if re-enabled)

    func findAXWindow(pid: pid_t, title: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let wins = app.allWindows, !wins.isEmpty else { return nil }
        return wins.first { $0.title == title } ?? wins.first
    }

    // MARK: - Coordinate conversion
    // AX/Quartz: origin top-left of primary screen, y increases down.
    // AppKit:    origin bottom-left of primary screen, y increases up.

    private var primaryH: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
    }

    private func axToAppKit(point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: point.x, y: primaryH - point.y - size.height,
               width: size.width, height: size.height)
    }

    private func appKitToAX(_ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryH - rect.maxY)
    }
}
