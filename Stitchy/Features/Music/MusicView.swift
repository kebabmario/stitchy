// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The expanded music player.
struct MusicView: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(IslandModel.self) private var model

    var body: some View {
        if let track = music.track {
            if model.lyricsExpanded {
                LyricsExpandedView(track: track)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            } else if model.queueExpanded {
                QueueView(track: track)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            } else {
                PlayerView(track: track).transition(.opacity)
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.tertiaryText)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Nothing Playing").font(.system(size: 14, weight: .semibold))
            Text("Play something in Music or Spotify. Other players and browsers aren't available through public macOS APIs.")
                .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlayerView: View {
    let track: NowPlayingService.Track
    @Environment(AppServices.self) private var services
    @Environment(NowPlayingService.self) private var music
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Artwork(size: 128)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    if let icon = music.player?.icon { Image(nsImage: icon).resizable().frame(width: 13, height: 13) }
                    Text((music.player?.name ?? "").uppercased()).font(DS.label).tracking(0.8).foregroundStyle(Color.tertiaryText)
                    Spacer()
                    if music.isPlaying { EqualizerView(color: NSColor(music.accent), animating: settings.animatedVisualizer).frame(width: 16, height: 12) }
                    if !SnapshotRenderer.isRendering, !services.island.isScreenLocked {
                        IconButton(symbol: "pip.enter", size: 9, diameter: 20, help: "Floating Player") {
                            services.island.collapse()
                            services.floatingPlayer.toggle()
                        }
                    }
                }
                Text(track.title).font(.system(size: 16, weight: .semibold)).lineLimit(1).padding(.top, 4)
                    .contentTransition(.opacity).id("t-\(track.id)").transition(.opacity)
                Text(track.artist.isEmpty ? track.album : track.artist)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.secondaryText).lineLimit(1)
                Spacer(minLength: 6)
                Scrubber(track: track)
                if music.controlsEnabled, music.permission != .denied {
                    Transport().padding(.top, 6)
                } else {
                    ControlsNote().padding(.top, 6)
                }
            }
            .frame(height: 128)
        }
        .animation(.easeInOut(duration: 0.35), value: track.id)
        .safeAreaInset(edge: .bottom, spacing: 8) { LyricLineButton() }
    }
}

/// Album art with a soft accent glow; crossfades when the track changes.
private struct Artwork: View {
    let size: CGFloat
    @Environment(NowPlayingService.self) private var music

    var body: some View {
        ZStack {
            ArtworkView(image: music.artwork, size: size, radius: size * 0.14, placeholderIcon: nil)
                .id(music.artwork.map { ObjectIdentifier($0) })
                .transition(.opacity.animation(.easeInOut(duration: 0.45)))
        }
        .frame(width: size, height: size)
        .shadow(color: music.accent.opacity(music.artwork == nil ? 0 : 0.45), radius: 16, y: 6)
        .scaleEffect(music.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: music.isPlaying)
        .accessibilityHidden(true)
    }
}

/// Draggable progress bar. Seeking needs Automation access.
private struct Scrubber: View {
    let track: NowPlayingService.Track
    @Environment(NowPlayingService.self) private var music
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        let duration = track.duration ?? 0
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying && dragValue == nil ? 0.5 : 3600)) { context in
            let elapsed = dragValue ?? music.elapsed(at: context.date) ?? 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.18))
                        Capsule().fill(.white.opacity(0.85)).frame(width: geo.size.width * fraction)
                    }
                    .frame(height: hovering || dragValue != nil ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard duration > 0, music.controlsEnabled else { return }
                            dragValue = min(max(g.location.x / geo.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let v = dragValue { music.seek(to: v) }
                            dragValue = nil
                        })
                }
                .frame(height: 10)
                .onHover { hovering = $0 }
                .animation(Interaction.spring, value: hovering)
                HStack {
                    Text(elapsed.clockStringFloor)
                    Spacer()
                    Text(duration > 0 ? "-" + max(duration - elapsed, 0).clockString : "")
                }
                .font(DS.numerals(10, weight: .medium))
                .foregroundStyle(Color.tertiaryText)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
    }
}

