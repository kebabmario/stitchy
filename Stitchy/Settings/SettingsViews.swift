import ApplicationServices
import Speech
import CoreBluetooth
import AVFoundation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var loginStatus = LaunchAtLogin.status
    @State private var loginError: String?
    @State private var confirmReset = false
    @Environment(SensitiveGate.self) private var gate

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: { enabled in
                        do { try LaunchAtLogin.set(enabled); loginError = nil } catch { loginError = error.localizedDescription }
                        loginStatus = LaunchAtLogin.status
                    }
                ))
                if loginStatus == .requiresApproval {
                    HStack {
                        Text("Approve Stitchy in Login Items to finish.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SystemSettingsLink.open(SystemSettingsLink.loginItems) }
                    }
                }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.callout) }
                Toggle("Show island", isOn: $settings.islandVisible)
                Picker("Display", selection: $settings.display) {
                    ForEach(DisplayChoice.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Open launcher with a shortcut", isOn: $settings.hotkeyEnabled)
                Picker("Shortcut", selection: $settings.hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!settings.hotkeyEnabled)
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Opens the island on the launcher with search focused. Press it again to close. Esc also closes the island.")
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                HStack {
                    Text("Restore every preference to its default.")
                    Spacer()
                    Button("Reset Settings…", role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = LaunchAtLogin.status }
        .confirmationDialog("Reset all Stitchy settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                Task { if await gate.authorize("reset all Stitchy settings") { settings.reset() } }
            }
        } message: {
            Text("Notes, focus history, launcher items and files on your shelf are kept.")
        }
    }
}

// MARK: - Island

