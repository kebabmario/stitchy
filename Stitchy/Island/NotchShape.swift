// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The attached-notch silhouette: a flat top edge flush with the display,
/// small concave shoulders where it meets the edge, and rounded bottom
/// corners. Both radii animate, so compact and expanded are one morphing shape.
struct NotchShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat
    /// Convex top corners (Dynamic Island style). Used when shoulder is 0.
    var topRadius: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(shoulder, bottomRadius), topRadius) }
        set { shoulder = newValue.first.first; bottomRadius = newValue.first.second; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        if topRadius > 0.5, shoulder < 0.5 {
            // Floating island: a continuous rounded rectangle / capsule.
            let r = RectangleCornerRadii(topLeading: min(topRadius, rect.height / 2), bottomLeading: min(bottomRadius, rect.height / 2),
                                         bottomTrailing: min(bottomRadius, rect.height / 2), topTrailing: min(topRadius, rect.height / 2))
            return UnevenRoundedRectangle(cornerRadii: r, style: .continuous).path(in: rect)
        }
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
