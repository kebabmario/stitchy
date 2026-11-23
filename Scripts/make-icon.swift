// Renders Stitchy's app icon into Stitchy/Resources/AppIcon.icns.
// Run: swift Scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS icon grid: 824pt squircle centred in 1024.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSGradient(colors: [NSColor(white: 0.30, alpha: 1), NSColor(white: 0.10, alpha: 1)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // The island: black capsule near the top, expanded below it.
    let island = NSBezierPath(roundedRect: NSRect(x: 252, y: 430, width: 520, height: 330), xRadius: 120, yRadius: 120)
    NSColor.black.setFill()
    island.fill()
    // Content hints: a ring and two bars.
    NSColor.systemOrange.setStroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 320, y: 520, width: 150, height: 150))
    ring.lineWidth = 26
    ring.stroke()
    NSColor.white.withAlphaComponent(0.9).setFill()
    NSBezierPath(roundedRect: NSRect(x: 510, y: 615, width: 190, height: 34), xRadius: 17, yRadius: 17).fill()
    NSColor.white.withAlphaComponent(0.45).setFill()
    NSBezierPath(roundedRect: NSRect(x: 510, y: 545, width: 130, height: 28), xRadius: 14, yRadius: 14).fill()
    // Stitch line under the island.
    NSColor.white.withAlphaComponent(0.25).setStroke()
    let stitch = NSBezierPath()
    stitch.move(to: NSPoint(x: 300, y: 330))
    stitch.line(to: NSPoint(x: 724, y: 330))
    stitch.lineWidth = 16
    stitch.lineCapStyle = .round
    stitch.setLineDash([36, 30], count: 2, phase: 0)
    stitch.stroke()
    return true
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = root.appendingPathComponent("Stitchy/Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")
