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
            Button("Reset", role: .destructive) { settings.reset() }
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
            Section("Features") {
                feature("Music", "music.note", .pink, "Apple Music and Spotify.", $settings.musicEnabled)
                feature("Timers", "timer", .orange, "Countdowns, stopwatch and Focus sessions.", $settings.timerEnabled)
                feature("File Shelf", "tray.full.fill", .teal, "Drag files onto the island to hold them.", $settings.shelfEnabled)
                feature("Quick Notes", "note.text", .yellow, "Notes saved on this Mac.", $settings.notesEnabled)
                feature("Launcher", "magnifyingglass", .indigo, "Search apps, folders, Shortcuts and actions.", $settings.launcherEnabled)
                feature("Calendar", "calendar", .red, "Today's schedule and meeting reminders. Needs calendar access.", Binding(
                    get: { settings.calendarEnabled },
                    set: { on in
                        if on, calendar.access != .granted { Task { await calendar.requestAccess() } } else { settings.calendarEnabled = on }
                    }))
                feature("Downloads", "arrow.down.circle.fill", .blue, "Watches ~/Downloads. macOS asks for folder access.", $settings.downloadsEnabled)
                feature("Battery", "battery.100percent", .green, "Charge level, charging and low-battery alerts.", $settings.batteryEnabled)
                feature("System HUD", "speaker.wave.2.fill", .gray, "Volume, mute and audio output changes.", $settings.hudEnabled)
                feature("Camera Guard", "video.fill", .green, "Shows when the camera or microphone is in use.", $settings.privacyGuardEnabled)
                feature("AI Usage", "sparkle", .orange, "Claude Code and Codex usage from local logs.", $settings.aiUsageEnabled)
                feature("Live Alerts & Activity Feed", "bell.fill", .red, "Short alerts in the island and a history feed.", $settings.alertsEnabled)
            }
            Section {
                Toggle("Show live activities in the compact island", isOn: $settings.compactActivities)
                Toggle("Timers, stopwatch and Focus", isOn: $settings.showTimerActivity).disabled(!settings.compactActivities)
                Toggle("Music", isOn: $settings.showMusicActivity).disabled(!settings.compactActivities)
                Toggle("Downloads and AirDrop", isOn: $settings.showTransferActivity).disabled(!settings.compactActivities)
                Toggle("Camera and microphone", isOn: $settings.showPrivacyActivity).disabled(!settings.compactActivities)
            } header: {
                Text("Activity Visibility")
            } footer: {
                Text("When several are active, the island shows the most important one: camera/mic, then timers, transfers, then music. All of them are listed on Home.")
            }
            Section("Music") {
                Toggle("Show an alert when the track changes", isOn: $settings.trackChangeAlerts)
                Toggle("Artwork, progress and controls (Automation)", isOn: $settings.musicControlsEnabled)
            }
            Section("Focus") {
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

// MARK: - Face ID

struct FaceIDSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(FaceIDService.self) private var faceID
    @State private var confirmDelete = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Enable Stitchy Face ID", isOn: $settings.faceIDEnabled)
            } footer: {
                Text("A camera-based presence check that runs entirely on this Mac. It is not Apple Face ID: a regular webcam has no depth sensing, so a photo or a look-alike can fool it. It never unlocks your Mac, types passwords or protects anything. Private sections use Touch ID or your password instead.")
            }
            if settings.faceIDEnabled {
                Section("1 · Camera Access") {
                    HStack {
                        Label(cameraText, systemImage: faceID.cameraStatus == .authorized ? "checkmark.circle.fill" : "camera")
                            .foregroundStyle(faceID.cameraStatus == .authorized ? .green : .primary)
                        Spacer()
                        if faceID.cameraStatus == .notDetermined {
                            Button("Allow Camera…") { Task { await faceID.requestCamera() } }
                        } else if faceID.cameraStatus == .denied || faceID.cameraStatus == .restricted {
                            Button("Open Privacy Settings") { SystemSettingsLink.open(SystemSettingsLink.camera) }
                        }
                    }
                    Text("The camera only turns on while you enroll or run a check, and the green camera light is always on while it runs. Frames are analysed in memory and discarded; only numeric face descriptors are saved, in your Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("2 · Enroll") {
                    CameraPreview(session: faceID.session, active: faceID.cameraRunning)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) { cameraBadge.padding(8) }
                    HStack {
                        Button(faceID.isEnrolled ? "Re-enroll" : "Enroll My Face") { Task { await faceID.enroll() } }
                            .disabled(faceID.cameraStatus != .authorized || faceID.cameraRunning)
                        Button("Check Now") { Task { await faceID.check() } }
                            .disabled(!faceID.isEnrolled || faceID.cameraRunning)
                        Spacer()
                        Text(phaseText).foregroundStyle(.secondary).font(.callout)
                    }
                    if case .enrolling(let progress) = faceID.phase { ProgressView(value: progress) }
                }
                Section("3 · Manage") {
                    LabeledContent("Enrollment", value: faceID.isEnrolled ? "Saved in Keychain" : "None")
                    Button("Delete Face Data…", role: .destructive) { confirmDelete = true }.disabled(!faceID.isEnrolled)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete Stitchy Face ID data?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { faceID.deleteEnrollment() }
        } message: {
            Text("Removes the saved face descriptors from your Keychain. This can't be undone.")
        }
    }

    private var cameraText: String {
        switch faceID.cameraStatus {
        case .authorized: "Camera allowed"
        case .denied: "Camera access denied"
        case .restricted: "Camera restricted"
        default: "Not requested yet"
        }
    }

    private var cameraBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(faceID.cameraRunning ? .green : .gray).frame(width: 7, height: 7)
            Text(faceID.cameraRunning ? (faceID.faceVisible ? "Camera on · face found" : "Camera on") : "Camera off")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
    }

    private var phaseText: String {
        switch faceID.phase {
        case .idle: ""
        case .enrolling: "Look at the camera…"
        case .checking: "Checking…"
        case .finished(let s), .failed(let s): s
        }
    }
}

