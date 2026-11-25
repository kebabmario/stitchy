import SwiftUI

/// The expanded island: a tab header and one feature page.
struct ExpandedIslandView: View {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let geometry = model.geometry
        VStack(spacing: IslandGeometry.headerSpacing) {
            IslandHeader(tabs: model.isScreenLocked ? [] : visibleTabs)
                .frame(height: IslandGeometry.headerHeight)
            page
                .id(currentTab)
                .transition(.blurReplace)
                .frame(maxWidth: .infinity)
                // Lyrics / Up Next grow the island; the page must grow with it or the bottom stays empty.
                .frame(height: currentTab.contentHeight + (currentTab == .music ? geometry.extraHeight : 0), alignment: .top)
        }
        .padding(.top, geometry.expandedTopPadding)
        .padding(.horizontal, 18)
        .padding(.bottom, IslandGeometry.bottomPadding)
        .frame(width: geometry.expandedWidth, alignment: .top)
        .foregroundStyle(.white)
        .modifier(ShelfDropTarget())
    }

    private var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { tab in
            switch tab {
            case .home, .activity, .calendar, .weather: true
            case .music: settings.musicEnabled
            case .timer: settings.timerEnabled
            case .shelf: settings.shelfEnabled || settings.clipboardEnabled
            case .notes: settings.notesEnabled
            case .launcher: settings.launcherEnabled
            case .tools: settings.toolsEnabled
            }
        }
    }

    private var currentTab: IslandTab {
        if model.isScreenLocked { return .music }
        return visibleTabs.contains(model.tab) ? model.tab : .home
    }

    @ViewBuilder private var page: some View {
        if model.isScreenLocked {
            LockScreenPage()
        } else {
            unlockedPage
        }
    }

    @ViewBuilder private var unlockedPage: some View {
        switch currentTab {
        case .home: DashboardView()
        case .music: MusicView()
        case .timer: TimersView()
        case .weather: WeatherView()
        case .shelf: ShelfView()
        case .notes: PrivateGate { NotesView() }
        case .calendar: CalendarView()
        case .launcher: LauncherView()
        case .tools: ToolsView()
        case .activity: ActivityView()
        }
    }
}

struct IslandHeader: View {
    let tabs: [IslandTab]
    @Environment(IslandModel.self) private var model
    @Environment(BatteryMonitor.self) private var battery
    @Environment(AppSettings.self) private var settings
    @Environment(ActivityFeed.self) private var feed
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 0) {
            // iOS 26-style floating tab bar: the tabs share one soft capsule.
            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    TabButton(tab: tab, isSelected: model.tab == tab, badge: tab == .activity && feed.unread > 0, namespace: selection) {
                        model.select(tab)
                    }
                }
            }
            .padding(2)
            .background {
                if !tabs.isEmpty {
                    Capsule().fill(.white.opacity(0.06))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
                }
            }
            // Empty header space toggles the island closed (click-to-toggle).
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { model.headerTapped() }
            if settings.batteryEnabled, battery.snapshot.hasBattery {
                HStack(spacing: 4) {
                    Text("\(battery.snapshot.percent)%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: battery.snapshot.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(battery.snapshot.tint, .white.opacity(0.4))
                        .font(.system(size: 13))
                }
                .fixedSize()
                .padding(.trailing, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Battery \(battery.snapshot.percent) percent, \(battery.snapshot.statusText)")
            }
            if !model.isScreenLocked {
                IconButton(symbol: "gearshape.fill", size: 11, diameter: 24, help: "Stitchy Settings") {
                    model.collapse()
                    model.openSettings()
                }
            }
        }
    }
}

private struct TabButton: View {
    let tab: IslandTab
    let isSelected: Bool
    let badge: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 30, height: 24)
                .foregroundStyle(.white.opacity(isSelected ? 1 : hovering ? 0.8 : 0.42))
                .background {
                    if isSelected {
                        Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "tab", in: namespace)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge {
                        Circle().fill(.red).frame(width: 6, height: 6).offset(x: -5, y: 4)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plainHit)
        .onHover { hovering = $0 }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Segmented pills used inside pages ("Timers · Stopwatch · Focus").
struct Segmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .foregroundStyle(.white.opacity(selection == value ? 1 : 0.5))
                        .background {
                            if selection == value {
                                Capsule().fill(.white.opacity(0.14)).matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plainHit)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.05)))
    }
}

