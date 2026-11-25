import SwiftUI

/// One ongoing thing the island can show. Every feature reports its live
/// state through this single model; the compact island shows the highest
/// priority activity and the expanded Home page lists all of them.
struct IslandActivity: Identifiable {
    enum Kind {
        case camera, microphone
        case countdown(TimerService)
        case pomodoro(Pomodoro)
        case stopwatch(Stopwatch)
        case download(DownloadsMonitor.Download)
        case airDrop(Int)
        case music
        case keepAwake
        case micMuted
        case weather
        case focus
        case call
        case agent(status: String, agent: AgentActivityMonitor.Agent, started: Date)
    }

    let id: String
    let kind: Kind
    /// Higher wins the compact island.
    let priority: Int
    let symbol: String
    let tint: Color
    let title: String
    let tab: IslandTab

    /// Privacy indicators outrank everything; finished timers outrank
    /// running ones; passive media is lowest.
    enum Priority {
        static let privacy = 100
        static let timerFinished = 90
        static let countdown = 80
        static let pomodoro = 75
        static let transfer = 65
        static let stopwatch = 60
        static let music = 40
    }
}

extension AppServices {
    /// All live activities, highest priority first.
    var activities: [IslandActivity] {
        var list: [IslandActivity] = []
        if settings.privacyGuardEnabled, settings.showPrivacyActivity {
            if privacy.cameraActive {
                list.append(.init(id: "camera", kind: .camera, priority: IslandActivity.Priority.privacy + 1,
                                  symbol: "video.fill", tint: .green, title: "Camera in use", tab: .home))
            }
            if privacy.microphoneActive {
                list.append(.init(id: "mic", kind: .microphone, priority: IslandActivity.Priority.privacy,
                                  symbol: "mic.fill", tint: .orange, title: "Microphone in use", tab: .home))
            }
        }
        if settings.timerEnabled, settings.showTimerActivity {
            for timer in timers.activeCountdowns {
                list.append(.init(id: "timer-\(timer.id)", kind: .countdown(timer),
                                  priority: timer.phase == .finished ? IslandActivity.Priority.timerFinished : IslandActivity.Priority.countdown,
                                  symbol: "timer", tint: .orange, title: timer.label, tab: .timer))
            }
            let pomodoro = timers.pomodoro
            if pomodoro.timer.isActive {
                list.append(.init(id: "pomodoro", kind: .pomodoro(pomodoro),
                                  priority: pomodoro.timer.phase == .finished ? IslandActivity.Priority.timerFinished : IslandActivity.Priority.pomodoro,
                                  symbol: pomodoro.phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill",
                                  tint: pomodoro.phase.tint, title: pomodoro.phase.title, tab: .timer))
            }
            if timers.stopwatch.isActive {
                list.append(.init(id: "stopwatch", kind: .stopwatch(timers.stopwatch), priority: IslandActivity.Priority.stopwatch,
                                  symbol: "stopwatch", tint: .yellow, title: "Stopwatch", tab: .timer))
            }
        }
        if settings.showTransferActivity {
            if let count = shelf.airDropInProgress {
                list.append(.init(id: "airdrop", kind: .airDrop(count), priority: IslandActivity.Priority.transfer + 1,
                                  symbol: "airplayaudio", tint: .blue, title: "AirDrop", tab: .shelf))
            }
            if settings.downloadsEnabled {
                for d in downloads.active.prefix(3) {
                    list.append(.init(id: "dl-\(d.id)", kind: .download(d), priority: IslandActivity.Priority.transfer,
                                      symbol: "arrow.down", tint: .blue, title: d.name, tab: .activity))
                }
            }
        }
        if let call = mirror.activeCall {
            list.append(.init(id: "call", kind: .call, priority: IslandActivity.Priority.privacy + 2, symbol: "phone.fill",
                              tint: .green, title: call.title, tab: .home))
        }
        if settings.agentActivityEnabled, let session = agents.live {
            list.append(.init(id: "agent", kind: .agent(status: session.status, agent: session.agent, started: session.started), priority: 50,
                              symbol: session.agent == .claude ? "sparkle" : "chevron.left.forwardslash.chevron.right", tint: .orange,
                              title: session.project.isEmpty ? session.agent.rawValue : "\(session.agent.rawValue) · \(session.project)",
                              tab: .activity))
        }
        if focus.isFocused == true {
            list.append(.init(id: "focus", kind: .focus, priority: 20, symbol: "moon.fill", tint: .indigo, title: "Focus", tab: .home))
        }
        if controls.isKeepingAwake {
            list.append(.init(id: "awake", kind: .keepAwake, priority: 30, symbol: "cup.and.saucer.fill",
                              tint: .yellow, title: "Keeping Awake", tab: .home))
        }
        if controls.micMuted {
            list.append(.init(id: "micmuted", kind: .micMuted, priority: IslandActivity.Priority.privacy - 1, symbol: "mic.slash.fill",
                              tint: .red, title: "Microphone Muted", tab: .home))
        }
        if settings.musicEnabled, settings.showMusicActivity, nowPlaying.isPlaying {
            list.append(.init(id: "music", kind: .music, priority: IslandActivity.Priority.music,
                              symbol: "music.note", tint: nowPlaying.accent, title: nowPlaying.track?.title ?? "Music", tab: .music))
        }
        // Weather only fills an otherwise idle island, and only if asked for.
        if list.isEmpty, settings.weatherEnabled, settings.compactWeather, let c = weather.current {
            list.append(.init(id: "weather", kind: .weather, priority: 1,
                              symbol: WeatherService.describe(c.code, isDay: c.isDay).symbol, tint: .cyan, title: "Weather", tab: .weather))
        }
        return list.sorted { $0.priority > $1.priority }
    }

    /// The island's size for `mode`. Music only needs its cover and visualizer
    /// beside the notch, so its live island is narrower than other activities'.
    func islandSize(_ mode: IslandGeometry.Mode) -> CGSize {
        let geometry = island.geometry
        var size = geometry.size(mode, tab: island.tab)
        switch compactActivities.first?.kind {
        case .music?:
            switch mode {
            case .live: size.width = geometry.compact.width + 52
            case .liveLyrics: size.width = geometry.compact.width + 96
            default: break
            }
        case .agent?:
            if mode == .liveLyrics { size.width = geometry.compact.width + 120 }   // room for "project · step"
        default: break
        }
        return size
    }

    /// The island's current mode; shared by the view and hit-testing.
    var islandMode: IslandGeometry.Mode {
        let live = compactActivities
        // The strip under the island: the current lyric for music, the current step for a coding agent.
        let lyricStrip: Bool = {
            if case .agent = live.first?.kind { return true }
            guard settings.lyricsEnabled, settings.compactLyrics, case .music = live.first?.kind,
                  case .synced = lyrics.state else { return false }
            return true
        }()
        return island.mode(hasLiveActivity: !live.isEmpty, lyricStrip: lyricStrip)
    }

    /// What the compact island shows (respects the master switch).
    var compactActivities: [IslandActivity] {
        settings.compactActivities ? activities : []
    }

    /// Second and third live activities, shown as bubbles beside the island
    /// (right, then left) while the first keeps the island.
    var bubbleActivities: [IslandActivity] {
        guard settings.activityBubbles, !island.isExpanded, island.alert == nil, island.hud == nil else { return [] }
        return Array(compactActivities.dropFirst().prefix(2))
    }

    /// Extra width on each side taken by bubbles (for hit-testing).
    var bubbleExtent: CGFloat {
        bubbleActivities.isEmpty ? 0 : IslandBubble.size(for: island.geometry).width + IslandBubble.gap
    }
}
