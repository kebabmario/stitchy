// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Owns every long-lived service and wires their events together.
/// Services only start when their feature is enabled, so disabled features
/// cost nothing at runtime.
@MainActor @Observable
final class AppServices {
    @ObservationIgnored let settings = AppSettings()
    @ObservationIgnored let island: IslandModel
    @ObservationIgnored let feed = ActivityFeed()
    @ObservationIgnored let battery = BatteryMonitor()
    @ObservationIgnored let network = NetworkMonitor()
    @ObservationIgnored let nowPlaying: NowPlayingService
    @ObservationIgnored let timers: TimerStore
    @ObservationIgnored let shelf = FileShelf()
    @ObservationIgnored let screenshots = ScreenshotWatcher()
    @ObservationIgnored let folderTracker = FolderTracker()
    @ObservationIgnored let mixer = AppVolumeMixer()
    @ObservationIgnored let dockPreviews = DockPreviews()
    @ObservationIgnored let windowSnapper = WindowSnapper()
    @ObservationIgnored let capture = CaptureService()
    @ObservationIgnored let annotator = AnnotationEditor()
    @ObservationIgnored let cameraMirror = CameraMirror()
    @ObservationIgnored let dictation = Dictation()
    @ObservationIgnored let xcodeBuilds = XcodeBuildMonitor()
    @ObservationIgnored let agents = AgentActivityMonitor()
    @ObservationIgnored let breaks = BreakReminder()
    @ObservationIgnored private var duplicates = DuplicateFilter()
    @ObservationIgnored let downloads = DownloadsMonitor()
    @ObservationIgnored let notifier = SystemNotifier()
    @ObservationIgnored let clipboard: ClipboardHistory
    @ObservationIgnored let audio = AudioMonitor()
    @ObservationIgnored let privacy = PrivacyGuard()
    @ObservationIgnored let notes = NotesStore()
    @ObservationIgnored let calendar: CalendarService
    @ObservationIgnored let aiUsage = AIUsageMonitor()
    @ObservationIgnored let launcher: Launcher
    @ObservationIgnored let gate: SensitiveGate
    @ObservationIgnored let privateLock: PrivateLock
    @ObservationIgnored let appleNotes = AppleNotesService()
    @ObservationIgnored let bluetooth = BluetoothMonitor()
    @ObservationIgnored let drives = DrivesMonitor()
    @ObservationIgnored let controls = SystemControls()
    @ObservationIgnored let lyrics = LyricsService()
    @ObservationIgnored let weather: WeatherService
    @ObservationIgnored let focus: FocusService
    @ObservationIgnored let mirror: NotificationMirror
    @ObservationIgnored let queue: QueueService
    @ObservationIgnored let hotkey = GlobalHotkey()
    @ObservationIgnored let extensions = ExtensionStore()
    @ObservationIgnored let extensionData = ExtensionDataService()
    @ObservationIgnored let extensionAutomations = ExtensionAutomationEngine()
    @ObservationIgnored lazy var extensionEditor = ExtensionEditorController(services: self)
    @ObservationIgnored lazy var floatingPlayer = FloatingPlayerController(services: self)

    init() {
        island = IslandModel(settings: settings)
        nowPlaying = NowPlayingService(settings: settings)
        timers = TimerStore(settings: settings, notifier: notifier)
        clipboard = ClipboardHistory(settings: settings)
        calendar = CalendarService(settings: settings)
        launcher = Launcher(settings: settings)
        gate = SensitiveGate(settings: settings)
        privateLock = PrivateLock(settings: settings, gate: gate)
        weather = WeatherService(settings: settings)
        focus = FocusService(settings: settings)
        mirror = NotificationMirror(settings: settings)
        queue = QueueService(settings: settings)
        wire()
    }

    func start() {
        notifier.configure()
        if !SnapshotRenderer.isRendering { shelf.restorePinned() }
        network.start()
        observeContinuously { [weak self] in self?.applyFeatureToggles() }
        // Only enabled extensions with a data source poll their API.
        observeContinuously { [weak self] in guard let self else { return }; self.extensionData.sync(with: self.extensions.extensions) }
        // Lyrics follow the current track however it was learned (launch-time
        // sync, notifications, or a player switch). Cached per song.
        observeContinuously { [weak self] in
            guard let self, self.settings.lyricsEnabled, let t = self.nowPlaying.track else { return }
            let embedded = self.nowPlaying.embeddedLyrics
            Task { await self.lyrics.load(title: t.title, artist: t.artist, album: t.album, duration: t.duration, embedded: embedded) }
        }
    }