/// Hides private content until unlocked with Touch ID or the password.
struct PrivateGate<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(PrivateLock.self) private var lock
    @State private var result: SystemAuth.Phase?

    var body: some View {
        if lock.isLocked || result == .success {
            VStack(spacing: 10) {
                TouchIDGlyph(phase: lock.isUnlocking ? .scanning : result, size: 40)
                    .frame(width: 64, height: 64)
                Text(lock.isUnlocking ? (SystemAuth.hasTouchID ? "Touch the sensor" : "Enter your password") : "Private")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.opacity)
                if !lock.isUnlocking {
                    PillButton(title: "Unlock", symbol: SystemAuth.hasTouchID ? "touchid" : "lock.open.fill",
                               tint: .white, prominent: true) {
                        Task { await unlock() }
                    }
                }
                if let error = lock.lastError, !lock.isUnlocking {
                    Text(error).font(.system(size: 10)).foregroundStyle(.red.opacity(0.85)).lineLimit(2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Interaction.spring, value: lock.isUnlocking)
        } else {
            content
        }
    }

    private func unlock() async {
        result = nil
        await lock.unlock()
        result = lock.isLocked ? .failed : .success
        // Let the check mark land before revealing the content.
        if result == .success { try? await Task.sleep(for: .milliseconds(550)) }
        withAnimation(Interaction.spring) { result = nil }
    }
}

/// Dropping files anywhere on the expanded island adds them to the shelf.
private struct ShelfDropTarget: ViewModifier {
    @Environment(IslandModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(FileShelf.self) private var shelf

    func body(content: Content) -> some View {
        if SnapshotRenderer.isRendering {
            content  // ImageRenderer can't draw AppKit-backed drop targets
        } else {
            content.dropDestination(for: URL.self) { urls, _ in
                guard settings.shelfEnabled else { return false }
                let added = shelf.add(urls)
                model.select(.shelf)
                model.convertToHover()
                return added > 0
            } isTargeted: { targeted in
                model.isDropTargeted = targeted && settings.shelfEnabled
            }
        }
    }
}

/// What the island may show while the Mac is locked: Now Playing (with
/// lyrics) and the time. No notes, clipboard, files, launcher or settings.
struct LockScreenPage: View {
    @Environment(NowPlayingService.self) private var music

    var body: some View {
        if music.track != nil {
            LockScreenNowPlaying()
        } else {
            clock
        }
    }

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 4) {
                Image(systemName: "lock.fill").foregroundStyle(Color.secondaryText)
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text("Unlock to use Stitchy").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Animated Touch ID glyph: rings ripple out from the fingerprint and a
/// highlight sweeps up it while macOS asks for Touch ID, then it morphs to
/// a check or a cross. macOS reports no sensor events, so "scanning" covers
/// the whole system prompt.
struct TouchIDGlyph: View {
    let phase: SystemAuth.Phase?
    var size: CGFloat = 40
    @State private var animate = false

    private var look: (symbol: String, tint: Color) {
        switch phase {
        case .success: ("checkmark.circle.fill", .green)
        case .failed: ("xmark.circle.fill", .red)
        default: (SystemAuth.hasTouchID ? "touchid" : "lock.fill", phase == .scanning ? .pink : .white.opacity(0.85))
        }
    }

    var body: some View {
        let scanning = phase == .scanning
        ZStack {
            if scanning {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(Color.pink.opacity(0.5), lineWidth: 1.5)
                        .scaleEffect(animate ? 1.55 : 0.75)
                        .opacity(animate ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double(i) * 0.7), value: animate)
                }
            }
            Image(systemName: look.symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(look.tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: scanning)
                .overlay {
                    if scanning {
                        // A soft highlight sweeping up the fingerprint.
                        LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: size * 0.3)
                            .offset(y: animate ? -size * 0.5 : size * 0.5)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: animate)
                            .mask(Image(systemName: look.symbol).font(.system(size: size)))
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(phase == .success ? 1.08 : 1)
        }
        .frame(width: size * 1.6, height: size * 1.6)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: phase)
        .onAppear { animate = true }
        .accessibilityLabel(phase == .scanning ? "Waiting for Touch ID" : phase == .success ? "Unlocked" : "Locked")
    }
}

