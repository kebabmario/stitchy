// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import SwiftUI

/// What the lock screen music shows; shared by the art and player windows.
@MainActor @Observable
final class LockScreenState {
    var showLyrics = false
    /// Hidden with the player's hide button: the plain macOS lock screen until the next lock.
    var hidden = false
}

/// Full-screen lock screen music, in the style of Apple's full-screen album
/// art lock screen: the whole cover (its top and bottom fading into a blurred
/// copy), a single-line clock behind the cover's subject, a centred player
/// and full-screen lyrics on request.
///
/// Two windows, both in the lock-screen space (private SkyLight API, see
/// LockScreenPresenter):
///  - The art window ignores every click and never becomes key.
///  - The player window takes clicks only on its controls and never becomes
///    key, so typing always goes to the macOS password field.
/// The player ends above the area where macOS shows your name, password field
/// and Touch ID prompt.
@MainActor
final class LockScreenArtController {
    private var art: NSPanel?
    private var player: NSPanel?
    private let services: AppServices
    private let state = LockScreenState()
    private var wakeObserver: NSObjectProtocol?

    init(services: AppServices) {
        self.services = services
        observeContinuously { [weak self] in self?.applyState() }
    }

    /// Follows the state: hide everything, or slide the player aside for the lyrics panel.
    private func applyState() {
        let lyrics = state.showLyrics, hidden = state.hidden   // read both so changes to either re-run this
        guard let art, let player, let screen = NSScreen.main, services.island.isScreenLocked else { return }
        if hidden {
            art.orderOut(nil)
            player.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            player.animator().setFrame(Self.playerFrame(in: screen.frame, lyrics: lyrics), display: true)
        }
    }

    func update(locked: Bool) {
        guard locked, services.settings.lockScreenIsland, services.settings.lockScreenArt,
              let screen = NSScreen.main ?? NSScreen.screens.first else {
            hideAll()
            islandLog.notice("lockscreen art hidden (unlocked or off)")
            return
        }
        state.hidden = false
        state.showLyrics = false
        let artWindow = art ?? makePanel(LockScreenArtView(), clickThrough: true, level: .normal)
        art = artWindow
        artWindow.setFrame(screen.frame, display: true)
        let playerWindow = player ?? makePanel(LockScreenPlayerView(), clickThrough: false, level: .floating)
        player = playerWindow
        playerWindow.setFrame(Self.playerFrame(in: screen.frame), display: true)
        reassert()
        islandLog.notice("lockscreen art shown")
        // When a key press brings up the macOS login prompt, macOS hides this layer so the
        // password field is never covered; we don't fight that. It returns when the screen
        // next wakes while still locked.
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                                             object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.services.island.isScreenLocked == true, self?.state.hidden == false { self?.reassert() }
                }
            }
        }
    }

    /// Dev aid (`--preview-lockscreen [lyrics]`): shows the real windows on the
    /// normal desktop for a while, outside the lock-screen space, so the
    /// layout can be screenshotted. Never used in a normal launch.
    func previewOnDesktop(lyrics: Bool, seconds: Double = 25) {
        guard let screen = NSScreen.main else { return }
        let artWindow = art ?? makePanel(LockScreenArtView(), clickThrough: true, level: .normal)
        art = artWindow
        artWindow.setFrame(screen.frame, display: true)
        let playerWindow = player ?? makePanel(LockScreenPlayerView(), clickThrough: false, level: .floating)
        player = playerWindow
        playerWindow.setFrame(Self.playerFrame(in: screen.frame, lyrics: lyrics), display: true)
        artWindow.level = .screenSaver
        playerWindow.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        state.showLyrics = lyrics
        islandLog.notice("lockscreen preview lyrics=\(lyrics, privacy: .public) track=\(self.services.nowPlaying.track != nil, privacy: .public)")
        artWindow.orderFrontRegardless()
        playerWindow.orderFrontRegardless()
        Task { [weak self] in
            // Also write what the windows draw to PNGs (art + player composited), for review.
            try? await Task.sleep(for: .seconds(3))
            if let dir = ProcessInfo.processInfo.environment["STITCHY_PREVIEW_OUT"], let self { self.snapshot(to: URL(fileURLWithPath: dir), lyrics: lyrics) }
            try? await Task.sleep(for: .seconds(max(seconds - 3, 1)))
            self?.art?.orderOut(nil)
            self?.player?.orderOut(nil)
        }
    }

    /// Renders the art and player (with blur and masks) using the real track, for review.
    private func snapshot(to dir: URL, lyrics: Bool) {
        guard let screen = NSScreen.main else { return }
        let size = screen.frame.size
        let f = Self.playerFrame(in: CGRect(origin: .zero, size: size), lyrics: lyrics)
        let view = ZStack(alignment: .topLeading) {
            Color(white: 0.2)
            LockScreenArtView()
            LockScreenPlayerView().frame(width: f.width, height: f.height)
                .offset(x: f.minX, y: size.height - f.maxY)
        }
        .frame(width: size.width, height: size.height)
        .environment(state)
        .stitchyEnvironment(services)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent(lyrics ? "real-lock-lyrics.png" : "real-lock.png"))
        }
    }

    private func hideAll() {
        art?.orderOut(nil)
        player?.orderOut(nil)
        state.showLyrics = false
    }

    private func reassert() {
        // Never on an unlocked Mac: these windows belong to the lock screen only.
        guard services.island.isScreenLocked else { hideAll(); return }
        LockScreenPresenter.shared?.reshowSpace()
        for w in [art, player].compactMap({ $0 }) {
            w.orderFrontRegardless()
            LockScreenPresenter.shared?.attach(w)
        }
    }

    /// Centred near the bottom, like Apple's full-screen art lock screen. A key press brings
    /// up the macOS login prompt, which hides this layer, so it never covers the password field.
    /// With lyrics open, the player moves to the left half (the lyrics panel takes the right).
    nonisolated static func playerFrame(in screen: CGRect, lyrics: Bool = false) -> CGRect {
        let size = CGSize(width: lyrics ? min(560, screen.width * 0.42) : min(660, screen.width * 0.46), height: 290)
        let bottomFromTop = screen.height * (lyrics ? 0.92 : 0.95)
        let centerX = lyrics ? screen.minX + screen.width * LockScreenLayout.leftCenter : screen.midX
        return CGRect(x: centerX - size.width / 2, y: screen.maxY - bottomFromTop, width: size.width, height: size.height)
    }

    private func makePanel(_ view: some View, clickThrough: Bool, level: NSWindow.Level) -> NSPanel {
        let p = NeverKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = level
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = clickThrough
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: view.environment(state).stitchyEnvironment(services))
        return p
    }
}

