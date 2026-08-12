// Renders AppIcon.icns. The menu bar glyph is an SF Symbol, which Apple's license
// forbids using as an app icon, so the icon is drawn from scratch here.
//
//   swift Tools/make-icon.swift
//
import AppKit
import Foundation

func drawIcon(pixels: Int) -> Data? {
    let s = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let margin = s * 0.075
    let plate = NSRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let squircle = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.2237, yRadius: plate.width * 0.2237)
    NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.60, blue: 0.96, alpha: 1),
               ending: NSColor(srgbRed: 0.08, green: 0.19, blue: 0.44, alpha: 1))?.draw(in: squircle, angle: -90)

    let center = NSPoint(x: s / 2, y: s * 0.42)
    let radius = s * 0.235

    let dial = NSBezierPath()
    dial.appendArc(withCenter: center, radius: radius, startAngle: 205, endAngle: -25, clockwise: true)
    dial.lineWidth = s * 0.072
    dial.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    dial.stroke()

    let angle = CGFloat.pi * 0.73
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.95, y: center.y + sin(angle) * radius * 0.95))
    needle.lineWidth = s * 0.055
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()

    let hub = s * 0.048
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, scale) pairs iconutil expects.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (points, scale) in variants {
    guard let data = drawIcon(pixels: points * scale) else { continue }
    let suffix = scale == 1 ? "" : "@2x"
    try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}
print(iconset.path)