/// Lock screen Now Playing: the cover's colours fill the background, a big
/// clock sits behind the cover's subject (depth, via Vision), synced lyrics
/// and Up Next beside it. Read-only data; controls only play/skip.
struct LockScreenNowPlaying: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(LyricsService.self) private var lyrics
    @Environment(QueueService.self) private var queue
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            backdrop
            HStack(alignment: .top, spacing: DS.Space.m) {
                DepthArtwork(image: music.artwork, size: 136)
                VStack(alignment: .leading, spacing: 0) {
                    Text(music.track?.title ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(music.track.map { $0.artist.isEmpty ? $0.album : $0.artist } ?? "")
                        .font(DS.body).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    lyricLines.padding(.top, DS.Space.s)
                    Spacer(minLength: 4)
                    upNext
                    transport.padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DS.Space.s)
        }
        .foregroundStyle(.white)
        .task(id: music.track?.id) {
            if settings.lyricsEnabled, let t = music.track {
                await lyrics.load(title: t.title, artist: t.artist, album: t.album, duration: t.duration, embedded: music.embeddedLyrics)
            }
            await queue.refresh(player: music.player, shuffle: music.shuffle)
        }
    }

    /// The cover, blurred and darkened, fills the page.
    private var backdrop: some View {
        GeometryReader { geo in
            Group {
                if let art = music.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 36).saturation(1.3)
                        .overlay(LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                } else {
                    music.accent.opacity(0.25)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous))
        }
    }

    /// Current line large, next line dimmed; updates with playback.
    private var lyricLines: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: music.isPlaying ? 0.25 : 3600)) { context in
            let (current, next) = Self.lines(lyrics.state, at: music.elapsed(at: context.date))
            VStack(alignment: .leading, spacing: 2) {
                Text(current ?? "♪").font(.system(size: 13, weight: .bold)).lineLimit(2)
                    .id(current).transition(.push(from: .bottom).combined(with: .opacity))
                if let next { Text(next).font(DS.caption).foregroundStyle(.white.opacity(0.5)).lineLimit(1) }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.9), value: current)
        }
    }

    nonisolated static func lines(_ state: LyricsService.State, at time: TimeInterval?) -> (String?, String?) {
        guard case .synced(let lines) = state, let time, let i = LyricsService.index(in: lines, at: time + 0.2) else { return (nil, nil) }
        let next = lines[(i + 1)...].first { !$0.text.isEmpty }?.text
        return (lines[i].text.isEmpty ? nil : lines[i].text, next)
    }

    @ViewBuilder private var upNext: some View {
        if let item = queue.items.first {
            HStack(spacing: 4) {
                Text("UP NEXT").font(DS.label).tracking(0.8).foregroundStyle(.white.opacity(0.5))
                Text("\(item.title) · \(item.artist)").font(DS.caption).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: DS.Space.m) {
            button("backward.fill", 12) { music.previous() }
            button(music.isPlaying ? "pause.fill" : "play.fill", 15) { music.playPause() }
            button("forward.fill", 12) { music.next() }
        }
        .disabled(!music.controlsEnabled)
    }

    private func button(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .bold)).frame(width: 26, height: 22)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Cover art with a big clock behind its subject. Vision finds the subject
/// once per cover (on this Mac); without one, the clock just sits on top.
struct DepthArtwork: View {
    let image: NSImage?
    let size: CGFloat
    @State private var cutout: NSImage?

    /// "4:04" or "16:04" by the user's locale, without AM/PM or a leading zero.
    static func clock(_ date: Date, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("jmm")
        f.amSymbol = ""
        f.pmSymbol = ""
        return f.string(from: date).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ArtworkView(image: image, size: size, radius: size * 0.12)
            TimelineView(.everyMinute) { context in
                Text(Self.clock(context.date))
                    .font(DS.numerals(size * 0.3, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6)
                    .padding(.top, size * 0.06)
            }
            if let cutout {
                Image(nsImage: cutout).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size, height: size)
        .task(id: image.map { ObjectIdentifier($0) }) {
            cutout = nil
            guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let result = await Task.detached(priority: .utility) { (try? CaptureService.subjectCutout(cg)).map(UncheckedBox.init) }.value
            withAnimation(.easeOut(duration: 0.4)) { cutout = result.map { NSImage(cgImage: $0.value, size: .zero) } }
        }
    }
}
