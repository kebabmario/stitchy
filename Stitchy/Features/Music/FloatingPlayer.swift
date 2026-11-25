import AppKit
import SwiftUI

/// Droppy-style Floating Player: a small always-on-top music window you can
/// drag anywhere. Two sizes: Mini (strip) and Player (big artwork + scrubber).
@MainActor
final class FloatingPlayerController {
    private var panel: NSPanel?
    private let services: AppServices

    init(services: AppServices) { self.services = services }

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 96),
                            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: FloatingPlayerView { [weak self] in self?.close() }
                .stitchyEnvironment(services))
            host.sizingOptions = [.preferredContentSize]   // window follows the SwiftUI size
            p.contentView = host
            if !p.setFrameUsingName("StitchyFloatingPlayer"), let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.minY + 24))
            }
            p.setFrameAutosaveName("StitchyFloatingPlayer")
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func close() { panel?.orderOut(nil) }
}

struct FloatingPlayerView: View {
    var onClose: () -> Void
    @Environment(NowPlayingService.self) private var music
    @AppStorage("floatingPlayerLarge") private var large = false
    @State private var hovering = false

    var body: some View {
        Group {
            if large { player } else { mini }
        }
        .padding(12)
        .foregroundStyle(.white)
        .background(background)
        .overlay(alignment: .topTrailing) {
            if hovering {
                HStack(spacing: 4) {
                    IconButton(symbol: large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                               size: 8, diameter: 18, help: large ? "Mini size" : "Player size") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { large.toggle() }
                    }
                    IconButton(symbol: "xmark", size: 8, diameter: 18, help: "Close Floating Player", action: onClose)
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { h in withAnimation(Interaction.spring) { hovering = h } }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: large ? 30 : 24, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(.black.opacity(0.55)), in: shape)
        } else {
            shape.fill(.black.opacity(0.88)).overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        }
    }

    private var mini: some View {
        HStack(spacing: 12) {
            ArtworkView(image: music.artwork, size: 64, radius: 14, placeholderIcon: music.player?.icon)
            VStack(alignment: .leading, spacing: 2) {
                titles
                controls(big: 15).padding(.top, 4)
            }
        }
        .frame(width: 296, alignment: .leading)
    }

    private var player: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtworkView(image: music.artwork, size: 236, radius: 22, placeholderIcon: music.player?.icon)
                .shadow(color: music.accent.opacity(0.45), radius: 18, y: 6)
            titles
            progress
            controls(big: 20).frame(maxWidth: .infinity)
        }
        .frame(width: 236)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(music.track?.title ?? "Nothing Playing").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
            Text(music.track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "Play something in Music or Spotify")
                .font(.system(size: 11.5)).foregroundStyle(Color.secondaryText).lineLimit(1)
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: 1)) { context in
            let elapsed = music.elapsed(at: context.date) ?? 0
            let duration = music.track?.duration ?? 0
            VStack(spacing: 3) {
                ProgressView(value: duration > 0 ? min(elapsed / duration, 1) : 0).tint(.white)
                HStack {
                    Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text(Duration.seconds(max(duration - elapsed, 0)).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.system(size: 9.5, weight: .medium).monospacedDigit()).foregroundStyle(Color.tertiaryText)
            }
        }
    }

    private func controls(big: CGFloat) -> some View {
        HStack(spacing: 14) {
            button("backward.fill", size: big * 0.75, help: "Previous") { music.previous() }
            button(music.isPlaying ? "pause.fill" : "play.fill", size: big, help: "Play/Pause") { music.playPause() }
            button("forward.fill", size: big * 0.75, help: "Next") { music.next() }
        }
        .disabled(music.track == nil || !music.controlsEnabled)
    }

    private func button(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.8, height: size * 1.5)
        }
        .buttonStyle(PressableStyle()).help(help).accessibilityLabel(help)
    }
}