struct IslandSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(IslandModel.self) private var model

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                Picker("Style", selection: $settings.style) {
                    ForEach(IslandStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                slider("Notch width", $settings.notchWidth, 150...280, "pt")
                Toggle("Match menu bar height", isOn: Binding(
                    get: { settings.notchHeight == 0 },
                    set: { settings.notchHeight = $0 ? 0 : Double(model.menuBarHeight.rounded()) }
                ))
                if settings.notchHeight > 0 {
                    slider("Notch height", $settings.notchHeight, 22...48, "pt")
                }
                slider("Expanded width", $settings.expandedWidth, 420...560, "pt")
                slider("Distance from top", $settings.topGap, 0...40, "pt")
                slider("Horizontal offset", $settings.horizontalOffset, -300...300, "pt")
                Toggle("Show on the Lock Screen", isOn: $settings.lockScreenIsland)
                Text("Uses private macOS window-server APIs (adapted from SkyLightWindow, MIT). While locked, the island shows only Now Playing, lyrics and the time: no notes, clipboard, files or settings. Turning this off takes effect after restarting Stitchy. A future macOS update may break it; Stitchy then just hides it.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Toggle("Hide when an app is in full screen", isOn: $settings.hideInFullScreen)
                    Spacer()
                    Button("Restore Defaults") {
                        settings.notchWidth = 190; settings.notchHeight = 0; settings.expandedWidth = 460
                        settings.topGap = 0; settings.horizontalOffset = 0
                    }
                }
            }
            Section("Expansion") {
                Toggle("Expand on hover", isOn: $settings.hoverToExpand)
                slider("Hover delay", $settings.hoverDelay, 0...0.8, "ms", scale: 1000, step: 0.05)
                    .disabled(!settings.hoverToExpand)
                slider("Hover sensitivity", $settings.hoverMargin, 0...24, "pt", step: 1)
                Toggle("Collapse when the pointer leaves", isOn: $settings.collapseOnExit)
                    .disabled(!settings.hoverToExpand)
                Toggle("Click to expand", isOn: $settings.clickToExpand)
                Toggle("Haptic feedback on expand", isOn: $settings.haptics)
            }
            Section {
                Picker("Animation", selection: $settings.animationStyle) {
                    ForEach(AnimationStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Animate music visualizer", isOn: $settings.animatedVisualizer)
            } header: {
                Text("Animation")
            } footer: {
                Text("Hover sensitivity adds slack around the island so it doesn't flicker at the edge. Reduce Motion always uses short, simple transitions.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Labeled slider with a value readout.
func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String,
            scale: Double = 1, step: Double = 1) -> some View {
    LabeledContent(title) {
        HStack {
            Slider(value: value, in: range, step: step).frame(width: 190)
            Text("\(Int((value.wrappedValue * scale).rounded())) \(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Features

struct FeaturesSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarService.self) private var calendar

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Island & Alerts") {
                feature("Live Alerts & Activity Feed", "bell.fill", .red, "Short alerts in the island and a history feed.", $settings.alertsEnabled)
                feature("Calendar", "calendar", .red, "Today's schedule and meeting reminders. Needs calendar access.", Binding(
                    get: { settings.calendarEnabled },
                    set: { on in
                        if on, calendar.access != .granted { Task { await calendar.requestAccess() } } else { settings.calendarEnabled = on }
                    }))
                feature("Battery", "battery.100percent", .green, "Charge level, charging and low-battery alerts.", $settings.batteryEnabled)
                feature("Camera Guard", "video.fill", .green, "Shows when the camera or microphone is in use.", $settings.privacyGuardEnabled)
            }
            Section("Media") {
                feature("Music", "music.note", .pink, "Apple Music and Spotify.", $settings.musicEnabled)
                feature("System HUD", "speaker.wave.2.fill", .gray, "Volume, mute and audio output changes.", $settings.hudEnabled)
            }
            Section("Files & Productivity") {
                feature("File Shelf", "tray.full.fill", .teal, "Drag files onto the island to hold them.", $settings.shelfEnabled)
                feature("Shake to Open Shelf", "hand.draw.fill", .teal, "While dragging a file, shake it to open the shelf.", $settings.shakeToShelf)
                feature("Downloads", "arrow.down.circle.fill", .blue, "Watches ~/Downloads. macOS asks for folder access.", $settings.downloadsEnabled)
                feature("Notes", "note.text", .yellow, "Your Apple Notes in the island: browse, search, create, open.", $settings.notesEnabled)
                feature("Timers", "timer", .orange, "Countdowns, stopwatch and Focus sessions.", $settings.timerEnabled)
                feature("Launcher", "magnifyingglass", .indigo, "Search apps, folders, Shortcuts and actions.", $settings.launcherEnabled)
                feature("Tools", "wrench.and.screwdriver.fill", .gray, "Calculator with history, and developer tools (JSON, Base64, hashes, JWT, QR…).", $settings.toolsEnabled)
                feature("Break Reminders", "figure.walk", .mint, "After a stretch of active use: rest your eyes, move, drink, breathe. Quiet during calls; idle time resets it.", $settings.breakReminders)
                if settings.breakReminders {
                    Stepper("Every \(Int(settings.breakMinutes)) minutes", value: $settings.breakMinutes, in: 20...120, step: 5)
                }
            }
            Section("System") {
                feature("Bluetooth Devices", "airpods", .blue, "Shows AirPods, keyboards and other devices connecting. macOS asks for Bluetooth access.", $settings.bluetoothEnabled)
                feature("Drives", "externaldrive.fill", .gray, "USB and SD drives appear with one-tap Eject.", $settings.drivesEnabled)
                feature("Window Snapping", "rectangle.split.2x1", .orange, "⌃⌥ ←→↑↓ halves · ⌃⌥ U I J K quarters · ⌃⌥ D F G thirds · ⌃⌥ E T two-thirds · ⌃⌥↩ maximize · ⌃⌥C center · ⌃⌥⌘→ next display. Needs Accessibility.", $settings.windowSnapEnabled)
                feature("Dock Window Previews", "dock.rectangle", .blue, "Hover an app in the Dock to see its windows; click one to switch. Needs Accessibility and Screen Recording.", $settings.dockPreviewsEnabled)
            }
            Section("Developer") {
                feature("Xcode Build Alerts", "hammer.fill", .blue, "An alert when an Xcode or xcodebuild build finishes: scheme, time, errors. Reads DerivedData logs only.", $settings.xcodeBuildAlerts)
                feature("Coding Agent Activity", "sparkle", .orange, "Live Claude Code and Codex status, and an alert when they finish. Reads their local session logs; shows only the tool and file name.", $settings.agentActivityEnabled)
                feature("AI Usage", "sparkle", .orange, "Claude Code and Codex usage from local logs.", $settings.aiUsageEnabled)
            }
            Section {
                Toggle("Show live activities in the compact island", isOn: $settings.compactActivities)
                Toggle("Show extra activities as bubbles beside the island", isOn: $settings.activityBubbles).disabled(!settings.compactActivities)
                Toggle("Timers, stopwatch and Focus", isOn: $settings.showTimerActivity).disabled(!settings.compactActivities)
                Toggle("Music", isOn: $settings.showMusicActivity).disabled(!settings.compactActivities)
                Toggle("Downloads and AirDrop", isOn: $settings.showTransferActivity).disabled(!settings.compactActivities)
                Toggle("Camera and microphone", isOn: $settings.showPrivacyActivity).disabled(!settings.compactActivities)
                Toggle("Coding agents (Claude Code, Codex)", isOn: $settings.agentActivityEnabled)
            } header: {
                Text("Activity Visibility")
            } footer: {
                Text("When several are active, the island shows the most important one: camera/mic, then timers, transfers, then music. All of them are listed on Home.")
            }
            Section("Music") {
                Toggle("Show an alert when the track changes", isOn: $settings.trackChangeAlerts)
                Toggle("Artwork, progress and controls (Automation)", isOn: $settings.musicControlsEnabled)
                Toggle("Synced lyrics", isOn: $settings.lyricsEnabled)
                Toggle("Show the current line in the compact island", isOn: $settings.compactLyrics).disabled(!settings.lyricsEnabled)
                Text("Lyrics come from LRCLIB (lrclib.net), a free public database: Stitchy sends the song's title, artist, album and length, once per song (results are cached). Spotify doesn't share lyrics with other apps. Lyrics stored with Apple Music tracks are used when LRCLIB has none.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SpotifySettings()
            WeatherFocusSettings()
            CommunicationSettings()
            Section("Pomodoro") {
                stepper("Focus", $settings.focusMinutes, 5...90)
                stepper("Short break", $settings.shortBreakMinutes, 1...30)
                stepper("Long break", $settings.longBreakMinutes, 5...60)
                Stepper("Long break every \(Int(settings.sessionsPerLongBreak)) sessions", value: $settings.sessionsPerLongBreak, in: 2...8)
            }
            Section("Calendar") {
                stepper("Remind me before meetings", $settings.meetingReminderMinutes, 0...30)
            }
        }
        .formStyle(.grouped)
    }

    private func stepper(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        Stepper("\(title): \(Int(value.wrappedValue)) min", value: value, in: range)
    }
}

func feature(_ title: String, _ symbol: String, _ tint: Color, _ detail: String, _ isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Clipboard & Shelf

struct ClipboardSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardHistory.self) private var clipboard

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Keep clipboard history", isOn: $settings.clipboardEnabled)
                Stepper("Remember \(Int(settings.clipboardHistorySize)) items", value: $settings.clipboardHistorySize, in: 5...200, step: 5)
                Toggle("Skip items marked concealed or transient", isOn: $settings.clipboardIgnoreConcealed)
                HStack {
                    Text("\(clipboard.entries.count) items in memory")
                    Spacer()
                    Button("Clear History", role: .destructive) { clipboard.clear() }.disabled(clipboard.entries.isEmpty)
                }
            } header: {
                Text("Clipboard History")
            } footer: {
                Text("History is kept in memory only and is cleared when Stitchy quits. Stitchy checks the clipboard's change counter twice a second while this is on and reads contents only when it changes. macOS may ask once whether Stitchy can read pasted content.")
            }
            Section {
                ForEach(settings.clipboardExcludedApps, id: \.self) { id in
                    HStack {
                        appLabel(id)
                        Spacer()
                        Button { settings.clipboardExcludedApps.removeAll { $0 == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add App…") { pickApp() }
            } header: {
                Text("Never Record Copies From")
            }
            Section("File Shelf") {
                Toggle("Show file previews", isOn: $settings.shelfPreviews)
                Toggle("Put new screenshots on the Shelf", isOn: $settings.screenshotsToShelf)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tracked folder")
                        Text(settings.trackedFolder.isEmpty ? "New files in a folder you pick land on the Shelf." : settings.trackedFolder)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if !settings.trackedFolder.isEmpty { Button("Stop") { settings.trackedFolder = "" } }
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { settings.trackedFolder = url.path }
                    }
                }
                Text("The shelf only keeps references. Removing items or clearing the shelf never touches files on disk.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func appLabel(_ bundleID: String) -> some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        return HStack(spacing: 8) {
            if let url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18) }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                .foregroundStyle(url == nil ? .secondary : .primary)
        }
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier,
              !settings.clipboardExcludedApps.contains(id) else { return }
        settings.clipboardExcludedApps.append(id)
    }
}

// MARK: - Launcher

struct LauncherSettingsView: View {
    @Environment(Launcher.self) private var launcher
    @State private var showingShortcuts = false

    var body: some View {
        Form {
            Section {
                if launcher.items.isEmpty {
                    Text("No items yet. Installed apps and Stitchy actions are always searchable.").foregroundStyle(.secondary)
                }
                ForEach(launcher.items) { item in
                    HStack(spacing: 8) {
                        if item.kind == .shortcut {
                            Image(systemName: "square.2.layers.3d.fill").foregroundStyle(.pink).frame(width: 18)
                        } else {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.target)).resizable().frame(width: 18, height: 18)
                        }
                        Text(item.name)
                        Text(item.kind == .shortcut ? "Shortcut" : item.kind == .folder ? "Folder" : "App").foregroundStyle(.secondary).font(.caption)
                        Spacer()
                        Button { launcher.remove(item) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Launcher Items")
            } footer: {
                Text("Only Shortcuts you add here can be run from Stitchy. They run with Apple's shortcuts tool.")
            }
            Section {
                HStack {
                    Button("Add App…") { pick(apps: true) }
                    Button("Add Folder…") { pick(apps: false) }
                    Button("Add Shortcut…") {
                        showingShortcuts = true
                        Task { await launcher.loadShortcuts() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingShortcuts) { ShortcutPicker() }
    }

    private func pick(apps: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !apps
        panel.canChooseFiles = apps
        if apps { panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications") }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        launcher.add(.init(kind: apps ? .app : .folder, name: FileManager.default.displayName(atPath: url.path), target: url.path))
    }
}

private struct ShortcutPicker: View {
    @Environment(Launcher.self) private var launcher
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Approve a Shortcut").font(.headline)
            if let list = launcher.availableShortcuts {
                if list.isEmpty { Text("No Shortcuts found.").foregroundStyle(.secondary) }
                List(list, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Add") { launcher.add(.init(kind: .shortcut, name: name, target: name)) }
                            .disabled(launcher.items.contains { $0.kind == .shortcut && $0.target == name })
                    }
                }
            } else {
                ProgressView("Loading Shortcuts…")
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding()
        .frame(width: 380, height: 360)
    }
}

// MARK: - Privacy

/// Live permission states for the overview. Each check is a silent status read; none prompts.
@MainActor
enum PermissionStatus {
    static var accessibility: (String, Color) { AXIsProcessTrusted() ? ("Allowed", .green) : ("Not allowed", .secondary) }
    static var screenRecording: (String, Color) { CGPreflightScreenCaptureAccess() ? ("Allowed", .green) : ("Not allowed", .secondary) }
    static func av(_ type: AVMediaType) -> (String, Color) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: ("Allowed", .green)
        case .denied, .restricted: ("Denied", .red)
        default: ("Not requested", .secondary)
        }
    }
    static var camera: (String, Color) { av(.video) }
    static var microphone: (String, Color) { av(.audio) }
    static var speech: (String, Color) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: ("Allowed", .green)
        case .denied, .restricted: ("Denied", .red)
        default: ("Not requested", .secondary)
        }
    }
    static var bluetooth: (String, Color) {
        switch CBManager.authorization {
        case .allowedAlways: ("Allowed", .green)
        case .denied, .restricted: ("Denied", .red)
        default: ("Not requested", .secondary)
        }
    }
}

struct PrivacySettingsView: View {
    /// Bumped when Stitchy becomes active again, so statuses changed in System Settings show up.
    @State private var refresh = 0
    @Environment(NowPlayingService.self) private var music
    @Environment(SystemNotifier.self) private var notifier
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(CalendarService.self) private var calendar
    @Environment(AppSettings.self) private var settings
    @Environment(PrivateLock.self) private var lock
    @Environment(SensitiveGate.self) private var gate

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Lock Notes and Clipboard", isOn: Binding(
                    get: { settings.privateSectionsLocked },
                    set: { on in Task { await lock.setLocking(on) } }))
                if settings.privateSectionsLocked {
                    Button("Lock Now") { lock.lock() }
                }
                Toggle("Require Authentication for Sensitive Actions", isOn: Binding(
                    get: { settings.requireAuthForSensitive },
                    set: { on in Task { await gate.setRequireSensitive(on) } }))
                LabeledContent("macOS authentication", value: SystemAuth.biometryDescription)
                if let error = gate.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                }
            } header: {
                Text("Touch ID")
            } footer: {
                Text("Private sections unlock with Touch ID or your password for 5 minutes. With sensitive-action protection on, turning the lock off or resetting settings asks first. The island animates while macOS waits for your finger. Stitchy never sees or types your password.")
            }
            Section {
                row("Notifications", "Timer, focus and reminder alerts", notificationStatus) {
                    if notifier.status == .notDetermined { Task { await notifier.requestAuthorization() } } else { SystemSettingsLink.open(SystemSettingsLink.notifications) }
                }
                row("Automation", "Music & Spotify artwork, progress and controls", automationStatus) {
                    if music.permission == .denied || music.permission == .granted { SystemSettingsLink.open(SystemSettingsLink.automation) } else { Task { await music.enableControls() } }
                }
                row("Calendars", "Today's schedule and reminders", calendarStatus) {
                    if calendar.access == .unknown { Task { await calendar.requestAccess() } } else { SystemSettingsLink.open(SystemSettingsLink.calendars) }
                }
                let _ = refresh
                row("Accessibility", "Calls & Messages, Dock previews, window snapping", PermissionStatus.accessibility) {
                    SystemSettingsLink.open(SystemSettingsLink.accessibility)
                }
                row("Screen Recording", "Screen text capture, annotation, Dock previews", PermissionStatus.screenRecording) {
                    SystemSettingsLink.open(SystemSettingsLink.screenRecording)
                }
                row("Camera", "Camera Mirror, only while it's open", PermissionStatus.camera) {
                    SystemSettingsLink.open(SystemSettingsLink.camera)
                }
                row("Microphone", "Dictation, only while you dictate", PermissionStatus.microphone) {
                    SystemSettingsLink.open(SystemSettingsLink.microphone)
                }
                row("Speech Recognition", "Dictation", PermissionStatus.speech) {
                    SystemSettingsLink.open(SystemSettingsLink.speech)
                }
                row("Bluetooth", "Connected-device alerts", PermissionStatus.bluetooth) {
                    SystemSettingsLink.open(SystemSettingsLink.bluetooth)
                }
                row("System Audio", "App Volume (asked the first time you lower an app)", ("Asked when used", .secondary)) {
                    SystemSettingsLink.open(SystemSettingsLink.screenRecording)
                }
                row("Downloads Folder", "Download progress", downloadsStatus) {
                    if settings.downloadsEnabled { SystemSettingsLink.open(SystemSettingsLink.filesAndFolders) } else { settings.downloadsEnabled = true }
                }
                row("Pasted Content", "Clipboard history (macOS may ask)", (settings.clipboardEnabled ? "On" : "Off", .secondary)) {
                    SystemSettingsLink.open(SystemSettingsLink.pasteboard)
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Each permission is requested only when you first use the feature that needs it.")
            }
            Section("Network Services") {
                LabeledContent("Lyrics (LRCLIB)", value: settings.lyricsEnabled ? "On: title, artist, album, length" : "Off")
                LabeledContent("Weather (Open-Meteo)", value: settings.weatherEnabled ? "On: rounded coordinates of your place" : "Off")
                Text("Nothing else leaves your Mac. No accounts, no analytics.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Not Required") {
                Text("Stitchy asks for Accessibility only for Calls & Messages or Dock Window Previews, Screen Recording only for Dock Window Previews, and audio capture only when you lower an app's volume. It never asks for Input Monitoring, Location or Full Disk Access. It can't read other apps' notifications or know which app uses the camera, because macOS doesn't allow that. Incoming phone and FaceTime calls aren't shown: macOS has no public API for observing them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            notifier.refreshStatus()
            await music.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh += 1 }
    }

    private var notificationStatus: (String, Color) {
        switch notifier.status {
        case .authorized, .provisional: ("Allowed", .green)
        case .denied: ("Denied", .red)
        default: ("Not requested", .secondary)
        }
    }

    private var automationStatus: (String, Color) {
        switch music.permission {
        case .granted: ("Allowed", .green)
        case .denied: ("Denied", .red)
        case .appNotRunning: (settings.musicControlsEnabled ? "Open Music or Spotify to check" : "Not requested", .secondary)
        case .notDetermined: ("Not requested", .secondary)
        }
    }

    private var calendarStatus: (String, Color) {
        switch calendar.access {
        case .granted: ("Allowed", .green)
        case .denied: ("Denied", .red)
        case .unknown: ("Not requested", .secondary)
        }
    }

    private var downloadsStatus: (String, Color) {
        if !settings.downloadsEnabled { return ("Off", .secondary) }
        return downloads.accessDenied ? ("Denied", .red) : ("Allowed", .green)
    }

    private func row(_ title: String, _ detail: String, _ status: (String, Color), action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status.0).foregroundStyle(status.1).font(.callout)
            Button("Manage…", action: action)
        }
    }
}