    /// Starts or stops services to match the toggles in Settings.
    private func applyFeatureToggles() {
        settings.batteryEnabled ? battery.start() : battery.stop()
        settings.musicEnabled ? nowPlaying.start() : nowPlaying.stop()
        settings.downloadsEnabled ? downloads.start() : downloads.stop()
        settings.clipboardEnabled ? clipboard.start() : clipboard.stop()
        settings.hudEnabled ? audio.start() : audio.stop()
        settings.privacyGuardEnabled ? privacy.start() : privacy.stop()
        settings.calendarEnabled ? calendar.start() : calendar.stop()
        settings.bluetoothEnabled ? bluetooth.start() : bluetooth.stop()
        settings.drivesEnabled ? drives.start() : drives.stop()
        settings.shelfEnabled && settings.screenshotsToShelf ? screenshots.start() : screenshots.stop()
        if settings.shelfEnabled, !settings.trackedFolder.isEmpty {
            folderTracker.start(URL(fileURLWithPath: settings.trackedFolder, isDirectory: true))
        } else {
            folderTracker.stop()
        }
        settings.dockPreviewsEnabled ? dockPreviews.start() : dockPreviews.stop()
        settings.windowSnapEnabled ? windowSnapper.start() : windowSnapper.stop()
        settings.xcodeBuildAlerts ? xcodeBuilds.start() : xcodeBuilds.stop()
        settings.agentActivityEnabled ? agents.start() : agents.stop()
        breaks.interval = settings.breakMinutes * 60
        settings.breakReminders ? breaks.start() : breaks.stop()
        if !settings.lyricsEnabled { lyrics.clear() }
        settings.weatherEnabled ? weather.start() : weather.stop()
        settings.mirrorEnabled ? mirror.start() : mirror.stop()
        if !settings.timerEnabled { timers.stopAll() }
        if settings.hotkeyEnabled {
            hotkey.register(settings.hotkey)
        } else {
            hotkey.unregister()
        }
    }

    func post(_ event: ActivityEvent) {
        guard settings.alertsEnabled, duplicates.allows(event) else { return }
        if event.recordsInFeed { feed.add(event) }
        if event.showsAlert { island.present(event) }
    }