private struct Transport: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(IslandModel.self) private var model
    @State private var showVolume = false

    var body: some View {
        HStack(spacing: 0) {
            small(music.shuffle == true ? "shuffle" : "shuffle", active: music.shuffle == true, help: "Shuffle") { music.toggleShuffle() }
                .disabled(music.shuffle == nil)
            Spacer()
            big("backward.fill", size: 16, help: "Previous") { music.previous() }
            Spacer()
            big(music.isPlaying ? "pause.fill" : "play.fill", size: 22, help: music.isPlaying ? "Pause" : "Play") { music.playPause() }
                .contentTransition(.symbolEffect(.replace))
            Spacer()
            big("forward.fill", size: 16, help: "Next") { music.next() }
            Spacer()
            small(music.repeatMode == .one ? "repeat.1" : "repeat", active: (music.repeatMode ?? .off) != .off, help: "Repeat") { music.cycleRepeat() }
                .disabled(music.repeatMode == nil)
            Spacer()
            small("list.bullet", active: model.queueExpanded, help: "Up Next") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { model.lyricsExpanded = false; model.queueExpanded = true }
            }
            Spacer()
            small("speaker.wave.2.fill", active: showVolume, help: "Volume") { withAnimation(Interaction.spring) { showVolume.toggle() } }
                .disabled(music.volume == nil)
                .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { music.volume ?? 0 }, set: { music.setVolume($0) }), in: 0...1).frame(width: 140)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .padding(12)
                }
        }
        .task { await music.refreshExtras() }
    }

    private func big(_ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 34, height: 30).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).help(help).accessibilityLabel(help)
    }

    private func small(_ symbol: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.tertiaryText)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(active ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle()).help(help).accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct ControlsNote: View {
    @Environment(NowPlayingService.self) private var music

    var body: some View {
        HStack(spacing: 8) {
            Text(music.permission == .denied ? "Playback control was denied." : "Controls, artwork and seeking need Automation access.")
                .font(.system(size: 10.5)).foregroundStyle(Color.secondaryText).lineLimit(2)
            Spacer(minLength: 0)
            PillButton(title: music.permission == .denied ? "Open Settings" : "Enable", tint: .white) {
                if music.permission == .denied { SystemSettingsLink.open(SystemSettingsLink.automation) } else { Task { await music.enableControls() } }
            }
        }
    }
}

/// The current lyric line under the player; click to enlarge.
private struct LyricLineButton: View {
    @Environment(LyricsService.self) private var lyrics
    @Environment(NowPlayingService.self) private var music
    @Environment(AppSettings.self) private var settings
    @Environment(IslandModel.self) private var model

    var body: some View {
        if settings.lyricsEnabled {
            Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { model.lyricsExpanded = true } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill").font(.system(size: 10)).foregroundStyle(music.accent.opacity(0.9))
                    TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.25 : 3600)) { context in
                        Text(caption(at: context.date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .id(caption(at: context.date))
                            .transition(.push(from: .bottom).combined(with: .opacity))
                            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: caption(at: context.date))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.tertiaryText)
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.055)))
                .modifier(HoverHighlight(cornerRadius: 13))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plainHit)
            .help("Show lyrics")
            .task(id: music.track?.id) { await loadLyrics() }
            .onChange(of: music.embeddedLyrics) { _, _ in Task { await loadLyrics() } }
        }
    }

    private func caption(at date: Date) -> String {
        switch lyrics.state {
        case .synced: lyrics.line(at: music.elapsed(at: date)) ?? "♪"
        case .plain: "Lyrics (not time-synced)"
        case .loading: "Finding lyrics…"
        case .notFound: "No lyrics for this song"
        case .failed: "Lyrics unavailable offline"
        case .idle: "Lyrics"
        }
    }

    private func loadLyrics() async {
        guard let t = music.track else { return }
        await lyrics.load(title: t.title, artist: t.artist, album: t.album, duration: t.duration, embedded: music.embeddedLyrics)
    }
}

