// SPDX-License-Identifier: GPL-3.0-or-later
// Renders Stitchy's app icon into Stitchy/Resources/AppIcon.icns.
// Run: swift Scripts/make-icon.swift [preview.png]
//
// The folded-ribbon logo. Geometry and colours come from docs/logo/geometry.json,
// written by Scripts/make-logo-svg.py (which also writes the SVG and animated
// versions), so the icon and the SVGs always match.
import AppKit

let size: CGFloat = 1024
let args = CommandLine.arguments
let root = URL(fileURLWithPath: args[0]).deletingLastPathComponent().deletingLastPathComponent()

// geometry.json: shapes {name: {path: [[op, x, y, …]], gradient: {from, to, stops: [[offset, hex]]}}},
// order, gap (triangle) and creases ({a, b, into}).
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("docs/logo/geometry.json"))) as! [String: Any]
let shapes = json["shapes"] as! [String: [String: Any]]
let order = json["order"] as! [String]
let gapPoints = (json["gap"] as! [[Double]]).map { CGPoint(x: $0[0], y: $0[1]) }
let creases = json["creases"] as! [[String: [Double]]]

func color(_ hex: String, _ a: CGFloat = 1) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(srgbRed: CGFloat(n >> 16 & 0xff) / 255, green: CGFloat(n >> 8 & 0xff) / 255, blue: CGFloat(n & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// Builds a path from the same M/L/Q/Z commands the SVG uses.
func shapePath(_ name: String) -> CGPath {
    let path = CGMutablePath()
    for cmd in shapes[name]!["path"] as! [[Any]] {
        let op = cmd[0] as! String
        let n = cmd.dropFirst().map { CGFloat(($0 as! NSNumber).doubleValue) }
        switch op {
        case "M": path.move(to: CGPoint(x: n[0], y: n[1]))
        case "L": path.addLine(to: CGPoint(x: n[0], y: n[1]))
        case "Q": path.addQuadCurve(to: CGPoint(x: n[2], y: n[3]), control: CGPoint(x: n[0], y: n[1]))
        default: path.closeSubpath()
        }
    }
    return path
}

func fill(_ name: String, in ctx: CGContext) {
    let g = shapes[name]!["gradient"] as! [String: Any]
    let from = g["from"] as! [Double], to = g["to"] as! [Double]
    let stops = g["stops"] as! [[Any]]
    ctx.saveGState()
    ctx.addPath(shapePath(name)); ctx.clip()
    ctx.drawLinearGradient(gradient(stops.map { color($0[1] as! String) }, stops.map { CGFloat(($0[0] as! NSNumber).doubleValue) }),
                           start: CGPoint(x: from[0], y: from[1]), end: CGPoint(x: to[0], y: to[1]),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // SVG coordinates
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Outer blue glow, then the dark tile.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: color("#1E4BFF", 0.16))
    ctx.addPath(tile); ctx.setFillColor(color("#01030C")); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    ctx.drawLinearGradient(CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [color("#040A24"), color("#01030C"), color("#030820")] as CFArray, locations: [0, 0.5, 1])!,
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    // Inner edge glow: a shadow cast inward from everything outside the tile.
    ctx.setShadow(offset: .zero, blur: 60, color: color("#1F52FF", 0.95))
    let frame = CGMutablePath(); frame.addRect(tileRect.insetBy(dx: -300, dy: -300)); frame.addPath(tile)
    ctx.addPath(frame); ctx.setFillColor(color("#1F52FF")); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tile.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 4))
    ctx.setFillColor(color("#3D74FF", 0.55)); ctx.fillPath()
    ctx.restoreGState()

    // Glow behind the ribbon.
    let union = CGMutablePath()
    order.forEach { union.addPath(shapePath($0)) }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 56, color: color("#1E5BFF", 0.8))
    ctx.addPath(union); ctx.setFillColor(color("#1E5BFF", 0.55)); ctx.fillPath()
    ctx.restoreGState()

    // The ribbon: the fold, its crease shading, then the bands.
    fill("fold", in: ctx)
    for c in creases {
        let a = c["a"]!, b = c["b"]!, into = c["into"]!
        let mid = CGPoint(x: (a[0] + b[0]) / 2, y: (a[1] + b[1]) / 2)
        ctx.saveGState()
        ctx.addPath(shapePath("fold")); ctx.clip()
        ctx.drawLinearGradient(gradient([color("#020A40", 0.32), color("#020A40", 0)], [0, 1]),
                               start: mid, end: CGPoint(x: mid.x + into[0] * 38, y: mid.y + into[1] * 38), options: [.drawsBeforeStartLocation])
        ctx.restoreGState()
    }
    fill("top", in: ctx)
    fill("bottom", in: ctx)
    let gap = CGMutablePath()
    gap.addLines(between: gapPoints); gap.closeSubpath()
    ctx.addPath(gap); ctx.setFillColor(color("#01030C")); ctx.fillPath()
    // Fine light lines on the creases, brightest at the bend.
    for c in creases {
        let a = CGPoint(x: c["a"]![0], y: c["a"]![1]), b = CGPoint(x: c["b"]![0], y: c["b"]![1])
        ctx.saveGState()
        let line = CGMutablePath(); line.move(to: a); line.addLine(to: b)
        ctx.addPath(line.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 4)); ctx.clip()
        ctx.drawLinearGradient(gradient([color("#E6F7FF", 0), color("#E6F7FF", 0.45), color("#F4FCFF", 0.9)], [0, 0.55, 1]),
                               start: a, end: b, options: [])
        ctx.restoreGState()
    }
}

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = g
    g.cgContext.interpolationQuality = .high
    g.cgContext.scaleBy(x: CGFloat(px) / size, y: CGFloat(px) / size)
    draw(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

if args.count > 1 {
    try render(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
    try render(64).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1].replacingOccurrences(of: ".png", with: "-64.png")))
    exit(0)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(base * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Stitchy/Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