    private func wire() {
        if !SnapshotRenderer.isRendering { SystemAuth.removeLegacyFaceData() }
        SystemAuth.onPhase = { [weak self] in self?.island.showAuth($0) }
        battery.onEvent = { [weak self] in self?.post($0) }
        downloads.onEvent = { [weak self] in self?.post($0) }
        timers.onEvent = { [weak self] in self?.post($0) }
        calendar.onEvent = { [weak self] in self?.post($0) }
        shelf.onTransferEvent = { [weak self] in self?.post($0) }
        bluetooth.onEvent = { [weak self] in self?.post($0) }
        drives.onEvent = { [weak self] in self?.post($0) }
        weather.onEvent = { [weak self] in self?.post($0) }
        mirror.onIncoming = { [weak self] item in
            guard let self else { return }
            let isCall = item.kind == .call
            self.post(ActivityEvent(symbol: isCall ? "phone.fill" : "message.fill", tint: isCall ? .green : .blue,
                                    title: item.title, detail: item.body ?? item.app, tab: .home,
                                    recordsInFeed: false, alertDuration: isCall ? 12 : 4))
        }
        hotkey.onPress = { [weak self] in
            guard let self else { return }
            guard !self.island.isScreenLocked else { return }
            if self.island.isExpanded, self.island.tab == .launcher { self.island.collapse() } else { self.island.openLauncher() }
        }
        nowPlaying.onTrackChange = { [weak self] track, artwork in
            guard let self else { return }
            guard self.settings.trackChangeAlerts else { return }
            self.post(ActivityEvent(
                symbol: "music.note", tint: .pink, title: track.title, detail: track.artist,
                artwork: artwork, tab: .music, recordsInFeed: false
            ))
        }
        capture.onEvent = { [weak self] in self?.post($0) }
        extensionData.onUpdate = { [weak self] id, doc in
            guard let self, let ext = self.extensions.extensionNamed(id) else { return }
            self.extensionAutomations.evaluate(ext, doc: doc)
        }
        extensionAutomations.onAlert = { [weak self] alert, ext in
            guard let self else { return }
            self.post(ActivityEvent(symbol: ext.icon == ExtIconImage.rocket ? "sparkles" : ext.icon, tint: .purple, title: alert.title,
                                    detail: alert.message.isEmpty ? ext.name : alert.message,
                                    artwork: ExtIconImage.alertArtwork(ext), tab: .extensions, alertDuration: 5))
            if alert.notify {
                self.notifier.schedule(id: "ext-\(alert.automationID.uuidString)", title: alert.title,
                                       body: alert.message.isEmpty ? ext.name : alert.message, after: 1)
            }
        }
        annotator.onSaved = { [weak self] url in
            self?.shelf.add([url])
            self?.post(ActivityEvent(symbol: "pencil.tip.crop.circle", tint: .pink, title: "Annotated copy saved", detail: url.lastPathComponent, tab: .shelf))
        }
        cameraMirror.onError = { [weak self] message in
            self?.post(ActivityEvent(symbol: "video.slash", tint: .orange, title: "Camera Mirror", detail: message, tab: .tools, recordsInFeed: false))
        }
        dictation.onFinished = { [weak self] text in Task { await self?.capture.deliver(text: text, source: "dictation") } }
        breaks.isQuiet = { [weak self] in
            guard let self else { return true }
            return self.privacy.cameraActive || self.privacy.microphoneActive || self.mirror.activeCall != nil
        }
        breaks.onReminder = { [weak self] s in
            self?.post(ActivityEvent(symbol: s.symbol, tint: .mint, title: s.title, detail: s.detail, tab: .home, recordsInFeed: false, alertDuration: 8))
        }
        xcodeBuilds.onBuild = { [weak self] build in
            let time = Duration.seconds(build.duration).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))
            self?.post(ActivityEvent(
                symbol: build.succeeded ? "hammer.fill" : "xmark.octagon.fill", tint: build.succeeded ? .green : .red,
                title: build.succeeded ? "Build Succeeded" : "Build Failed",
                detail: build.succeeded ? "\(build.scheme) · \(time)\(build.warnings > 0 ? " · \(build.warnings) warnings" : "")"
                                        : "\(build.scheme) · \(build.errors) error\(build.errors == 1 ? "" : "s")",
                tab: .activity))
        }
        agents.onFinished = { [weak self] session in
            let took = Date().timeIntervalSince(session.started).clockStringFloor
            self?.post(ActivityEvent(symbol: "checkmark.seal.fill", tint: .orange, title: "\(session.agent.rawValue) finished",
                                     detail: session.project.isEmpty ? "took \(took)" : "\(session.project) · took \(took)",
                                     artwork: AppIcons.icon(session.agent.appName), tab: .activity))
        }
        windowSnapper.onNeedsPermission = { [weak self] in
            self?.post(ActivityEvent(symbol: "rectangle.split.2x1", tint: .orange, title: "Allow Accessibility for snapping",
                                     detail: "System Settings › Privacy & Security › Accessibility", tab: .home, recordsInFeed: false))
        }
        folderTracker.onNewFiles = { [weak self] urls in
            guard let self, self.shelf.add(urls) > 0 else { return }
            self.post(ActivityEvent(symbol: "folder.fill", tint: .blue,
                                    title: urls.count == 1 ? "New in \(self.folderTracker.folder?.lastPathComponent ?? "folder")" : "\(urls.count) new files",
                                    detail: urls.count == 1 ? urls[0].lastPathComponent : self.folderTracker.folder?.lastPathComponent, tab: .shelf,
                                    recordsInFeed: false))
        }
        screenshots.onScreenshot = { [weak self] url in
            guard let self, self.shelf.add([url]) > 0 else { return }
            self.post(ActivityEvent(symbol: "camera.viewfinder", tint: .cyan, title: "Screenshot on Shelf",
                                    detail: url.lastPathComponent, tab: .shelf, recordsInFeed: false))  // shelf.onAdd already logs it
        }
        shelf.onAdd = { [weak self] count in
            self?.post(ActivityEvent(
                symbol: "tray.and.arrow.down.fill", tint: .blue,
                title: count == 1 ? "Added 1 file to Shelf" : "Added \(count) files to Shelf",
                tab: .shelf, showsAlert: false
            ))
        }
        audio.onChange = { [weak self] change in
            guard let self, self.settings.hudEnabled else { return }
            let a = self.audio
            switch change {
            case .volume, .mute:
                self.island.showHUD(HUDEvent(symbol: a.volumeSymbol, title: a.isMuted ? "Muted" : a.outputName,
                                             level: a.isMuted ? 0 : Double(a.volume)))
            case .output:
                self.island.showHUD(HUDEvent(symbol: "hifispeaker.fill", tint: .blue, title: a.outputName))
            }
        }
        privacy.onChange = { [weak self] camera, mic in
            guard let self, self.settings.privacyGuardEnabled else { return }
            if camera || mic {
                self.post(ActivityEvent(symbol: camera ? "video.fill" : "mic.fill", tint: camera ? .green : .orange,
                                        title: camera ? "Camera Turned On" : "Microphone Turned On",
                                        detail: "macOS doesn't say which app", tab: .home, alertDuration: 2.4))
            }
        }
        launcher.actions = [
            .init(id: "timer5", title: "Start 5-Minute Timer", symbol: "timer") { [weak self] in
                self?.timers.addCountdown(seconds: 300)
                self?.island.select(.timer)
            },
            .init(id: "focus", title: "Start Focus Session", symbol: "brain.head.profile") { [weak self] in
                self?.timers.pomodoro.start()
                self?.island.select(.timer)
            },
            .init(id: "stopwatch", title: "Start Stopwatch", symbol: "stopwatch") { [weak self] in
                self?.timers.stopwatch.start()
                self?.island.select(.timer)
            },
            .init(id: "note", title: "New Apple Note", symbol: "square.and.pencil") { [weak self] in
                self?.appleNotes.startCompose()
                self?.island.select(.notes)
            },
            .init(id: "clipboard", title: "Show Clipboard History", symbol: "doc.on.clipboard") { [weak self] in
                self?.island.select(.shelf)
            },
            .init(id: "ocr", title: "Capture Text from Screen", symbol: "text.viewfinder") { [weak self] in
                guard let self else { return }
                self.island.collapse()
                Task { await self.capture.captureTextFromScreen() }
            },
            .init(id: "annotate", title: "Annotate Screenshot", symbol: "pencil.tip.crop.circle") { [weak self] in
                guard let self else { return }
                self.island.collapse()
                Task { if let url = await self.capture.captureRegion() { self.annotator.open(url, deleteSourceOnClose: true) } }
            },
            .init(id: "mirror", title: "Camera Mirror", symbol: "person.crop.circle") { [weak self] in
                self?.island.collapse()
                self?.cameraMirror.toggle()
            },
            .init(id: "dictate", title: "Dictate to Clipboard", symbol: "waveform") { [weak self] in
                self?.island.select(.tools)
                self?.dictation.toggle()
            },
            .init(id: "floating", title: "Floating Player", symbol: "pip") { [weak self] in
                self?.island.collapse()
                self?.floatingPlayer.toggle()
            },
            .init(id: "awake", title: "Keep Mac Awake for 1 Hour", symbol: "cup.and.saucer.fill") { [weak self] in
                self?.controls.keepAwake(for: 3600)
            },
            .init(id: "mic", title: "Mute / Unmute Microphone", symbol: "mic.slash.fill") { [weak self] in
                guard let self else { return }
                self.controls.refreshMic()
                self.controls.setMicMuted(!self.controls.micMuted)
            },
            .init(id: "settings", title: "Open Stitchy Settings", symbol: "gearshape") { [weak self] in
                self?.island.collapse()
                self?.island.openSettings()
            },
        ]
    }
}
