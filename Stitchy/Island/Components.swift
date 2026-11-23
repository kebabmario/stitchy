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

/// Music visualizer bars, animated by Core Animation on the render server
/// so a playing track costs ~0% CPU in Stitchy itself.
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var animating: Bool

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.update(color: color, animating: animating)
    }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var isAnimating = false
    private let durations: [CFTimeInterval] = [0.46, 0.58, 0.38, 0.52]
    private let restScale: [CGFloat] = [0.45, 0.8, 0.35, 0.6]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (i, bar) in bars.enumerated() {
            bar.transform = CATransform3DMakeScale(1, restScale[i], 1)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width: CGFloat = 2.6
        let gap = (bounds.width - width * CGFloat(bars.count)) / CGFloat(bars.count - 1)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (width + gap) + width / 2, y: bounds.midY)
            bar.cornerRadius = width / 2
        }
        CATransaction.commit()
    }

    func update(color: NSColor, animating: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()
        guard animating != isAnimating else { return }
        isAnimating = animating
        for (i, bar) in bars.enumerated() {
            bar.removeAllAnimations()
            guard animating else { continue }
            let anim = CABasicAnimation(keyPath: "transform.scale.y")
            anim.fromValue = 0.25
            anim.toValue = 1.0
            anim.duration = durations[i]
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            anim.beginTime = CACurrentMediaTime() + Double(i) * 0.09
            bar.add(anim, forKey: "eq")
        }
    }
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
