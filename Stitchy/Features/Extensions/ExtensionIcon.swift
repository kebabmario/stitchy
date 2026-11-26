// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// An extension's icon: the user's own image, Stitchy's rocket, or an SF Symbol.
struct ExtIcon: View {
    let ext: StitchyExtension
    var size: CGFloat = 14

    var body: some View {
        if let image = ExtIconImage.image(ext.iconImage) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: size * 1.25, height: size * 1.25)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        } else {
            ExtSymbol(name: ext.icon, size: size)
        }
    }
}

/// Renders a built-in symbol name, including Stitchy's own drawn icons.
struct ExtSymbol: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        if name == ExtIconImage.rocket {
            RocketShape().fill(.foreground, style: FillStyle(eoFill: true)).frame(width: size * 1.1, height: size * 1.1)
        } else {
            Image(systemName: name).font(.system(size: size, weight: .semibold))
        }
    }
}

/// A simple original rocket, pointing up-right.
struct RocketShape: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * s, y: r.minY + y * s) }
        var body = Path()
        body.move(to: p(0.94, 0.06))
        body.addCurve(to: p(0.58, 0.72), control1: p(0.95, 0.35), control2: p(0.78, 0.58))
        body.addLine(to: p(0.28, 0.42))
        body.addCurve(to: p(0.94, 0.06), control1: p(0.42, 0.22), control2: p(0.65, 0.05))
        body.closeSubpath()
        // fins
        body.move(to: p(0.34, 0.36)); body.addLine(to: p(0.12, 0.38)); body.addLine(to: p(0.02, 0.52)); body.addLine(to: p(0.26, 0.48)); body.closeSubpath()
        body.move(to: p(0.64, 0.66)); body.addLine(to: p(0.62, 0.88)); body.addLine(to: p(0.48, 0.98)); body.addLine(to: p(0.52, 0.74)); body.closeSubpath()
        // flame
        body.move(to: p(0.33, 0.58)); body.addLine(to: p(0.42, 0.67)); body.addLine(to: p(0.06, 0.94)); body.closeSubpath()
        // window (cut out)
        body.addEllipse(in: CGRect(x: r.minX + 0.58 * s, y: r.minY + 0.26 * s, width: 0.16 * s, height: 0.16 * s))
        return body
    }
}

enum ExtIconImage {
    static let rocket = "stitchy.rocket"
    static let maxBytes = 200_000
    static let side: CGFloat = 128

    @MainActor private static var cache: [Data: NSImage] = [:]

    @MainActor static func image(_ data: Data?) -> NSImage? {
        guard let data else { return nil }
        if let hit = cache[data] { return hit }
        let image = NSImage(data: data)
        if cache.count > 64 { cache.removeAll() }
        cache[data] = image
        return image
    }

    /// Any image file → a square 128 pt PNG. Re-encoding drops metadata and anything that isn't pixels.
    static func normalized(_ data: Data) -> Data? {
        guard data.count <= 20_000_000, let src = NSImage(data: data), src.size.width > 0, src.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        // Aspect-fill into the square.
        let scale = max(side / src.size.width, side / src.size.height)
        let w = src.size.width * scale, h = src.size.height * scale
        src.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]), png.count <= maxBytes else { return nil }
        return png
    }

    /// For island alerts, which take an NSImage.
    @MainActor static func alertArtwork(_ ext: StitchyExtension) -> NSImage? {
        if let i = image(ext.iconImage) { return i }
        guard ext.icon == rocket else { return nil }
        let r = ImageRenderer(content: RocketShape().fill(Color.white, style: FillStyle(eoFill: true)).frame(width: 40, height: 40).padding(8).background(Color.purple, in: RoundedRectangle(cornerRadius: 12)))
        r.scale = 2
        return r.nsImage
    }
}
