import Foundation
import Observation
import SwiftUI

enum AnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case natural, snappy, gentle, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .snappy: "Snappy"
        case .gentle: "Gentle"
        case .minimal: "Minimal"
        }
    }

    /// Springs tuned to stay close to critically damped: a hint of life, no wobble.
    func expand(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.18) }
        switch self {
        case .natural: return .spring(response: 0.42, dampingFraction: 0.82)
        case .snappy: return .spring(response: 0.3, dampingFraction: 0.86)
        case .gentle: return .spring(response: 0.58, dampingFraction: 0.85)
        case .minimal: return .easeOut(duration: 0.2)
        }
    }

    func collapse(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.16) }
        switch self {
        case .natural: return .spring(response: 0.36, dampingFraction: 0.9)
        case .snappy: return .spring(response: 0.26, dampingFraction: 0.92)
        case .gentle: return .spring(response: 0.5, dampingFraction: 0.92)
        case .minimal: return .easeIn(duration: 0.16)
        }
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable, Sendable {
    case builtIn, primary

    var id: String { rawValue }
    var title: String { self == .builtIn ? "Built-in Display" : "Primary Display" }
}

/// Global shortcut presets. Registered with Carbon's RegisterEventHotKey,
/// which needs no Accessibility or Input Monitoring permission.
enum HotkeyPreset: String, CaseIterable, Identifiable, Sendable {
    case controlOptionSpace, optionCommandS, controlCommandS

    var id: String { rawValue }

    var title: String {
        switch self {
        case .controlOptionSpace: "⌃⌥Space"
        case .optionCommandS: "⌥⌘S"
        case .controlCommandS: "⌃⌘S"
        }
    }
}

