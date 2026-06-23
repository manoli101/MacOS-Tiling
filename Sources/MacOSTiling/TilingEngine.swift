import AppKit

@MainActor
final class TilingEngine {
    static let shared = TilingEngine()

    private struct WindowRecord {
        var state: TilingState
        var originalFrame: CGRect
        var lastInteraction: Date
    }

    private var records: [String: WindowRecord] = [:]
    private let timeout: TimeInterval = 3.0

    private init() {}

    func stateFor(windowID: String) -> TilingState {
        guard let r = records[windowID],
              Date().timeIntervalSince(r.lastInteraction) < timeout else { return .floating }
        return r.state
    }

    func handle(direction: Direction, windowID: String, currentFrame: CGRect) -> CGRect {
        let screens = sortedScreens()
        let now = Date()

        var record: WindowRecord
        if let existing = records[windowID], now.timeIntervalSince(existing.lastInteraction) < timeout {
            record = existing
        } else {
            record = WindowRecord(state: .floating, originalFrame: currentFrame, lastInteraction: now)
        }

        let currentScreenIdx = screenIndex(for: currentFrame, in: screens)
        let newState = transition(from: record.state, direction: direction,
                                  currentScreen: currentScreenIdx, screenCount: screens.count)

        let targetFrame: CGRect
        if newState == .floating {
            targetFrame = record.originalFrame
        } else {
            targetFrame = frame(for: newState, screens: screens)
        }

        record.state = newState
        record.lastInteraction = now
        records[windowID] = record

        return targetFrame
    }

    // MARK: - State transitions

    private func transition(from state: TilingState, direction: Direction,
                            currentScreen: Int, screenCount: Int) -> TilingState {
        let nextRight = min(currentScreen + 1, screenCount - 1)
        let nextLeft  = max(currentScreen - 1, 0)
        let hasRight  = currentScreen < screenCount - 1
        let hasLeft   = currentScreen > 0

        switch (state, direction) {
        // floating
        case (.floating, .right): return .rightHalf(screen: currentScreen)
        case (.floating, .left):  return .leftHalf(screen: currentScreen)
        case (.floating, .up):    return .topHalf(screen: currentScreen)
        case (.floating, .down):  return .centered(screen: currentScreen)

        // centered → arrows move to halves; down restores; double-down (minimize) handled in HotkeyManager
        case (.centered(let s), .right): return .rightHalf(screen: s)
        case (.centered(let s), .left):  return .leftHalf(screen: s)
        case (.centered(let s), .up):    return .maximized(screen: s)
        case (.centered, .down):  return .floating

        // rightHalf
        case (.rightHalf(_), .right):    return hasRight ? .rightHalf(screen: nextRight) : .floating
        case (.rightHalf(let s), .left): return .leftHalf(screen: s)
        case (.rightHalf(let s), .up):   return .topRight(screen: s)
        case (.rightHalf(let s), .down): return .bottomRight(screen: s)

        // leftHalf
        case (.leftHalf(_), .left):      return hasLeft ? .leftHalf(screen: nextLeft) : .floating
        case (.leftHalf(let s), .right): return .rightHalf(screen: s)
        case (.leftHalf(let s), .up):    return .topLeft(screen: s)
        case (.leftHalf(let s), .down):  return .bottomLeft(screen: s)

        // topHalf — estado intermedio; →/← seleccionan cuartos superiores en el mismo monitor
        case (.topHalf(let s), .right): return .topRight(screen: s)
        case (.topHalf(let s), .left):  return .topLeft(screen: s)
        case (.topHalf(let s), .up):    return .maximized(screen: s)
        case (.topHalf(_), .down):      return .floating

        // topRight
        case (.topRight(_), .right):    return hasRight ? .topRight(screen: nextRight) : .floating
        case (.topRight(let s), .left): return .topLeft(screen: s)
        case (.topRight(let s), .up):   return .maximized(screen: s)
        case (.topRight(let s), .down): return .rightHalf(screen: s)

        // topLeft
        case (.topLeft(_), .left):      return hasLeft ? .topLeft(screen: nextLeft) : .floating
        case (.topLeft(let s), .right): return .topRight(screen: s)
        case (.topLeft(let s), .up):    return .maximized(screen: s)
        case (.topLeft(let s), .down):  return .leftHalf(screen: s)

        // bottomRight
        case (.bottomRight(_), .right):    return hasRight ? .bottomRight(screen: nextRight) : .floating
        case (.bottomRight(let s), .left): return .bottomLeft(screen: s)
        case (.bottomRight(let s), .up):   return .rightHalf(screen: s)
        case (.bottomRight(_), .down):     return .floating

        // bottomLeft
        case (.bottomLeft(_), .left):      return hasLeft ? .bottomLeft(screen: nextLeft) : .floating
        case (.bottomLeft(let s), .right): return .bottomRight(screen: s)
        case (.bottomLeft(let s), .up):    return .leftHalf(screen: s)
        case (.bottomLeft(_), .down):      return .floating

        // maximized: ↓ restaura, ←/→ va a mitad, ↑ no hace nada
        case (.maximized(let s), .right): return .rightHalf(screen: s)
        case (.maximized(let s), .left):  return .leftHalf(screen: s)
        case (.maximized, .up):           return state
        case (.maximized(_), .down):      return .floating
        }
    }

