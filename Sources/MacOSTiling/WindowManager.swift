import AppKit
import ApplicationServices

@MainActor
final class WindowManager {

    // MARK: - Window retrieval

    func frontmostWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appRef else { return nil }
        let app = appRef as! AXUIElement  // swiftlint:disable:this force_cast

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef else { return nil }
        return (winRef as! AXUIElement)
    }

    /// Stable string key for tracking a window across key presses.
    func windowID(_ window: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        return "\(pid)|\(title)"
    }

    // MARK: - Frame (AppKit screen coordinates: origin bottom-left of primary screen)

    func getFrame(_ window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }

        var axPoint = CGPoint.zero
        var axSize = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &axPoint),  // swiftlint:disable:this force_cast
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &axSize) else { return nil }  // swiftlint:disable:this force_cast

        return axToAppKit(point: axPoint, size: axSize)
    }

    /// - bottomAnchored: if true, anchors the BOTTOM edge of the window to appKitFrame.minY.
    ///   Use for bottom-half/quarter snaps so content at the bottom (e.g. input bars) is never
    ///   hidden behind the Dock, even when the app enforces a minimum window height.
    func setFrame(_ window: AXUIElement, _ appKitFrame: CGRect, bottomAnchored: Bool = false) {
        let h = primaryScreenHeight()

        // Always set size first so the app resizes before we compute the final position.
        var axSize = CGSize(width: appKitFrame.width, height: appKitFrame.height)
        if let sizeVal = AXValueCreate(.cgSize, &axSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
        }

        let axPoint: CGPoint
        if bottomAnchored {
            // Read back the actual height (app may have enforced a larger minimum).
            var actualHeight = appKitFrame.height
            var sizeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let sr = sizeRef {
                var sz = CGSize.zero
                AXValueGetValue(sr as! AXValue, .cgSize, &sz)  // swiftlint:disable:this force_cast
                actualHeight = sz.height
            }
            // Anchor bottom edge of window at appKitFrame.minY (top of Dock).
            axPoint = CGPoint(x: appKitFrame.minX, y: h - appKitFrame.minY - actualHeight)
        } else {
            axPoint = appKitToAxOrigin(appKitFrame)
        }

        var pt = axPoint
        if let posVal = AXValueCreate(.cgPoint, &pt) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
    }

    func minimize(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, true as CFTypeRef)
    }

    func pid(_ window: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        return p
    }

    func findAXWindow(pid: pid_t, title: String) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement], !wins.isEmpty else { return nil }
        for w in wins {
            var tRef: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &tRef)
            if (tRef as? String) == title { return w }
        }
        return wins.first
    }

    func raise(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFTypeRef)
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        NSRunningApplication(processIdentifier: p)?.activate(options: [])
    }

    // MARK: - Coordinate conversion

    // AX uses Quartz coords: (0,0) at top-left of primary screen, y increases down.
    // AppKit uses: (0,0) at bottom-left of primary screen, y increases up.
    // NSScreen.visibleFrame is in AppKit coords.

    private func primaryScreenHeight() -> CGFloat {
        // The primary screen has its origin at (0,0) in AppKit coords.
        return NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    private func axToAppKit(point: CGPoint, size: CGSize) -> CGRect {
        let h = primaryScreenHeight()
        // AX y is distance from top; AppKit y is distance from bottom.
        let appKitY = h - point.y - size.height
        return CGRect(x: point.x, y: appKitY, width: size.width, height: size.height)
    }

    private func appKitToAxOrigin(_ rect: CGRect) -> CGPoint {
        let h = primaryScreenHeight()
        return CGPoint(x: rect.origin.x, y: h - rect.maxY)
    }
}