/// All user preferences, persisted to UserDefaults on every change.
/// Keys starting with "data." hold user data (history, launcher items) and
/// survive Reset Settings.
@MainActor @Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    // Island appearance
    var islandVisible = true { didSet { save(islandVisible, "islandVisible") } }
    /// Width of the resting notch, in points.
    var notchWidth = 190.0 { didSet { save(notchWidth, "notchWidth") } }
    /// Height of the resting notch; 0 = match the menu bar.
    var notchHeight = 0.0 { didSet { save(notchHeight, "notchHeight") } }
    var expandedWidth = 460.0 { didSet { save(expandedWidth, "expandedWidth") } }
    /// Gap between the top edge of the display and the island. 0 = attached.
    var topGap = 0.0 { didSet { save(topGap, "topGap") } }
    var horizontalOffset = 0.0 { didSet { save(horizontalOffset, "horizontalOffset") } }
    var display = DisplayChoice.builtIn { didSet { save(display.rawValue, "display") } }
    var hideInFullScreen = true { didSet { save(hideInFullScreen, "hideInFullScreen") } }

    // Behaviour
    var hoverToExpand = true { didSet { save(hoverToExpand, "hoverToExpand") } }
    var hoverDelay = 0.18 { didSet { save(hoverDelay, "hoverDelay") } }
    /// Extra activation slack around the island, in points.
    var hoverMargin = 6.0 { didSet { save(hoverMargin, "hoverMargin") } }
    var collapseOnExit = true { didSet { save(collapseOnExit, "collapseOnExit") } }
    var clickToExpand = true { didSet { save(clickToExpand, "clickToExpand") } }
    var haptics = true { didSet { save(haptics, "haptics") } }
    var animationStyle = AnimationStyle.natural { didSet { save(animationStyle.rawValue, "animationStyle") } }
    var animatedVisualizer = true { didSet { save(animatedVisualizer, "animatedVisualizer") } }

    // Features
    var musicEnabled = true { didSet { save(musicEnabled, "musicEnabled") } }
    var timerEnabled = true { didSet { save(timerEnabled, "timerEnabled") } }
    var shelfEnabled = true { didSet { save(shelfEnabled, "shelfEnabled") } }
    /// Off by default: watching ~/Downloads triggers a macOS privacy prompt.
    var downloadsEnabled = false { didSet { save(downloadsEnabled, "downloadsEnabled") } }
    var batteryEnabled = true { didSet { save(batteryEnabled, "batteryEnabled") } }
    var alertsEnabled = true { didSet { save(alertsEnabled, "alertsEnabled") } }
    /// Off by default: clipboard history is opt-in.
    var clipboardEnabled = false { didSet { save(clipboardEnabled, "clipboardEnabled") } }
    var notesEnabled = true { didSet { save(notesEnabled, "notesEnabled") } }
    /// Off until the user grants calendar access from the Calendar tab.
    var calendarEnabled = false { didSet { save(calendarEnabled, "calendarEnabled") } }
    var launcherEnabled = true { didSet { save(launcherEnabled, "launcherEnabled") } }
    /// Off by default: reads local coding-agent logs only after opt-in.
    var aiUsageEnabled = false { didSet { save(aiUsageEnabled, "aiUsageEnabled") } }
    var hudEnabled = true { didSet { save(hudEnabled, "hudEnabled") } }
    var privacyGuardEnabled = true { didSet { save(privacyGuardEnabled, "privacyGuardEnabled") } }

    // Activity visibility in the compact island
    var compactActivities = true { didSet { save(compactActivities, "compactActivities") } }
    var showTimerActivity = true { didSet { save(showTimerActivity, "showTimerActivity") } }
    var showMusicActivity = true { didSet { save(showMusicActivity, "showMusicActivity") } }
    var showTransferActivity = true { didSet { save(showTransferActivity, "showTransferActivity") } }
    var showPrivacyActivity = true { didSet { save(showPrivacyActivity, "showPrivacyActivity") } }

    // Music
    /// Opt-in: Apple Events (Automation permission) for artwork, position and controls.
    var musicControlsEnabled = false { didSet { save(musicControlsEnabled, "musicControlsEnabled") } }
    var trackChangeAlerts = true { didSet { save(trackChangeAlerts, "trackChangeAlerts") } }

    // Timers & focus
    var timerDuration = 300.0 { didSet { save(timerDuration, "timerDuration") } }
    var focusMinutes = 25.0 { didSet { save(focusMinutes, "focusMinutes") } }
    var shortBreakMinutes = 5.0 { didSet { save(shortBreakMinutes, "shortBreakMinutes") } }
    var longBreakMinutes = 15.0 { didSet { save(longBreakMinutes, "longBreakMinutes") } }
    var sessionsPerLongBreak = 4.0 { didSet { save(sessionsPerLongBreak, "sessionsPerLongBreak") } }

    // Clipboard
    var clipboardHistorySize = 25.0 { didSet { save(clipboardHistorySize, "clipboardHistorySize") } }
    var clipboardIgnoreConcealed = true { didSet { save(clipboardIgnoreConcealed, "clipboardIgnoreConcealed") } }
    var clipboardExcludedApps: [String] = AppSettings.defaultExcludedApps {
        didSet { save(clipboardExcludedApps, "clipboardExcludedApps") }
    }

    // Shelf
    var shelfPreviews = true { didSet { save(shelfPreviews, "shelfPreviews") } }

    // Calendar
    var meetingReminderMinutes = 5.0 { didSet { save(meetingReminderMinutes, "meetingReminderMinutes") } }

    // Shortcuts
    var hotkeyEnabled = true { didSet { save(hotkeyEnabled, "hotkeyEnabled") } }
    var hotkey = HotkeyPreset.controlOptionSpace { didSet { save(hotkey.rawValue, "hotkey") } }

    // Face ID
    var faceIDEnabled = false { didSet { save(faceIDEnabled, "faceIDEnabled") } }
    var privateSectionsLocked = false { didSet { save(privateSectionsLocked, "privateSectionsLocked") } }

    /// Password managers and keychain tools never recorded by clipboard history.
    static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.Passwords", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
    ]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Reads every preference, falling back to its default. The single
    /// source of default values, used at launch and by Reset Settings.
    private func load() {
        func b(_ k: String, _ d: Bool) -> Bool { defaults.object(forKey: k) as? Bool ?? d }
        func n(_ k: String, _ d: Double) -> Double { defaults.object(forKey: k) as? Double ?? d }
        func s(_ k: String) -> String { defaults.string(forKey: k) ?? "" }
        islandVisible = b("islandVisible", true)
        notchWidth = n("notchWidth", 190)
        notchHeight = n("notchHeight", 0)
        expandedWidth = n("expandedWidth", 460)
        topGap = n("topGap", 0)
        horizontalOffset = n("horizontalOffset", 0)
        display = DisplayChoice(rawValue: s("display")) ?? .builtIn
        hideInFullScreen = b("hideInFullScreen", true)
        hoverToExpand = b("hoverToExpand", true)
        hoverDelay = n("hoverDelay", 0.18)
        hoverMargin = n("hoverMargin", 6)
        collapseOnExit = b("collapseOnExit", true)
        clickToExpand = b("clickToExpand", true)
        haptics = b("haptics", true)
        animationStyle = AnimationStyle(rawValue: s("animationStyle")) ?? .natural
        animatedVisualizer = b("animatedVisualizer", true)
        musicEnabled = b("musicEnabled", true)
        timerEnabled = b("timerEnabled", true)
        shelfEnabled = b("shelfEnabled", true)
        downloadsEnabled = b("downloadsEnabled", false)
        batteryEnabled = b("batteryEnabled", true)
        alertsEnabled = b("alertsEnabled", true)
        clipboardEnabled = b("clipboardEnabled", false)
        notesEnabled = b("notesEnabled", true)
        calendarEnabled = b("calendarEnabled", false)
        launcherEnabled = b("launcherEnabled", true)
        aiUsageEnabled = b("aiUsageEnabled", false)
        hudEnabled = b("hudEnabled", true)
        privacyGuardEnabled = b("privacyGuardEnabled", true)
        compactActivities = b("compactActivities", true)
        showTimerActivity = b("showTimerActivity", true)
        showMusicActivity = b("showMusicActivity", true)
        showTransferActivity = b("showTransferActivity", true)
        showPrivacyActivity = b("showPrivacyActivity", true)
        musicControlsEnabled = b("musicControlsEnabled", false)
        trackChangeAlerts = b("trackChangeAlerts", true)
        timerDuration = n("timerDuration", 300)
        focusMinutes = n("focusMinutes", 25)
        shortBreakMinutes = n("shortBreakMinutes", 5)
        longBreakMinutes = n("longBreakMinutes", 15)
        sessionsPerLongBreak = n("sessionsPerLongBreak", 4)
        clipboardHistorySize = n("clipboardHistorySize", 25)
        clipboardIgnoreConcealed = b("clipboardIgnoreConcealed", true)
        clipboardExcludedApps = defaults.stringArray(forKey: "clipboardExcludedApps") ?? Self.defaultExcludedApps
        shelfPreviews = b("shelfPreviews", true)
        meetingReminderMinutes = n("meetingReminderMinutes", 5)
        hotkeyEnabled = b("hotkeyEnabled", true)
        hotkey = HotkeyPreset(rawValue: s("hotkey")) ?? .controlOptionSpace
        faceIDEnabled = b("faceIDEnabled", false)
        privateSectionsLocked = b("privateSectionsLocked", false)
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    /// Restores every preference to its default. User data ("data." keys,
    /// notes, shelf) is kept.
    func reset() {
        for key in defaults.dictionaryRepresentation().keys where !key.hasPrefix("data.") {
            defaults.removeObject(forKey: key)
        }
        load()
    }

    // MARK: Small typed storage for user data

    func data<T: Decodable>(_ type: T.Type, key: String) -> T? {
        defaults.data(forKey: "data." + key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    func setData<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: "data." + key)
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var expandAnimation: Animation { animationStyle.expand(reduceMotion: reduceMotion) }
    var collapseAnimation: Animation { animationStyle.collapse(reduceMotion: reduceMotion) }
}
