#!/usr/bin/env swift
// Generates MacOSTiling.iconset PNGs and converts to .icns
import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setFillColor(NSColor.clear.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    let pad = s * 0.08
    let radius = s * 0.14

    // Background: dark blue-gray rounded square
    let bgRect = CGRect(x: pad, y: pad, width: s - pad*2, height: s - pad*2)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    NSColor(red: 0.13, green: 0.16, blue: 0.22, alpha: 1).setFill()
    bgPath.fill()

    // Four quadrant lines (cross divider) — lighter than bg
    let midX = s / 2
    let midY = s / 2
    let lineInset = s * 0.15
    let lineWidth = max(1, s * 0.025)
    NSColor(white: 0.4, alpha: 0.6).setStroke()
    let crossPath = NSBezierPath()
    crossPath.lineWidth = lineWidth
    crossPath.move(to: NSPoint(x: midX, y: pad + lineInset))
    crossPath.line(to: NSPoint(x: midX, y: s - pad - lineInset))
    crossPath.move(to: NSPoint(x: pad + lineInset, y: midY))
    crossPath.line(to: NSPoint(x: s - pad - lineInset, y: midY))
    crossPath.stroke()

    // Window tile — top-right quadrant highlight (accent)
    let tileInset = s * 0.18
    let gapHalf = lineWidth / 2 + s * 0.025
    let tileRect = CGRect(
        x: midX + gapHalf,
        y: midY + gapHalf,
        width: s - pad - tileInset - midX - gapHalf,
        height: s - pad - tileInset - midY - gapHalf
    )
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: radius * 0.5, yRadius: radius * 0.5)
    NSColor(red: 0.25, green: 0.55, blue: 1.0, alpha: 0.9).setFill()
    tilePath.fill()

    // Arrow pointing top-right inside the tile — white
    let arrowSize = tileRect.width * 0.55
    let ax = tileRect.midX
    let ay = tileRect.midY
    let hw = arrowSize * 0.5
    NSColor.white.setStroke()
    NSColor.white.setFill()
    let arrow = NSBezierPath()
    arrow.lineWidth = max(1, s * 0.035)
    arrow.lineCapStyle = .round
    // horizontal line
    arrow.move(to: NSPoint(x: ax - hw * 0.5, y: ay))
    arrow.line(to: NSPoint(x: ax + hw * 0.5, y: ay))
    // vertical line
    arrow.move(to: NSPoint(x: ax, y: ay - hw * 0.5))
    arrow.line(to: NSPoint(x: ax, y: ay + hw * 0.5))
    // arrowhead right
    arrow.move(to: NSPoint(x: ax + hw * 0.2, y: ay + hw * 0.25))
    arrow.line(to: NSPoint(x: ax + hw * 0.5, y: ay))
    arrow.line(to: NSPoint(x: ax + hw * 0.2, y: ay - hw * 0.25))
    arrow.stroke()

    image.unlockFocus()
    return image
}

let iconsetDir = "MacOSTiling.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetDir)
try! fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for size in sizes {
    for scale in [1, 2] {
        let px = size * scale
        let image = drawIcon(size: px)
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let path = "\(iconsetDir)/\(name)"
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              let png = bmp.representation(using: .png, properties: [:]) else {
            print("Failed to generate \(name)")
            continue
        }
        try! png.write(to: URL(fileURLWithPath: path))
        print("✓ \(name) (\(px)×\(px))")
    }
}

print("Running iconutil...")
