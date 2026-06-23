import AppKit
import ApplicationServices

@MainActor
final class WindowManager {

    // MARK: - Window retrieval

    func frontmostWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return axApp.focusedWindow ?? axApp.mainWindow
    }

    func windowID(_ window: AXUIElement) -> String {
        "\(window.pid)|\(window.title ?? "")"
    }

    // MARK: - Frame  (AppKit coords: origin bottom-left of primary screen)

    func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let pt = window.axPosition, let sz = window.axSize else { return nil }
        return axToAppKit(point: pt, size: sz)
    }

    /// bottomAnchored: anchors the window's bottom edge to `appKitFrame.minY`.
    /// Use for bottom-half/quarter snaps so the Dock never clips content.
    func setFrame(_ window: AXUIElement, _ appKitFrame: CGRect, bottomAnchored: Bool = false) {
        let targetSize = CGSize(width: appKitFrame.width, height: appKitFrame.height)

        if bottomAnchored {
            window.setSize(targetSize)
            let actualH = window.axSize?.height ?? appKitFrame.height
            let origin  = CGPoint(x: appKitFrame.minX,
                                  y: primaryH - appKitFrame.minY - actualH)
            window.setPosition(origin)
        } else {
            window.setPosition(appKitToAX(appKitFrame))
            window.setSize(targetSize)
        }
    }

    func minimize(_ window: AXUIElement) {
        window.set(kAXMinimizedAttribute, true)
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