/// Live camera preview (AVCaptureVideoPreviewLayer). Shows black when off.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let active: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.sublayers?.first?.frame = view.bounds
        view.layer?.sublayers?.first?.opacity = active ? 1 : 0
    }
}

// MARK: - Privacy

struct PrivacySettingsView: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(SystemNotifier.self) private var notifier
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(CalendarService.self) private var calendar
    @Environment(FaceIDService.self) private var faceID
    @Environment(AppSettings.self) private var settings
    @Environment(PrivateLock.self) private var lock

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Lock Notes and Clipboard behind Touch ID / password", isOn: $settings.privateSectionsLocked)
                if settings.privateSectionsLocked {
                    Button("Lock Now") { lock.lock() }
                }
            } header: {
                Text("Private Sections")
            } footer: {
                Text("Uses LocalAuthentication. Unlocking lasts 5 minutes.")
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
                row("Camera", "Stitchy Face ID only", cameraStatus) {
                    if faceID.cameraStatus == .notDetermined { Task { await faceID.requestCamera() } } else { SystemSettingsLink.open(SystemSettingsLink.camera) }
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
            Section("Not Required") {
                Text("Stitchy never asks for Accessibility, Input Monitoring, Screen Recording, Location or Full Disk Access. It can't read other apps' notifications or know which app uses the camera, because macOS doesn't allow that. Incoming phone and FaceTime calls aren't shown: macOS has no public API for observing them.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            notifier.refreshStatus()
            await music.refreshPermission()
        }
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

    private var cameraStatus: (String, Color) {
        switch faceID.cameraStatus {
        case .authorized: ("Allowed", .green)
        case .denied, .restricted: ("Denied", .red)
        default: ("Not requested", .secondary)
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
