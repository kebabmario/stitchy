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
        case .natural: return .spring(response: 0.42, dampingFraction: 0.8)
        case .snappy: return .spring(response: 0.3, dampingFraction: 0.85)
        case .gentle: return .spring(response: 0.58, dampingFraction: 0.84)
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

/// All user preferences, persisted to UserDefaults on every change.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let islandVisible = "islandVisible"
        static let hoverToExpand = "hoverToExpand"
        static let hoverDelay = "hoverDelay"
        static let collapseOnExit = "collapseOnExit"
        static let clickToExpand = "clickToExpand"
        static let haptics = "haptics"
        static let animationStyle = "animationStyle"
        static let animatedVisualizer = "animatedVisualizer"
        static let topGap = "topGap"
        static let horizontalOffset = "horizontalOffset"
        static let display = "display"
        static let musicEnabled = "musicEnabled"
        static let timerEnabled = "timerEnabled"
        static let shelfEnabled = "shelfEnabled"
        static let downloadsEnabled = "downloadsEnabled"
        static let batteryEnabled = "batteryEnabled"
        static let alertsEnabled = "alertsEnabled"
        static let compactActivities = "compactActivities"
        static let musicControlsEnabled = "musicControlsEnabled"
        static let timerDuration = "timerDuration"
        static let all = [
            islandVisible, hoverToExpand, hoverDelay, collapseOnExit, clickToExpand, haptics,
            animationStyle, animatedVisualizer, topGap, horizontalOffset, display, musicEnabled,
            timerEnabled, shelfEnabled, downloadsEnabled, batteryEnabled, alertsEnabled,
            compactActivities, musicControlsEnabled, timerDuration,
        ]
    }

    @ObservationIgnored private let defaults: UserDefaults

    var islandVisible: Bool { didSet { defaults.set(islandVisible, forKey: Key.islandVisible) } }
    var hoverToExpand: Bool { didSet { defaults.set(hoverToExpand, forKey: Key.hoverToExpand) } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    var collapseOnExit: Bool { didSet { defaults.set(collapseOnExit, forKey: Key.collapseOnExit) } }
    var clickToExpand: Bool { didSet { defaults.set(clickToExpand, forKey: Key.clickToExpand) } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Key.haptics) } }
    var animationStyle: AnimationStyle { didSet { defaults.set(animationStyle.rawValue, forKey: Key.animationStyle) } }
    var animatedVisualizer: Bool { didSet { defaults.set(animatedVisualizer, forKey: Key.animatedVisualizer) } }
    /// Gap between the top edge of the display and the island, in points.
    var topGap: Double { didSet { defaults.set(topGap, forKey: Key.topGap) } }
    var horizontalOffset: Double { didSet { defaults.set(horizontalOffset, forKey: Key.horizontalOffset) } }
    var display: DisplayChoice { didSet { defaults.set(display.rawValue, forKey: Key.display) } }
    var musicEnabled: Bool { didSet { defaults.set(musicEnabled, forKey: Key.musicEnabled) } }
    var timerEnabled: Bool { didSet { defaults.set(timerEnabled, forKey: Key.timerEnabled) } }
    var shelfEnabled: Bool { didSet { defaults.set(shelfEnabled, forKey: Key.shelfEnabled) } }
    /// Off by default: watching ~/Downloads triggers a macOS privacy prompt.
    var downloadsEnabled: Bool { didSet { defaults.set(downloadsEnabled, forKey: Key.downloadsEnabled) } }
    var batteryEnabled: Bool { didSet { defaults.set(batteryEnabled, forKey: Key.batteryEnabled) } }
    var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) } }
    var compactActivities: Bool { didSet { defaults.set(compactActivities, forKey: Key.compactActivities) } }
    /// Opt-in: Apple Events (Automation permission) for artwork, position and controls.
    var musicControlsEnabled: Bool { didSet { defaults.set(musicControlsEnabled, forKey: Key.musicControlsEnabled) } }
    var timerDuration: Double { didSet { defaults.set(timerDuration, forKey: Key.timerDuration) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: key) as? Double ?? fallback }
        islandVisible = bool(Key.islandVisible, true)
        hoverToExpand = bool(Key.hoverToExpand, true)
        hoverDelay = double(Key.hoverDelay, 0.18)
        collapseOnExit = bool(Key.collapseOnExit, true)
        clickToExpand = bool(Key.clickToExpand, true)
        haptics = bool(Key.haptics, true)
        animationStyle = AnimationStyle(rawValue: defaults.string(forKey: Key.animationStyle) ?? "") ?? .natural
        animatedVisualizer = bool(Key.animatedVisualizer, true)
        topGap = double(Key.topGap, 3)
        horizontalOffset = double(Key.horizontalOffset, 0)
        display = DisplayChoice(rawValue: defaults.string(forKey: Key.display) ?? "") ?? .builtIn
        musicEnabled = bool(Key.musicEnabled, true)
        timerEnabled = bool(Key.timerEnabled, true)
        shelfEnabled = bool(Key.shelfEnabled, true)
        downloadsEnabled = bool(Key.downloadsEnabled, false)
        batteryEnabled = bool(Key.batteryEnabled, true)
        alertsEnabled = bool(Key.alertsEnabled, true)
        compactActivities = bool(Key.compactActivities, true)
        musicControlsEnabled = bool(Key.musicControlsEnabled, false)
        timerDuration = double(Key.timerDuration, 5 * 60)
    }

    /// Restores every preference to its default value.
    func reset() {
        let fresh = AppSettings(defaults: UserDefaults(suiteName: "app.stitchy.defaults-template") ?? .standard)
        for key in Key.all { defaults.removeObject(forKey: key) }
        islandVisible = fresh.islandVisible
        hoverToExpand = fresh.hoverToExpand
        hoverDelay = fresh.hoverDelay
        collapseOnExit = fresh.collapseOnExit
        clickToExpand = fresh.clickToExpand
        haptics = fresh.haptics
        animationStyle = fresh.animationStyle
        animatedVisualizer = fresh.animatedVisualizer
        topGap = fresh.topGap
        horizontalOffset = fresh.horizontalOffset
        display = fresh.display
        musicEnabled = fresh.musicEnabled
        timerEnabled = fresh.timerEnabled
        shelfEnabled = fresh.shelfEnabled
        downloadsEnabled = fresh.downloadsEnabled
        batteryEnabled = fresh.batteryEnabled
        alertsEnabled = fresh.alertsEnabled
        compactActivities = fresh.compactActivities
        musicControlsEnabled = fresh.musicControlsEnabled
        timerDuration = fresh.timerDuration
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var expandAnimation: Animation { animationStyle.expand(reduceMotion: reduceMotion) }
    var collapseAnimation: Animation { animationStyle.collapse(reduceMotion: reduceMotion) }
}