/// How a cover sits on the screen: fill it edge to edge, unless that would crop away
/// more than `maxCrop` of the cover (very wide or tall art), then show it whole.
enum ArtPlacement {
    struct Placement: Equatable { let size: CGSize; let fills: Bool }

    nonisolated static func place(_ image: CGSize, in screen: CGSize, maxCrop: CGFloat = 0.42) -> Placement {
        guard image.width > 0, image.height > 0 else { return Placement(size: screen, fills: true) }
        let fill = max(screen.width / image.width, screen.height / image.height)
        let drawn = CGSize(width: image.width * fill, height: image.height * fill)
        let cropped = 1 - (screen.width * screen.height) / (drawn.width * drawn.height)
        if cropped <= maxCrop { return Placement(size: drawn, fills: true) }
        let fit = min(screen.width / image.width, screen.height / image.height)
        return Placement(size: CGSize(width: image.width * fit, height: image.height * fit), fills: false)
    }

    /// Soft edges on all four sides for a cover shown whole.
    static var featherMask: some View {
        Rectangle().fill(.black)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                         .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
    }
}

/// Shared geometry for the lyrics layout (fractions of the screen).
enum LockScreenLayout {
    /// Lyrics panel: the right side.
    static func lyricsPanel(in size: CGSize) -> CGRect {
        CGRect(x: size.width * 0.53, y: size.height * 0.07, width: size.width * 0.43, height: size.height * 0.86)
    }
    /// Horizontal centre of the left half, where clock and player go while lyrics are open.
    static let leftCenter: CGFloat = 0.27
}

