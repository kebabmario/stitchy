import ServiceManagement
import SwiftUI
import UserNotifications

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
            Text("Your shelf, timer and files are not affected.")
        }
    }
}

struct IslandSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Interaction") {
                Toggle("Expand on hover", isOn: $settings.hoverToExpand)
                LabeledContent("Hover delay") {
                    HStack {
                        Slider(value: $settings.hoverDelay, in: 0...0.8, step: 0.05).frame(width: 180)
                        Text("\(Int(settings.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!settings.hoverToExpand)
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
                Text("Reduce Motion in Accessibility settings always uses short, simple transitions.")
            }
            Section("Position") {
                LabeledContent("Distance from top") {
                    HStack {
                        Slider(value: $settings.topGap, in: 0...40, step: 1).frame(width: 180)
                        Text("\(Int(settings.topGap)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                LabeledContent("Horizontal offset") {
                    HStack {
                        Slider(value: $settings.horizontalOffset, in: -300...300, step: 1).frame(width: 180)
                        Text("\(Int(settings.horizontalOffset)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Center") { settings.horizontalOffset = 0; settings.topGap = 3 }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FeaturesSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                feature("Music", "music.note", .pink, "Apple Music and Spotify.", $settings.musicEnabled)
                feature("Timer", "timer", .orange, "Countdown with completion alert.", $settings.timerEnabled)
                feature("File Shelf", "tray.full.fill", .teal, "Drag files onto the island to hold them.", $settings.shelfEnabled)
                feature("Downloads", "arrow.down.circle.fill", .blue, "Watches ~/Downloads. macOS asks for folder access.", $settings.downloadsEnabled)
                feature("Battery", "battery.100percent", .green, "Charge level, charging and power source.", $settings.batteryEnabled)
                feature("Live Alerts & Activity Feed", "bell.fill", .red, "Charging, timer and download alerts in the island.", $settings.alertsEnabled)
            } header: {
                Text("Features")
            }
            Section {
                Toggle("Show live activities in the compact island", isOn: $settings.compactActivities)
            } footer: {
                Text("Timers, downloads and music appear on either side of the resting island.")
            }
        }
        .formStyle(.grouped)
    }

    private func feature(_ title: String, _ symbol: String, _ tint: Color, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(.white)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PermissionsSettingsView: View {
    @Environment(NowPlayingService.self) private var music
    @Environment(SystemNotifier.self) private var notifier
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                row("Notifications", "Timer completion alerts", notificationStatus) {
                    if notifier.status == .notDetermined {
                        Task { await notifier.requestAuthorization() }
                    } else {
                        SystemSettingsLink.open(SystemSettingsLink.notifications)
                    }
                }
                row("Automation", "Music & Spotify artwork, progress and controls", automationStatus) {
                    if music.permission == .denied || music.permission == .granted {
                        SystemSettingsLink.open(SystemSettingsLink.automation)
                    } else {
                        Task { await music.enableControls() }
                    }
                }
                row("Downloads Folder", "Download progress", downloadsStatus) {
                    if settings.downloadsEnabled {
                        SystemSettingsLink.open(SystemSettingsLink.filesAndFolders)
                    } else {
                        settings.downloadsEnabled = true
                    }
                }
            } header: {
                Text("Optional Access")
            } footer: {
                Text("Each permission is requested only when you first use the feature that needs it.")
            }
            Section("Not Required") {
                Text("Stitchy never asks for Accessibility, Input Monitoring, Screen Recording, Location or Full Disk Access. It cannot read other apps' notifications; macOS does not allow it.")
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
