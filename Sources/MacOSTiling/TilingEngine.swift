import AppKit

@MainActor
final class TilingEngine {
    static let shared = TilingEngine()

    private struct WindowRecord {
        var state: TilingState
        var originalFrame: CGRect
        var previousFrame: CGRect?   // for undo
        var previousState: TilingState?
        var lastInteraction: Date
    }

    private var records: [String: WindowRecord] = [:]
    private let timeout: TimeInterval = 300.0  // 5 min — keeps undo/state alive across pauses

    private init() {}

    func stateFor(windowID: String) -> TilingState {
        guard let r = records[windowID],
              Date().timeIntervalSince(r.lastInteraction) < timeout else { return .floating }
        return r.state
    }

    // MARK: - Main handle

    func handle(direction: Direction, windowID: String, currentFrame: CGRect) -> CGRect {
        let screens = sortedScreens()
        let now = Date()

        var record: WindowRecord
        if let existing = records[windowID], now.timeIntervalSince(existing.lastInteraction) < timeout {
            record = existing
        } else {
            record = WindowRecord(state: .floating, originalFrame: currentFrame,
                                  previousFrame: nil, previousState: nil, lastInteraction: now)
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

        // Save undo snapshot before updating
        record.previousFrame = currentFrame
        record.previousState = record.state
        record.state = newState
        record.lastInteraction = now
        records[windowID] = record

        return targetFrame
    }

    // MARK: - Undo

    func undo(windowID: String) -> CGRect? {
        guard var record = records[windowID],
              let prev = record.previousFrame else { return nil }
        let frame = prev
        record.state = record.previousState ?? .floating
        record.previousFrame = nil
        record.previousState = nil
        record.lastInteraction = Date()
        records[windowID] = record
        return frame
    }

    // MARK: - Transitions

    private func transition(from state: TilingState, direction: Direction,
                            currentScreen: Int, screenCount: Int) -> TilingState {
        let nextRight = min(currentScreen + 1, screenCount - 1)
        let nextLeft  = max(currentScreen - 1, 0)
        let hasRight  = currentScreen < screenCount - 1
        let hasLeft   = currentScreen > 0
        let thirds    = Settings.enableThirds

        switch (state, direction) {

        // ── floating ──────────────────────────────────────────────────
        case (.floating, .right): return .rightHalf(screen: currentScreen)
        case (.floating, .left):  return .leftHalf(screen: currentScreen)
        case (.floating, .up):    return .topHalf(screen: currentScreen)
        case (.floating, .down):  return .centered(screen: currentScreen)

        // ── centered ──────────────────────────────────────────────────
        case (.centered(let s), .right): return .rightHalf(screen: s)
        case (.centered(let s), .left):  return .leftHalf(screen: s)
        case (.centered(let s), .up):    return .maximized(screen: s)
        case (.centered, .down):         return .floating

        // ── rightHalf ─────────────────────────────────────────────────
        case (.rightHalf(let s), .left): return .leftHalf(screen: s)
        case (.rightHalf(let s), .up):   return .topRight(screen: s)
        case (.rightHalf(let s), .down): return .bottomRight(screen: s)
        case (.rightHalf, .right) where hasRight: return .rightHalf(screen: nextRight)
        case (.rightHalf(let s), .right):
            return thirds ? .rightTwoThirds(screen: s) : .floating

        // ── leftHalf ──────────────────────────────────────────────────
        case (.leftHalf(let s), .right): return .rightHalf(screen: s)
        case (.leftHalf(let s), .up):    return .topLeft(screen: s)
        case (.leftHalf(let s), .down):  return .bottomLeft(screen: s)
        case (.leftHalf, .left) where hasLeft: return .leftHalf(screen: nextLeft)
        case (.leftHalf(let s), .left):
            return thirds ? .leftTwoThirds(screen: s) : .floating

        // ── topHalf ───────────────────────────────────────────────────
        case (.topHalf(let s), .right): return .topRight(screen: s)
        case (.topHalf(let s), .left):  return .topLeft(screen: s)
        case (.topHalf(let s), .up):    return .maximized(screen: s)
        case (.topHalf, .down):         return .floating

        // ── topRight ──────────────────────────────────────────────────
        case (.topRight, .right) where hasRight: return .topRight(screen: nextRight)
        case (.topRight(let s), .right): return .floating
        case (.topRight(let s), .left):  return .topLeft(screen: s)
        case (.topRight(let s), .up):    return .maximized(screen: s)
        case (.topRight(let s), .down):  return .rightHalf(screen: s)

        // ── topLeft ───────────────────────────────────────────────────
        case (.topLeft, .left) where hasLeft: return .topLeft(screen: nextLeft)
        case (.topLeft(let s), .left):   return .floating
        case (.topLeft(let s), .right):  return .topRight(screen: s)
        case (.topLeft(let s), .up):     return .maximized(screen: s)
        case (.topLeft(let s), .down):   return .leftHalf(screen: s)

        // ── bottomRight ───────────────────────────────────────────────
        case (.bottomRight, .right) where hasRight: return .bottomRight(screen: nextRight)
        case (.bottomRight(let s), .right): return .floating
        case (.bottomRight(let s), .left):  return .bottomLeft(screen: s)
        case (.bottomRight(let s), .up):    return .rightHalf(screen: s)
        case (.bottomRight, .down):         return .floating

        // ── bottomLeft ────────────────────────────────────────────────
        case (.bottomLeft, .left) where hasLeft: return .bottomLeft(screen: nextLeft)
        case (.bottomLeft(let s), .left):   return .floating
        case (.bottomLeft(let s), .right):  return .bottomRight(screen: s)
        case (.bottomLeft(let s), .up):     return .leftHalf(screen: s)
        case (.bottomLeft, .down):          return .floating

        // ── maximized ────────────────────────────────────────────────
        case (.maximized(let s), .right): return .rightHalf(screen: s)
        case (.maximized(let s), .left):  return .leftHalf(screen: s)
        case (.maximized, .up):           return state
        case (.maximized, .down):         return .floating

        // ── THIRDS ───────────────────────────────────────────────────

        // rightTwoThirds: cycling right → rightThird, left ↔ leftThird
        case (.rightTwoThirds(let s), .right): return thirds ? .rightThird(screen: s) : .floating
        case (.rightTwoThirds(let s), .left):  return thirds ? .leftThird(screen: s)  : .leftHalf(screen: s)
        case (.rightTwoThirds(let s), .up):    return .maximized(screen: s)
        case (.rightTwoThirds, .down):         return .floating

        // leftTwoThirds: cycling left → leftThird, right ↔ rightThird
        case (.leftTwoThirds(let s), .left):   return thirds ? .leftThird(screen: s)  : .floating
        case (.leftTwoThirds(let s), .right):  return thirds ? .rightThird(screen: s) : .rightHalf(screen: s)
        case (.leftTwoThirds(let s), .up):     return .maximized(screen: s)
        case (.leftTwoThirds, .down):          return .floating

        // rightThird (1/3): right → floating, left → centerThird
        case (.rightThird(let s), .left):  return thirds ? .centerThird(screen: s) : .leftHalf(screen: s)
        case (.rightThird(let s), .right) where hasRight: return .rightThird(screen: nextRight)
        case (.rightThird, .right):        return .floating
        case (.rightThird(let s), .up):    return .maximized(screen: s)
        case (.rightThird, .down):         return .floating

        // leftThird (1/3): left → floating, right → centerThird
        case (.leftThird(let s), .right):  return thirds ? .centerThird(screen: s) : .rightHalf(screen: s)
        case (.leftThird(let s), .left) where hasLeft: return .leftThird(screen: nextLeft)
        case (.leftThird, .left):          return .floating
        case (.leftThird(let s), .up):     return .maximized(screen: s)
        case (.leftThird, .down):          return .floating

        // centerThird: left → leftThird, right → rightThird
        case (.centerThird(let s), .left):  return thirds ? .leftThird(screen: s)  : .leftHalf(screen: s)
        case (.centerThird(let s), .right): return thirds ? .rightThird(screen: s) : .rightHalf(screen: s)
        case (.centerThird(let s), .up):    return .maximized(screen: s)
        case (.centerThird, .down):         return .floating
        }
    }

    // MARK: - Frame calculations

    private func frame(for state: TilingState, screens: [NSScreen]) -> CGRect {
        switch state {
        case .floating:                return .zero
        case .centered(let s):         return centered(screens[s])
        case .leftHalf(let s):         return leftHalf(screens[s])
        case .rightHalf(let s):        return rightHalf(screens[s])
        case .topHalf(let s):          return topHalf(screens[s])
        case .topLeft(let s):          return topLeft(screens[s])
        case .topRight(let s):         return topRight(screens[s])
        case .bottomLeft(let s):       return bottomLeft(screens[s])
        case .bottomRight(let s):      return bottomRight(screens[s])
        case .maximized(let s):
            let g = CGFloat(Settings.windowGap)
            return g > 0 ? screens[s].visibleFrame.insetBy(dx: g, dy: g) : screens[s].visibleFrame
        case .leftThird(let s):        return leftThird(screens[s])
        case .centerThird(let s):      return centerThird(screens[s])
        case .rightThird(let s):       return rightThird(screens[s])
        case .leftTwoThirds(let s):    return leftTwoThirds(screens[s])
        case .rightTwoThirds(let s):   return rightTwoThirds(screens[s])
        }
    }

    // MARK: - Half frames

    private func centered(_ screen: NSScreen) -> CGRect {
        let sf = screen.frame
        let vf = screen.visibleFrame
        let w = sf.width  * 0.65
        let h = vf.height * 0.70
        let x = sf.midX - w / 2
        let y = vf.minY + (vf.height - h) * 0.45
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // Gap model: outer edges +g, shared inner edges +g/2 each → g gap between tiles
    private func leftHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g, width: f.width/2 - g*1.5, height: f.height - g*2)
    }
    private func rightHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.minY + g, width: f.width/2 - g*1.5, height: f.height - g*2)
    }
    private func topHalf(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.midY + g/2, width: f.width - g*2, height: f.height/2 - g*1.5)
    }
    private func topLeft(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.midY + g/2, width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }
    private func topRight(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.midY + g/2, width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }
    private func bottomLeft(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g, width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }
    private func bottomRight(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.midX + g/2, y: f.minY + g, width: f.width/2 - g*1.5, height: f.height/2 - g*1.5)
    }

    // MARK: - Thirds frames
    // Gap model for thirds: outer edges +g, inner shared edges +g/2 each → g gap between tiles

    private func leftThird(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g,
                      width: f.width/3 - g*1.5, height: f.height - g*2)
    }
    private func centerThird(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + f.width/3 + g/2, y: f.minY + g,
                      width: f.width/3 - g, height: f.height - g*2)
    }
    private func rightThird(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + f.width*2/3 + g/2, y: f.minY + g,
                      width: f.width/3 - g*1.5, height: f.height - g*2)
    }
    private func leftTwoThirds(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + g, y: f.minY + g,
                      width: f.width*2/3 - g*1.5, height: f.height - g*2)
    }
    private func rightTwoThirds(_ screen: NSScreen) -> CGRect {
        let f = screen.visibleFrame; let g = CGFloat(Settings.windowGap)
        return CGRect(x: f.minX + f.width/3 + g/2, y: f.minY + g,
                      width: f.width*2/3 - g*1.5, height: f.height - g*2)
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
        var bestIdx = 0; var bestArea: CGFloat = 0
        for (i, screen) in screens.enumerated() {
            let area = screen.frame.intersection(windowFrame).width * screen.frame.intersection(windowFrame).height
            if area > bestArea { bestArea = area; bestIdx = i }
        }
        return bestIdx
    }
}