/// Never key or main: keystrokes always go to the macOS login window.
private final class NeverKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The cover filling the whole screen, its far left and right edges softened,
/// darker towards the bottom for the player, and a single-line clock behind
/// the cover's subject. With lyrics on, the art dims and the lyrics take over.
struct LockScreenArtView: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(LockScreenState.self) private var state
    @State private var cutout: NSImage?

    var body: some View {
        GeometryReader { geo in
            if music.track != nil {
                ZStack(alignment: .topLeading) {
                    fill(music.artwork, size: geo.size)
                    // Soft edges: a blurred copy shows only at the far left and right.
                    fill(music.artwork, size: geo.size)
                        .blur(radius: 55)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.06),
                                                     .init(color: .clear, location: 0.3), .init(color: .clear, location: 0.7),
                                                     .init(color: .black, location: 0.94), .init(color: .black, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                    LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0), .init(color: .clear, location: 0.18),
                                           .init(color: .clear, location: 0.5), .init(color: .black.opacity(0.55), location: 0.75),
                                           .init(color: .black.opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom)
                    clock(geo.size)
                        .frame(width: geo.size.width * (state.showLyrics ? LockScreenLayout.leftCenter * 2 : 1))
                    if let cutout { fill(cutout, size: geo.size, sharpOnly: true).transition(.opacity) }
                    if state.showLyrics {
                        lyricsPanel(geo.size)
                            .transition(.opacity.combined(with: .offset(x: 40)))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: music.track?.id)
        .animation(.spring(response: 0.55, dampingFraction: 0.88), value: state.showLyrics)
        .allowsHitTesting(false)
        .environment(\.colorScheme, .dark)
        .task(id: music.artwork.map { ObjectIdentifier($0) }) {
            cutout = nil
            guard !SnapshotRenderer.isRendering, let cg = music.artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let result = await Task.detached(priority: .utility) { (try? CaptureService.subjectCutout(cg)).map(UncheckedBox.init) }.value
            withAnimation(.easeOut(duration: 0.5)) { cutout = result.map { NSImage(cgImage: $0.value, size: .zero) } }
        }
    }

    /// Apple Music-style lyrics on the right, on a frosted panel: a blurred copy of the cover
    /// (drawn here, so the blur works inside the lock-screen window) with a light tint.
    private func lyricsPanel(_ size: CGSize) -> some View {
        let r = LockScreenLayout.lyricsPanel(in: size)
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return ZStack(alignment: .topLeading) {
            fill(music.artwork, size: size)
                .blur(radius: 50)
                .overlay(Color.black.opacity(0.32))
                .mask { shape.frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY) }
            shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            LockScreenLyrics(size: r.size)
                .frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The art placed for this screen (see `ArtPlacement`). A cover that fills is drawn edge to edge;
    /// one that would lose too much to cropping is shown whole, its edges fading into a blurred copy.
    /// The cutout uses the same placement (`sharpOnly`), so the clock depth still lines up.
    @ViewBuilder private func fill(_ image: NSImage?, size: CGSize, sharpOnly: Bool = false) -> some View {
        if let image {
            let source = music.artwork?.size ?? image.size
            let placement = ArtPlacement.place(source, in: size)
            ZStack {
                if !placement.fills, !sharpOnly {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height).clipped()
                        .blur(radius: 60).overlay(Color.black.opacity(0.2))
                }
                Image(nsImage: image).resizable().interpolation(.high).antialiased(true)
                    .frame(width: placement.size.width, height: placement.size.height)
                    .mask { placement.fills ? AnyView(Color.black) : AnyView(ArtPlacement.featherMask) }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        } else {
            LinearGradient(colors: [music.accent.opacity(0.7), .black], startPoint: .top, endPoint: .bottom)
        }
    }

    /// One line, like "15:04  Sat 22 Nov", near the top.
    private func clock(_ size: CGSize) -> some View {
        TimelineView(.everyMinute) { context in
            HStack(alignment: .firstTextBaseline, spacing: size.height * 0.02) {
                Text(DepthArtwork.clock(context.date))
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            .font(.system(size: size.height * 0.058, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.25), radius: 14)
            .padding(.top, size.height * 0.075)
        }
    }
}

/// Apple Music-style lyrics: big bold lines, the current one bright, the rest
/// dimmed and softly blurred, scrolling with the song.
struct LockScreenLyrics: View {
    /// The panel's size.
    let size: CGSize
    @Environment(NowPlayingService.self) private var music
    @Environment(LyricsService.self) private var lyrics

    /// Apple Music's lyrics type: SF Pro Bold, large, slightly tight.
    private var lineFont: Font { .system(size: min(size.height * 0.05, 34), weight: .bold) }

    var body: some View {
        Group {
            switch lyrics.state {
            case .synced(let lines):
                TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.2 : 3600)) { context in
                    let current = music.elapsed(at: context.date).flatMap { LyricsService.index(in: lines, at: $0 + 0.2) }
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: size.height * 0.03) {
                                Color.clear.frame(height: size.height * 0.18)
                                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                    Text(line.text.isEmpty ? "♪" : line.text)
                                        .font(lineFont)
                                        .tracking(-0.4)
                                        .modifier(LyricLineStyle(index: i, current: current))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(i)
                                }
                                Color.clear.frame(height: size.height * 0.5)
                            }
                            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: current)
                        }
                        .onChange(of: current) { _, i in
                            guard let i else { return }
                            withAnimation(.spring(response: 0.75, dampingFraction: 0.86)) { proxy.scrollTo(i, anchor: UnitPoint(x: 0, y: 0.3)) }
                        }
                        .onAppear { proxy.scrollTo(current ?? 0, anchor: UnitPoint(x: 0, y: 0.3)) }
                    }
                }
            case .plain(let text):
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text).font(.system(size: min(size.height * 0.035, 24), weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                }
            case .loading:
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                Text("No lyrics for this song").font(lineFont).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 34)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The centred player: title and artist, scrubber, transport, lyrics and
/// volume. Its buttons work; it never takes the keyboard.
struct LockScreenPlayerView: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(LyricsService.self) private var lyrics
    @Environment(QueueService.self) private var queue
    @Environment(LockScreenState.self) private var state

    var body: some View {
        if music.track != nil {
            VStack(spacing: 14) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(music.track?.title ?? "").font(.system(size: 23, weight: .semibold)).lineLimit(1)
                        Text(music.track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "")
                            .font(.system(size: 19, weight: .regular)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if !state.showLyrics { lyricOrNext }
                    small("quote.bubble", active: state.showLyrics, size: 17) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) { state.showLyrics.toggle() }
                    }
                    .help(state.showLyrics ? "Hide lyrics" : "Show lyrics")
                    small("eye.slash", active: false, size: 16) {
                        withAnimation(.easeOut(duration: 0.3)) { state.hidden = true }
                    }
                    .help("Hide the music screen until the next lock")
                }
                scrubber
                HStack {
                    small("shuffle", active: music.shuffle == true) { music.toggleShuffle() }
                        .disabled(music.shuffle == nil)
                    Spacer()
                    big("backward.fill", 28) { music.previous() }
                    Spacer()
                    big(music.isPlaying ? "pause.fill" : "play.fill", 42) { music.playPause() }
                    Spacer()
                    big("forward.fill", 28) { music.next() }
                    Spacer()
                    small(music.repeatMode == .one ? "repeat.1" : "repeat", active: (music.repeatMode ?? .off) != .off) { music.cycleRepeat() }
                        .disabled(music.repeatMode == nil)
                }
                .disabled(!music.controlsEnabled)
                if let volume = music.volume {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").font(.system(size: 11))
                        ThinBar(value: volume) { music.setVolume($0) }
                        Image(systemName: "speaker.wave.3.fill").font(.system(size: 11))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 8)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .environment(\.colorScheme, .dark)
            // Typing on the lock screen belongs to the password field: no control here takes focus.
            .focusEffectDisabled()
            .task(id: music.track?.id) {
                guard !SnapshotRenderer.isRendering, let t = music.track else { return }
                await lyrics.load(title: t.title, artist: t.artist, album: t.album, duration: t.duration, embedded: music.embeddedLyrics)
                await queue.refresh(player: music.player, shuffle: music.shuffle)
                await music.refreshExtras()
            }
        }
    }

    /// The live lyric line when there is one, otherwise what's up next.
    private var lyricOrNext: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.25 : 3600)) { context in
            let (current, _) = LockScreenNowPlaying.lines(lyrics.state, at: music.elapsed(at: context.date))
            Group {
                if let current {
                    Text(current).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .id(current).transition(.push(from: .bottom).combined(with: .opacity))
                } else if let next = queue.items.first {
                    Text("Next: \(next.title)").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .lineLimit(1)
            .frame(maxWidth: 260, alignment: .trailing)
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: current)
        }
    }

    private var scrubber: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 1 : 3600)) { context in
            let elapsed = music.elapsed(at: context.date) ?? 0, duration = music.track?.duration ?? 0
            VStack(spacing: 5) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.25))
                        Capsule().fill(.white).frame(width: g.size.width * (duration > 0 ? min(elapsed / duration, 1) : 0))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(elapsed.clockStringFloor)
                    Spacer()
                    Text(duration > 0 ? "-" + max(duration - elapsed, 0).clockString : "")
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func big(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size * 1.8, height: size * 1.4).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .focusable(false)
    }

    private func small(_ symbol: String, active: Bool, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? .white : .white.opacity(0.55))
                .frame(width: 36, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .focusable(false)
    }
}

/// A thin white level bar you can click or drag (no AppKit slider, no focus).
struct ThinBar: View {
    let value: Double
    let onChange: (Double) -> Void
    @State private var dragging: Double?
    @State private var lastSent = Date.distantPast

    var body: some View {
        GeometryReader { g in
            let v = dragging ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white.opacity(0.9)).frame(width: g.size.width * min(max(v, 0), 1))
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    let new = min(max(d.location.x / g.size.width, 0), 1)
                    dragging = new
                    // Each change is an Apple Event to the player: at most ~5 a second while dragging.
                    if Date().timeIntervalSince(lastSent) > 0.2 { lastSent = Date(); onChange(new) }
                }
                .onEnded { _ in
                    if let v = dragging { onChange(v) }
                    dragging = nil
                })
        }
        .frame(height: 18)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