struct WeatherFocusSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FocusService.self) private var focus
    @Environment(Launcher.self) private var launcher

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Weather", isOn: $settings.weatherEnabled)
            Toggle("Use °F and mph", isOn: $settings.weatherFahrenheit)
            Toggle("Alert when rain is likely in the next hour", isOn: $settings.weatherAlerts)
            Toggle("Show temperature in the idle island", isOn: $settings.compactWeather)
        } header: {
            Text("Weather")
        } footer: {
            Text("Forecasts from Open-Meteo (free, no account). Choose your place in the Weather tab: your location once, or a city. Open-Meteo has no severe-weather alerts.")
        }
        Section {
            HStack {
                Text("Focus status")
                Spacer()
                switch focus.access {
                case .authorized: Text(focus.isFocused == true ? "A Focus is on" : "No Focus").foregroundStyle(.secondary)
                case .denied: Button("Open Privacy Settings") { SystemSettingsLink.open(SystemSettingsLink.focus) }
                case .unavailable: Text("Not available").foregroundStyle(.secondary)
                case .unknown: Button("Allow…") { Task { await focus.requestAccess() } }
                }
            }
            shortcutPicker("Turn Focus on with", $settings.focusOnShortcut)
            shortcutPicker("Turn Focus off with", $settings.focusOffShortcut)
            if let error = focus.lastError { Text(error).foregroundStyle(.orange).font(.caption) }
        } header: {
            Text("Focus")
        } footer: {
            Text("macOS lets apps see only whether a Focus is on, not which one, and has no public way for apps to change it. Make two Shortcuts with the \u{201C}Set Focus\u{201D} action (e.g. Do Not Disturb on/off) and pick them here; the Home toggle runs them.")
        }
        .task { if launcher.availableShortcuts == nil { await launcher.loadShortcuts() } }
    }

    private func shortcutPicker(_ title: String, _ value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            Text("None").tag("")
            ForEach(launcher.availableShortcuts ?? [], id: \.self) { Text($0).tag($0) }
        }
    }
}

