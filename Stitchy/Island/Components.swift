import AppKit
import QuartzCore
import SwiftUI

struct ProgressRing: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var placeholderIcon: NSImage? = nil

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let placeholderIcon {
                Image(nsImage: placeholderIcon).resizable().aspectRatio(contentMode: .fit).padding(size * 0.04)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.24), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Small round icon button used throughout the island.
struct IconButton: View {
    var symbol: String
    var size: CGFloat = 14
    var diameter: CGFloat = 26
    var filled = false
    var tint: Color = .white
    var help: String
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(filled ? .black : tint.opacity(isEnabled ? 1 : 0.3))
                .frame(width: diameter, height: diameter)
                .background(
                    Circle().fill(filled ? tint : .white.opacity(hovering && isEnabled ? 0.16 : 0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Capsule text button ("Start", "Clear").
struct PillButton: View {
    var title: String
    var symbol: String? = nil
    var tint: Color = .white
    var prominent = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .foregroundStyle(prominent ? .black : tint)
            .background(Capsule().fill(prominent ? tint : .white.opacity(hovering ? 0.16 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

/// Rounded "widget" tile used on the dashboard.
struct Tile<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Music visualizer bars.
///
/// Measured on macOS 26: Core Animation animations in a hosted NSView kept
/// the whole island re-laying out every frame (2–20 % CPU). This version is
/// a SwiftUI TimelineView that steps ~6 times a second and only invalidates
/// itself, so a playing track costs well under 1 % CPU.
struct EqualizerView: View {
    var color: NSColor
    var animating: Bool
    private static let rest: [Double] = [0.45, 0.8, 0.35, 0.6]

    var body: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: animating ? 1.0 / 6 : 3600)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * 6
            HStack(alignment: .center, spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    let level = animating ? Self.level(i, t) : Self.rest[i]
                    if i > 0 { Spacer(minLength: 0) }
                    Capsule().fill(Color(nsColor: color)).frame(width: 2.6).frame(maxHeight: .infinity).scaleEffect(y: level)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Smooth-looking pseudo-random levels from overlapping sines.
    private static func level(_ i: Int, _ t: Double) -> Double {
        let d = Double(i)
        let v = 0.55 + 0.3 * sin(t * (0.9 + d * 0.37)) + 0.15 * sin(t * (2.1 + d * 0.53))
        return min(max(v, 0.2), 1)
    }
}

extension Date {
    /// Fixed start for periodic TimelineViews. Using `.now` re-anchors the
    /// schedule on every render, which makes it tick every frame.
    static let timelineAnchor = Date(timeIntervalSinceReferenceDate: 0)
}

extension Color {
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.35)
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

/// ScrollView that degrades to a plain container when rendering snapshots,
/// because ImageRenderer cannot draw AppKit-backed scroll views.
struct IslandScroll<Content: View>: View {
    var axis: Axis.Set
    @ViewBuilder var content: Content

    var body: some View {
        if SnapshotRenderer.isRendering {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        } else {
            ScrollView(axis, showsIndicators: false) { content }
        }
    }
}
