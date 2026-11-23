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
        if settings.musicEnabled, settings.showMusicActivity, nowPlaying.isPlaying {
            list.append(.init(id: "music", kind: .music, priority: IslandActivity.Priority.music,
                              symbol: "music.note", tint: nowPlaying.accent, title: nowPlaying.track?.title ?? "Music", tab: .music))
        }
        return list.sorted { $0.priority > $1.priority }
    }

    /// What the compact island shows (respects the master switch).
    var compactActivities: [IslandActivity] {
        settings.compactActivities ? activities : []
    }
}
