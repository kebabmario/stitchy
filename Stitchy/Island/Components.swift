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
                .modifier(CircleBackground(filled: filled, tint: tint, hovering: hovering && isEnabled))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct CircleBackground: ViewModifier {
    var filled: Bool
    var tint: Color
    var hovering: Bool

    func body(content: Content) -> some View {
        if filled {
            content.background(Circle().fill(tint))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(.white.opacity(hovering ? 0.16 : 0.08)))
        }
    }
}

/// Shared interaction style for every Stitchy control: a subtle lift on
/// hover, a press-down on click, one spring for all of it. With Reduce
/// Motion, only opacity changes.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractiveBody(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct InteractiveBody<Label: View>: View {
        let label: Label
        let isPressed: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.92 : hovering && isEnabled ? 1.05 : 1))
                .brightness(hovering && isEnabled && !isPressed ? 0.06 : 0)
                .opacity(isPressed ? 0.8 : 1)
                .animation(Interaction.spring, value: isPressed)
                .animation(Interaction.spring, value: hovering)
                // Hit area = the unscaled bounds. Without this the press scale
                // shrinks the target, so a click near the edge ends "outside"
                // and the button cancels its action.
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// `.plain` with a forgiving hit area: the whole frame plus 4pt of slop
/// counts, not just the glyph pixels, so clicks on a button's edge land.
struct PlainHitStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(4).contentShape(Rectangle()).padding(-4)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension ButtonStyle where Self == PlainHitStyle {
    static var plainHit: PlainHitStyle { PlainHitStyle() }
}

enum Interaction {
    /// One timing for hover/press feedback across the app.
    static let spring = Animation.spring(response: 0.24, dampingFraction: 0.72)
}

/// Hover highlight for rows and cards that aren't buttons.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 10
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.white.opacity(hovering ? 0.06 : 0)))
            .animation(Interaction.spring, value: hovering)
            .onHover { hovering = $0 }
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
            .modifier(PillBackground(prominent: prominent, tint: tint, hovering: hovering))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }
}

/// Secondary pills use Liquid Glass on macOS 26; prominent ones stay solid.
struct PillBackground: ViewModifier {
    var prominent: Bool
    var tint: Color
    var hovering: Bool

    func body(content: Content) -> some View {
        if prominent {
            content.background(Capsule().fill(tint))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0.09)))
        }
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
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }
}

/// Music visualizer bars, animated by Core Animation.
///
/// The animation runs in the render server: smooth at display refresh with
/// almost no app CPU. (Re-measured after fixing the TimelineView anchor
/// bug: a SwiftUI Canvas at 30 fps cost ~6.5 % because every frame
/// re-rendered the whole island.)
struct EqualizerView: NSViewRepresentable {
    var color: NSColor
    var animating: Bool

    func makeNSView(context: Context) -> EqualizerNSView { EqualizerNSView() }
    func updateNSView(_ view: EqualizerNSView, context: Context) { view.update(color: color, animating: animating) }
}

final class EqualizerNSView: NSView {
    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var isAnimating = false
    private let durations: [CFTimeInterval] = [0.43, 0.57, 0.37, 0.51]
    private let rest: [CGFloat] = [0.45, 0.8, 0.35, 0.6]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for (i, bar) in bars.enumerated() {
            bar.transform = CATransform3DMakeScale(1, rest[i], 1)
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w: CGFloat = 2.6
        let gap = (bounds.width - w * 4) / 3
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            bar.cornerRadius = w / 2
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
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            a.values = [0.3, 1.0, 0.55, 0.9, 0.3].map { NSNumber(value: Double($0) * (0.85 + 0.15 * Double(i % 2))) }
            a.duration = durations[i] * 4
            a.repeatCount = .infinity
            a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
            a.beginTime = CACurrentMediaTime() + Double(i) * 0.11
            bar.add(a, forKey: "eq")
        }
    }
}

/// Liquid Glass on macOS 26, a subtle fill before that.
struct GlassCapsule: ViewModifier {
    var tint: Color? = nil
    var prominent = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(prominent ? .regular.tint(tint).interactive() : .regular.interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(prominent ? (tint ?? .white) : .white.opacity(0.1)))
        }
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

// MARK: - Design tokens

/// Stitchy's design language: flat black island, rounded numerals, one quiet
/// surface ("well") per group, small tracked section labels, colour only on
/// icons and progress. Pages use these instead of ad-hoc values.
enum DS {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }
    static let wellRadius: CGFloat = 18

    /// Big numerals: clocks, timers, temperatures.
    static func numerals(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static let title = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 10.5, weight: .medium)
    static let label = Font.system(size: 9, weight: .bold)
}

/// One grouped surface: a slightly lifted panel with a hairline edge.
struct Well: ViewModifier {
    var padding: CGFloat = DS.Space.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous).fill(.white.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }
}

extension View {
    func well(padding: CGFloat = DS.Space.m) -> some View { modifier(Well(padding: padding)) }
}

/// Small uppercase label above a group ("NOW", "RUNNING").
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(DS.label)
            .tracking(0.8)
            .foregroundStyle(Color.tertiaryText)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Centered empty / setup state: tinted glyph in a soft circle, title, one
/// line of explanation and an optional primary action.
struct EmptyState: View {
    var symbol: String
    var tint: Color = .white
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(Circle().fill(tint.opacity(0.14)))
            Text(title).font(DS.title)
            Text(message)
                .font(DS.caption).foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 28)
                        .foregroundStyle(.black)
                        .background(Capsule().fill(.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small visible capsule action (no glass), used in page footers and grids.
struct Chip: View {
    var title: String
    var symbol: String? = nil
    var active = false
    var tint: Color = .white
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
                if !title.isEmpty { Text(title).font(.system(size: 11, weight: .semibold)) }
            }
            .padding(.horizontal, title.isEmpty ? 7 : 10).frame(minWidth: 24).frame(height: 24)
            .foregroundStyle(active ? .black : tint)
            .background(Capsule().fill(active ? tint : .white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title.isEmpty ? (symbol ?? "") : title)
    }
}

/// Apple Music-style motion for a lyric line, by its distance from the current
/// line: the current one is full size, bright and softly glowing; lines further
/// away shrink a little, dim and soften. Animate `current` with a spring.
struct LyricLineStyle: ViewModifier {
    let index: Int
    let current: Int?
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        let distance = current.map { abs(index - $0) } ?? 3
        let isCurrent = distance == 0
        content
            .foregroundStyle(.white.opacity(isCurrent ? 1 : max(0.22, 0.5 - Double(distance) * 0.07)))
            .scaleEffect(isCurrent || settings.reduceMotion ? 1 : max(0.9, 0.97 - CGFloat(distance) * 0.015), anchor: .leading)
            .blur(radius: isCurrent || settings.reduceMotion ? 0 : min(CGFloat(distance) * 0.5, 2))
            .shadow(color: .white.opacity(isCurrent ? 0.35 : 0), radius: isCurrent ? 10 : 0)
    }
}