/// Enlarged, auto-scrolling lyrics. Tap a line to jump there.
private struct LyricsExpandedView: View {
    let track: NowPlayingService.Track
    @Environment(LyricsService.self) private var lyrics
    @Environment(NowPlayingService.self) private var music
    @Environment(IslandModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(image: music.artwork, size: 34, radius: 7, placeholderIcon: music.player?.icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(track.artist).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer()
                IconButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 11, diameter: 28, help: "Play/Pause") { music.playPause() }
                    .disabled(!music.controlsEnabled)
                IconButton(symbol: "chevron.down", size: 11, diameter: 28, help: "Hide lyrics") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { model.lyricsExpanded = false }
                }
            }
            content
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                                             .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            progress
        }
        .padding(DS.Space.s)
        .background(backdrop)
    }

    /// The cover's colours behind the lyrics so the page never reads as empty black.
    private var backdrop: some View {
        GeometryReader { geo in
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 40).saturation(1.25)
                        .overlay(LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35), .black.opacity(0.6)],
                                                startPoint: .top, endPoint: .bottom))
                } else {
                    LinearGradient(colors: [music.accent.opacity(0.22), .black], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous))
        }
    }

    /// Slim position bar so the bottom of the page has a purpose.
    private var progress: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 1 : 3600)) { context in
            let elapsed = music.elapsed(at: context.date) ?? 0
            let duration = track.duration ?? 0
            HStack(spacing: DS.Space.s) {
                Text(elapsed.clockStringFloor)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: geo.size.width * (duration > 0 ? min(max(elapsed / duration, 0), 1) : 0))
                    }
                }
                .frame(height: 3)
                Text(duration > 0 ? "-" + max(duration - elapsed, 0).clockString : "")
            }
            .font(DS.numerals(9.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))
        }
        .frame(height: 12)
    }

    @ViewBuilder private var content: some View {
        switch lyrics.state {
        case .synced(let lines):
            TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.2 : 3600)) { context in
                let current = music.elapsed(at: context.date).flatMap { LyricsService.index(in: lines, at: $0 + 0.2) }
                GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            // Half a page above and below, so the current line can sit in the middle.
                            Color.clear.frame(height: geo.size.height * 0.42)
                            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                                Text(line.text.isEmpty ? "♪" : line.text)
                                    .font(.system(size: 19, weight: .bold))
                                    .tracking(-0.3)
                                    .modifier(LyricLineStyle(index: i, current: current))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                                    .contentShape(Rectangle())
                                    .onTapGesture { if music.controlsEnabled { music.seek(to: line.time) } }
                            }
                            Color.clear.frame(height: geo.size.height * 0.5)
                        }
                        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: current)
                    }
                    .onChange(of: current) { _, i in
                        guard let i else { return }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) { proxy.scrollTo(i, anchor: .center) }
                    }
                    .onAppear { proxy.scrollTo(current ?? 0, anchor: .center) }
                }
                }
            }
        case .plain(let text):
            ScrollView(.vertical, showsIndicators: false) {
                Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
            }
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            Text("No lyrics found for this song.").font(.system(size: 13)).foregroundStyle(Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The current lyric line in the compact island.
struct CompactLyricLine: View {
    @Environment(LyricsService.self) private var lyrics
    @Environment(NowPlayingService.self) private var music

    var body: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.25 : 3600)) { context in
            let line = lyrics.line(at: music.elapsed(at: context.date)) ?? "♪"
            Text(line)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .id(line)
                .transition(.push(from: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: line)
        }
        .padding(.horizontal, 14)
    }
}

/// Up Next: the following tracks (Music playlist order, or the Spotify
/// queue via the Web API when connected).
private struct QueueView: View {
    let track: NowPlayingService.Track
    @Environment(QueueService.self) private var queue
    @Environment(NowPlayingService.self) private var music
    @Environment(IslandModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ArtworkView(image: music.artwork, size: 34, radius: 7, placeholderIcon: music.player?.icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Up Next").font(.system(size: 13, weight: .semibold))
                    Text("After \(track.title)").font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
                Spacer()
                IconButton(symbol: "arrow.clockwise", size: 10, diameter: 28, help: "Refresh") {
                    Task { await queue.refresh(player: music.player, shuffle: music.shuffle) }
                }
                IconButton(symbol: "chevron.down", size: 11, diameter: 28, help: "Back to player") {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { model.queueExpanded = false }
                }
            }
            content
        }
        .task(id: track.id) { await queue.refresh(player: music.player, shuffle: music.shuffle) }
    }

    @ViewBuilder private var content: some View {
        switch queue.state {
        case .loaded:
            IslandScroll(axis: .vertical) {
                VStack(spacing: 2) {
                    if music.player == .music, music.shuffle == true {
                        Label("Shuffle is on. Music doesn't share its shuffled order, so this is playlist order.", systemImage: "shuffle")
                            .font(.system(size: 10)).foregroundStyle(Color.tertiaryText).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { i, item in
                        HStack(spacing: 10) {
                            QueueArtwork(url: item.artworkURL)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                                Text(item.artist).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                            }
                            Spacer()
                            Text("\(i + 1)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.tertiaryText)
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .modifier(HoverHighlight(cornerRadius: 9))
                    }
                }
            }
        case .needsSpotifyLogin:
            VStack(spacing: 8) {
                Image(systemName: "list.bullet").font(.system(size: 20)).foregroundStyle(Color.secondaryText)
                Text("Connect Spotify to see Up Next").font(.system(size: 13, weight: .semibold))
                Text("The Spotify app doesn't share its queue with other apps. Sign in once through Spotify's Web API in Settings › Features › Music.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 320)
                PillButton(title: "Open Settings", tint: .white, prominent: true) { model.collapse(); model.openSettings() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let message):
            Text(message).font(.system(size: 12)).foregroundStyle(Color.secondaryText).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading, .idle:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct QueueArtwork: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().aspectRatio(contentMode: .fill) } else { Color.white.opacity(0.08) }
                }
            } else {
                Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Color.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08))
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