    // MARK: - Frame calculations (AppKit coords: origin bottom-left)

    private func frame(for state: TilingState, screens: [NSScreen]) -> CGRect {
        switch state {
        case .floating:             return .zero
        case .centered(let s):      return centered(screens[s])
        case .leftHalf(let s):      return leftHalf(screens[s])
        case .rightHalf(let s):     return rightHalf(screens[s])
        case .topHalf(let s):       return topHalf(screens[s])
        case .topLeft(let s):       return topLeft(screens[s])
        case .topRight(let s):      return topRight(screens[s])
        case .bottomLeft(let s):    return bottomLeft(screens[s])
        case .bottomRight(let s):   return bottomRight(screens[s])
        case .maximized(let s):
            let g = CGFloat(Settings.windowGap)
            return g > 0 ? screens[s].visibleFrame.insetBy(dx: g, dy: g) : screens[s].visibleFrame
        }
    }

    private func centered(_ screen: NSScreen) -> CGRect {
        let sf = screen.frame
        let vf = screen.visibleFrame
        let w = sf.width  * 0.65
        let h = vf.height * 0.70
        let x = sf.midX - w / 2
        let y = vf.minY + (vf.height - h) * 0.45
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // Gap model: outer edges get g, shared inner edges get g/2 each side → gap between two tiles = g.
    // e.g. leftHalf right edge = midX - g/2, rightHalf left edge = midX + g/2 → gap = g. ✓

    private func topHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.midY + g/2,
                      width: f.width - g*2, height: f.height/2 - g*1.5)
    }

    private func leftHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g,
                      width: f.width/2 - g*1.5, height: f.height - g*2)
    }

    private func rightHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.minY + g,
                      width: f.width/2 - g*1.5, height: f.height - g*2)
    }

    private func topLeft(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.midY + g/2,
                      width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }

    private func topRight(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.midY + g/2,
                      width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }

    private func bottomLeft(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g,
                      width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }

    private func bottomRight(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame
        let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.minY + g,
                      width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }

    // MARK: - Screen helpers

    private func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    private func screenIndex(for windowFrame: CGRect, in screens: [NSScreen]) -> Int {
        let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        for (i, screen) in screens.enumerated() {
            if screen.frame.contains(center) { return i }
        }
        // Fallback: find screen with most overlap
        var bestIdx = 0
        var bestArea: CGFloat = 0
        for (i, screen) in screens.enumerated() {
            let overlap = screen.frame.intersection(windowFrame)
            let area = overlap.width * overlap.height
            if area > bestArea { bestArea = area; bestIdx = i }
        }
        return bestIdx
    }
}
