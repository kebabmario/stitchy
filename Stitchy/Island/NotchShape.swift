import SwiftUI

/// The attached-notch silhouette: a flat top edge flush with the display,
/// small concave shoulders where it meets the edge, and rounded bottom
/// corners. Both radii animate, so compact and expanded are one morphing shape.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set { shoulder = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 4, rect.height / 2)
        let b = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height - s)
        // 0.55 ≈ circular; a little more gives a softer, "continuous" corner.
        let k: CGFloat = 0.62
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left shoulder (concave), from the top edge down into the body.
        p.addCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s),
                   control1: CGPoint(x: rect.minX + s * k, y: rect.minY),
                   control2: CGPoint(x: rect.minX + s, y: rect.minY + s * (1 - k)))
        p.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - b))
        // Bottom-left corner.
        p.addCurve(to: CGPoint(x: rect.minX + s + b, y: rect.maxY),
                   control1: CGPoint(x: rect.minX + s, y: rect.maxY - b * (1 - k)),
                   control2: CGPoint(x: rect.minX + s + b * (1 - k), y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - s - b, y: rect.maxY))
        // Bottom-right corner.
        p.addCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - b),
                   control1: CGPoint(x: rect.maxX - s - b * (1 - k), y: rect.maxY),
                   control2: CGPoint(x: rect.maxX - s, y: rect.maxY - b * (1 - k)))
        p.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        // Right shoulder.
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                   control1: CGPoint(x: rect.maxX - s, y: rect.minY + s * (1 - k)),
                   control2: CGPoint(x: rect.maxX - s * k, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