struct CommunicationSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NotificationMirror.self) private var mirror
    @State private var confirm = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Calls & Messages", isOn: Binding(
                get: { settings.mirrorEnabled },
                set: { on in if on { confirm = true } else { settings.mirrorEnabled = false } }))
            if settings.mirrorEnabled {
                HStack {
                    Label(mirror.trusted ? "Accessibility allowed" : "Accessibility not allowed yet",
                          systemImage: mirror.trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(mirror.trusted ? .green : .orange)
                    Spacer()
                    if !mirror.trusted {
                        Button("Allow…") { mirror.requestAccess() }
                        Button("Check Again") { mirror.refreshTrust(); if mirror.trusted { mirror.start() } }
                    }
                }
                Toggle("Hide message previews (sender only)", isOn: $settings.mirrorHidePreviews)
                Toggle("Include notifications from other apps", isOn: $settings.mirrorOtherApps)
            }
        } header: {
            Text("Calls & Messages")
        } footer: {
            Text("macOS has no public API for other apps' calls or messages. When on, Stitchy uses Accessibility to read only the notification banners macOS already shows you (Messages, FaceTime, Phone), and shows them in the island. Nothing is saved or uploaded; the last few stay in memory. Accept/Decline appear only when the banner has those buttons. Replying isn't supported.")
        }
        .alert("Allow Calls & Messages?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                settings.mirrorEnabled = true
                mirror.requestAccess()
            }
        } message: {
            Text("Stitchy will ask for Accessibility access. It uses it only to read the text of notification banners from Messages, FaceTime and Phone (or other apps if you allow). It doesn't read other windows, record keystrokes, or keep message history.")
        }
    }
}

