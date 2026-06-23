import AppKit

@MainActor
final class DragSnapManager {
    private let windowManager: WindowManager

    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor: Any?

    // Drag state
    private var dragStart: CGPoint = .zero
    private var isDraggingFar = false
    private var trackedWindow: AXUIElement?
    private var initialWindowFrame: CGRect?

    // Snap state
    private var currentZone: SnapZone?
    private var overlayPanel: NSPanel?

    private let edgeThreshold: CGFloat = 24
    private let cornerThreshold: CGFloat = 60
    private let dragThreshold: CGFloat = 8

    enum SnapZone: Equatable {
        case leftHalf, rightHalf, maximize
        case topLeft, topRight, bottomLeft, bottomRight

        func frame(on screen: NSScreen) -> CGRect {
            let f = screen.visibleFrame
            switch self {
            case .leftHalf:    return CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height)
            case .rightHalf:   return CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height)
            case .maximize:    return f
            case .topLeft:     return CGRect(x: f.minX, y: f.midY, width: f.width / 2, height: f.height / 2)
            case .topRight:    return CGRect(x: f.midX, y: f.midY, width: f.width / 2, height: f.height / 2)
            case .bottomLeft:  return CGRect(x: f.minX, y: f.minY, width: f.width / 2, height: f.height / 2)
            case .bottomRight: return CGRect(x: f.midX, y: f.minY, width: f.width / 2, height: f.height / 2)
            }
        }
    }

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.onDown()
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.onDrag()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            self?.onUp()
        }
    }

    // MARK: - Mouse handlers

    private func onDown() {
        dragStart = NSEvent.mouseLocation
        isDraggingFar = false
        trackedWindow = nil
        initialWindowFrame = nil
    }

    private func onDrag() {
        let pos = NSEvent.mouseLocation
        if !isDraggingFar {
            guard hypot(pos.x - dragStart.x, pos.y - dragStart.y) > dragThreshold else { return }
            isDraggingFar = true
            // Capture window reference now that we know something is being dragged
            trackedWindow = windowManager.frontmostWindow()
            initialWindowFrame = trackedWindow.flatMap { windowManager.getFrame($0) }
        }

        let newZone = zone(at: pos)
        guard newZone != currentZone else { return }
        currentZone = newZone

        if let z = newZone, let scr = screen(at: pos) {
            showOverlay(frame: z.frame(on: scr))
        } else {
            hideOverlay()
        }
    }

    private func onUp() {
        let zone = currentZone
        currentZone = nil
        isDraggingFar = false
        hideOverlay()

        guard let zone,
              let win = trackedWindow,
              let initFrame = initialWindowFrame,
              let nowFrame = windowManager.getFrame(win) else {
            trackedWindow = nil; initialWindowFrame = nil
            return
        }

        // Only snap if the window actually moved (it was dragged, not a text selection)
        let moved = abs(nowFrame.minX - initFrame.minX) > 5 || abs(nowFrame.minY - initFrame.minY) > 5
        if moved {
            let scr = screen(at: NSEvent.mouseLocation) ?? NSScreen.main!
            let bottomAnchored = (zone == .bottomLeft || zone == .bottomRight)
            windowManager.setFrame(win, zone.frame(on: scr), bottomAnchored: bottomAnchored)
        }

        trackedWindow = nil
        initialWindowFrame = nil
    }

    // MARK: - Zone detection

    private func zone(at pos: CGPoint) -> SnapZone? {
        guard let scr = screen(at: pos) else { return nil }
        let f = scr.frame  // full screen frame in AppKit coords
        let e = edgeThreshold
        let c = cornerThreshold

        let atLeft  = pos.x <= f.minX + e
        let atRight = pos.x >= f.maxX - e
        let atTop   = pos.y >= f.maxY - e    // AppKit: y=0 bottom, maxY = top

        let atLeftC  = pos.x <= f.minX + c
        let atRightC = pos.x >= f.maxX - c
        let atTopC   = pos.y >= f.maxY - c
        let atBotC   = pos.y <= f.minY + c

        // Corners have larger hit area
        if atLeftC  && atTopC  { return .topLeft }
        if atRightC && atTopC  { return .topRight }
        if atLeftC  && atBotC  { return .bottomLeft }
        if atRightC && atBotC  { return .bottomRight }

        // Edges
        if atLeft  { return .leftHalf }
        if atRight { return .rightHalf }
        if atTop   { return .maximize }
        return nil
    }

    private func screen(at pos: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(pos) }
    }

    // MARK: - Overlay

    private func showOverlay(frame: CGRect) {
        if let p = overlayPanel {
            p.setFrame(frame, display: true, animate: false)
            return
        }

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.alphaValue = 0

        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        overlay.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.6).cgColor
        overlay.layer?.borderWidth = 2
        overlay.layer?.cornerRadius = 12
        p.contentView = overlay

        overlayPanel = p
        p.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 1
        }
    }

    private func hideOverlay() {
        guard let p = overlayPanel else { return }
        overlayPanel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            p.animator().alphaValue = 0
        }, completionHandler: {
            DispatchQueue.main.async { p.close() }
        })
    }
}
