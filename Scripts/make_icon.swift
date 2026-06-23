#!/usr/bin/env swift
// Tyler icon generator — Teal Snap × macOS 26 Liquid Glass
// Run from project root: swift Scripts/make_icon.swift
import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]

extension NSColor {
    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
    }
}

func makeGradient(_ colors: [NSColor], _ locs: [CGFloat] = [0, 1]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
               colors: colors.map(\.cgColor) as CFArray,
               locations: locs)!
}

func drawIcon(size: Int) -> NSImage {
    let S  = CGFloat(size)
    let f  = S / 512.0
    let detail = size >= 64

    let image = NSImage(size: NSSize(width: S, height: S))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    // SVG (top-left origin) → AppKit (bottom-left origin)
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x*f, y: S-(y+h)*f, width: w*f, height: h*f)
    }
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*f, y: S-y*f) }
    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: (cx-r)*f, y: S-(cy+r)*f, width: r*2*f, height: r*2*f))
    }

    ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

    // ── Icon squircle ────────────────────────────────────────────────────
    let rx = 116.0 * f
    let iconPath = NSBezierPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                                xRadius: rx, yRadius: rx)

    // ── Background: #f0fafa → #e4f4f4, diagonal + radial center glow ──
    ctx.saveGState()
    iconPath.addClip()
    ctx.drawLinearGradient(
        makeGradient([.rgb(240,250,250), .rgb(228,244,244)]),
        start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    let glowCtr = CGPoint(x: S*0.5, y: S*0.6)
    ctx.drawRadialGradient(
        makeGradient([NSColor(white:1,alpha:0.28), NSColor(white:1,alpha:0)]),
        startCenter: glowCtr, startRadius: 0,
        endCenter: glowCtr, endRadius: S*0.6, options: [])
    ctx.restoreGState()

    // ── Windows (SVG layout: pad=56, winSize=178, gap=44) ────────────────
    struct Win { let x, y: CGFloat; let teal: Bool }
    let wins: [Win] = [
        Win(x: 56,  y: 56,  teal: false),  // top-left
        Win(x: 278, y: 56,  teal: true),   // top-right — teal highlight
        Win(x: 56,  y: 278, teal: false),  // bottom-left
        Win(x: 278, y: 278, teal: false),  // bottom-right
    ]
    let wr: CGFloat = 26.0 * f   // window corner radius

    for win in wins {
        let wRect = R(win.x, win.y, 178, 178)
        let wPath = NSBezierPath(roundedRect: wRect, xRadius: wr, yRadius: wr)

        // 1. Drop shadow (paint solid white first to cast the shadow, gradient covers it next)
        ctx.saveGState()
        if win.teal {
            ctx.setShadow(offset: CGSize(width: 0, height: -8*f), blur: 18*f,
                          color: NSColor.rgb(10,158,151, 0.45).cgColor)
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: -4*f), blur: 7*f,
                          color: NSColor.rgb(0,140,130, 0.12).cgColor)
        }
        NSColor.white.setFill()
        wPath.fill()
        ctx.restoreGState()

        // 2. Fill (gradient paints over the white from step 1)
        ctx.saveGState()
        wPath.addClip()
        if win.teal {
            ctx.drawLinearGradient(
                makeGradient([.rgb(64,207,200), .rgb(10,158,151)]),
                start: CGPoint(x: wRect.midX, y: wRect.maxY),
                end:   CGPoint(x: wRect.midX + wRect.width*0.2, y: wRect.minY), options: [])
        } else {
            ctx.drawLinearGradient(
                makeGradient([NSColor(white:1,alpha:0.95), .rgb(210,245,245,0.45)]),
                start: CGPoint(x: wRect.minX, y: wRect.maxY),
                end:   CGPoint(x: wRect.minX, y: wRect.minY), options: [])
        }
        ctx.restoreGState()

        if detail {
            // 3. Title bar band
            let tbH: CGFloat = 30 * f
            let tbColor = win.teal ? NSColor(white:1,alpha:0.22) : NSColor(white:1,alpha:0.7)
            ctx.saveGState()
            wPath.addClip()
            tbColor.setFill()
            ctx.fill(CGRect(x: wRect.minX, y: wRect.maxY - tbH, width: wRect.width, height: tbH))
            ctx.restoreGState()

            // 4. Traffic lights (red / yellow / green)
            // SVG cy = win.y+15 (center of 30px title bar)
            let tlCY = win.y + 15
            let tlXs: [CGFloat] = [win.x+23, win.x+40, win.x+57]
            let tlColors: [NSColor] = [
                .rgb(255, 95, 90, win.teal ? 0.5 : 0.85),
                .rgb(255,190, 45, win.teal ? 0.5 : 0.85),
                .rgb( 45,200, 75, win.teal ? 0.5 : 0.85),
            ]
            for (i, color) in tlColors.enumerated() {
                color.setFill()
                circle(tlXs[i], tlCY, 6.5).fill()
            }

            // 5. Content lines
            let lineColor = win.teal ? NSColor(white:1,alpha:0.4) : NSColor.rgb(0,120,110,0.09)
            let lineX = win.x + 18
            let lineStartY = win.y + 50
            let lineDefs: [(CGFloat, CGFloat)] = [(126,0),(88,14),(108,28)]
            lineColor.setFill()
            ctx.saveGState()
            wPath.addClip()
            for (lw, dy) in lineDefs {
                let lr = R(lineX, lineStartY + dy, lw, 6)
                NSBezierPath(roundedRect: lr, xRadius: 3*f, yRadius: 3*f).fill()
            }
            ctx.restoreGState()

            // 6. Top-half glass sheen on teal window
            if win.teal {
                ctx.saveGState()
                wPath.addClip()
                ctx.drawLinearGradient(
                    makeGradient([NSColor(white:1,alpha:0.28), NSColor(white:1,alpha:0)]),
                    start: CGPoint(x: wRect.minX, y: wRect.maxY),
                    end:   CGPoint(x: wRect.minX, y: wRect.maxY - wRect.height*0.5), options: [])
                ctx.restoreGState()
            }
        }

        // 7. Border
        ctx.saveGState()
        wPath.addClip()
        (win.teal ? NSColor(white:1,alpha:0.5) : NSColor(white:1,alpha:0.95)).setStroke()
        wPath.lineWidth = 2 * f
        wPath.stroke()
        ctx.restoreGState()
    }

    // ── Snap arrow (center, sizes ≥ 64) ──────────────────────────────────
    if size >= 64 {
        // Halo
        NSColor.rgb(10,158,151, 0.10).setFill()
        circle(256, 256, 20).fill()

        // Arrow: M243 256 L269 256 (horizontal) + M261 245 L269 256 L261 267 (head)
        let arrow = NSBezierPath()
        arrow.lineWidth  = 6.5 * f
        arrow.lineCapStyle  = .round
        arrow.lineJoinStyle = .round
        NSColor.rgb(10,158,151).setStroke()
        arrow.move(to: P(243, 256)); arrow.line(to: P(269, 256))
        arrow.move(to: P(261, 245)); arrow.line(to: P(269, 256)); arrow.line(to: P(261, 267))
        arrow.stroke()
    }

    // ── Overall gloss (top half, white semi-transparent) ─────────────────
    ctx.saveGState()
    iconPath.addClip()
    ctx.drawLinearGradient(
        makeGradient([NSColor(white:1,alpha:0.65), NSColor(white:1,alpha:0)]),
        start: CGPoint(x: S/2, y: S), end: CGPoint(x: S/2, y: S*0.5), options: [])
    // Edge border highlight
    NSColor(white:1,alpha:0.75).setStroke()
    iconPath.lineWidth = 1.5 * f
    iconPath.stroke()
    ctx.restoreGState()

    return image
}

// ── Generate files ────────────────────────────────────────────────────────
let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent("Tyler.iconset")

try? fm.removeItem(at: iconsetURL)
try! fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for size in sizes {
    for scale in [1, 2] {
        if size == 1024 && scale == 2 { continue }  // 2048px not needed
        let px = size * scale
        let img = drawIcon(size: px)
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        guard let tiff = img.tiffRepresentation,
              let bmp  = NSBitmapImageRep(data: tiff),
              let png  = bmp.representation(using: .png, properties: [:]) else {
            print("✗ Failed: \(name)"); continue
        }
        try! png.write(to: iconsetURL.appendingPathComponent(name))
        print("✓ \(name) (\(px)×\(px))")
    }
}

print("▶ Running iconutil…")
let task = Process()
task.launchPath = "/usr/bin/iconutil"
task.arguments  = ["-c", "icns", "Tyler.iconset", "-o", "Tyler.icns"]
task.launch()
task.waitUntilExit()

if task.terminationStatus == 0 {
    print("✅  Tyler.icns ready")
} else {
    print("✗ iconutil failed (\(task.terminationStatus))")
}