struct SpotifySettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(QueueService.self) private var queue
    @State private var connecting = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            TextField("Spotify Client ID", text: $settings.spotifyClientID)
                .textFieldStyle(.roundedBorder)
                .disabled(queue.spotifyConnected)
            LabeledContent("Redirect URI to register") {
                Text(SpotifyAuth.redirectURI).textSelection(.enabled).font(.callout.monospaced())
            }
            HStack {
                if queue.spotifyConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect") { queue.disconnectSpotify() }
                } else {
                    Button(connecting ? "Waiting for browser…" : "Connect Spotify…") {
                        connecting = true
                        Task { await queue.connectSpotify(); connecting = false }
                    }
                    .disabled(settings.spotifyClientID.isEmpty || connecting)
                    Spacer()
                    Link("Spotify Developer Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                }
            }
            if let error = queue.signInError { Text(error).foregroundStyle(.orange).font(.caption) }
        } header: {
            Text("Spotify Up Next")
        } footer: {
            Text("The Spotify app doesn't share its queue with other apps; Spotify's Web API does. Create a free app in the Spotify Developer Dashboard, add the redirect URI above, select \u{201C}Web API\u{201D}, and paste its Client ID here. Stitchy signs in with PKCE (no secret), asks only to read playback state, and keeps the sign-in token in your Keychain.")
        }
    }
}
