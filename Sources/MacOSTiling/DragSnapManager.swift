import AppKit

@MainActor
final class DragSnapManager {
    private let windowManager: WindowManager

    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor:   Any?

    private var dragStart:      CGPoint = .zero
    private var isDraggingFar   = false
    private var trackedWindow:  AXUIElement?
    private var initialFrame:   CGRect?
    private var currentZone:    SnapZone?
    private var zoneIndicator:  ZoneIndicatorWindow?

    private let edgeThreshold:   CGFloat = 80
    private let cornerThreshold: CGFloat = 120
    private let dragThreshold:   CGFloat = 8

    enum SnapZone: Equatable, CaseIterable {
        case leftHalf, rightHalf, maximize
        case topLeft, topRight, bottomLeft, bottomRight

        @MainActor func frame(on screen: NSScreen) -> CGRect {
            let f = screen.visibleFrame
            let g = CGFloat(Settings.windowGap)
            switch self {
            case .leftHalf:    return CGRect(x: f.minX+g,   y: f.minY+g,   width: f.width/2-g*1.5,  height: f.height-g*2)
            case .rightHalf:   return CGRect(x: f.midX+g/2, y: f.minY+g,   width: f.width/2-g*1.5,  height: f.height-g*2)
            case .maximize:    return g > 0 ? f.insetBy(dx: g, dy: g) : f
            case .topLeft:     return CGRect(x: f.minX+g,   y: f.midY+g/2, width: f.width/2-g*1.5,  height: f.height/2-g*1.5)
            case .topRight:    return CGRect(x: f.midX+g/2, y: f.midY+g/2, width: f.width/2-g*1.5,  height: f.height/2-g*1.5)
            case .bottomLeft:  return CGRect(x: f.minX+g,   y: f.minY+g,   width: f.width/2-g*1.5,  height: f.height/2-g*1.5)
            case .bottomRight: return CGRect(x: f.midX+g/2, y: f.minY+g,   width: f.width/2-g*1.5,  height: f.height/2-g*1.5)
            }
        }
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.onDown() }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.onDrag() }
        upMonitor   = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp)     { [weak self] _ in self?.onUp() }
    }

    // MARK: - Mouse handlers

    private func onDown() {
        dragStart     = NSEvent.mouseLocation
        isDraggingFar = false
        trackedWindow = nil
        initialFrame  = nil
    }

    private func onDrag() {
        let pos = NSEvent.mouseLocation
        if !isDraggingFar {
            guard hypot(pos.x - dragStart.x, pos.y - dragStart.y) > dragThreshold else { return }
            isDraggingFar = true
            trackedWindow = windowManager.frontmostWindow()
            initialFrame  = trackedWindow.flatMap { windowManager.getFrame($0) }
        }
        guard isDraggingFar else { return }

        let newZone = zone(at: pos)
        guard newZone != currentZone else { return }
        currentZone = newZone

        if Settings.enableSnapOverlay {
            if let zone = newZone, let scr = screen(at: pos) {
                showIndicator(for: zone, on: scr)
            } else {
                hideIndicator()
            }
        }
    }

    private func onUp() {
        let zone = currentZone
        currentZone = nil
        isDraggingFar = false
        hideIndicator()

        guard let zone,
              let win      = trackedWindow,
              let initFrame = initialFrame,
              let nowFrame  = windowManager.getFrame(win) else {
            trackedWindow = nil; initialFrame = nil; return
        }

        let moved = abs(nowFrame.minX - initFrame.minX) > 5 || abs(nowFrame.minY - initFrame.minY) > 5
        if moved {
            let scr = screen(at: NSEvent.mouseLocation) ?? NSScreen.main!
            let bottomAnchored = zone == .bottomLeft || zone == .bottomRight
            windowManager.setFrame(win, zone.frame(on: scr), bottomAnchored: bottomAnchored)
        }
        trackedWindow = nil; initialFrame = nil
    }

    // MARK: - Zone detection

    private func zone(at pos: CGPoint) -> SnapZone? {
        guard let scr = screen(at: pos) else { return nil }
        let f = scr.frame
        let e = edgeThreshold
        let c = cornerThreshold
        let atLeft   = pos.x <= f.minX + e
        let atRight  = pos.x >= f.maxX - e
        let atTop    = pos.y >= f.maxY - e
        let atLeftC  = pos.x <= f.minX + c
        let atRightC = pos.x >= f.maxX - c
        let atTopC   = pos.y >= f.maxY - c
        let atBotC   = pos.y <= f.minY + c

        if atLeftC  && atTopC  { return .topLeft }
        if atRightC && atTopC  { return .topRight }
        if atLeftC  && atBotC  { return .bottomLeft }
        if atRightC && atBotC  { return .bottomRight }
        if atLeft  { return .leftHalf }
        if atRight { return .rightHalf }
        if atTop   { return .maximize }
        return nil
    }

    private func screen(at pos: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(pos) }
    }

    // MARK: - Indicator

    private func showIndicator(for zone: SnapZone, on screen: NSScreen) {
        let targetFrame = zone.frame(on: screen)
        if let ind = zoneIndicator {
            ind.animate(to: targetFrame)
        } else {
            zoneIndicator = ZoneIndicatorWindow(frame: targetFrame)
        }
    }

    private func hideIndicator() {
        zoneIndicator?.fadeOut { [weak self] in self?.zoneIndicator = nil }
    }
}

// MARK: - ZoneIndicatorWindow

@MainActor
final class ZoneIndicatorWindow: NSPanel {

    init(frame appKitFrame: CGRect) {
        super.init(
            contentRect: appKitFrame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false

        let v = NSView(frame: NSRect(origin: .zero, size: appKitFrame.size))
        v.wantsLayer = true
        let layer = v.layer!
        layer.cornerRadius = 14
        layer.backgroundColor = NSColor(red: 64/255, green: 207/255, blue: 200/255, alpha: 0.45).cgColor
        layer.borderColor     = NSColor(red: 10/255,  green: 158/255, blue: 151/255, alpha: 1.0).cgColor
        layer.borderWidth     = 2.5
        layer.shadowColor     = NSColor(red: 10/255,  green: 158/255, blue: 151/255, alpha: 0.6).cgColor
        layer.shadowRadius    = 18
        layer.shadowOpacity   = 1
        layer.shadowOffset    = .zero
        contentView = v

        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
    }

    func animate(to newFrame: CGRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
        }
        contentView?.frame = NSRect(origin: .zero, size: newFrame.size)
    }

    func fadeOut(completion: @escaping () -> Void) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
            completion()
        })
    }
}
