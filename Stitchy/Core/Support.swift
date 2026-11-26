// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import ServiceManagement
import os

/// Lightweight state-transition log: `log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info`
let islandLog = Logger(subsystem: "app.stitchy.Stitchy", category: "island")

/// Re-runs `body` whenever an @Observable property it reads changes.
/// Used by AppKit controllers that need to react to SwiftUI-side state.
@MainActor
func observeContinuously(_ body: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in observeContinuously(body) }
    }
}

enum ScreenLocator {
    /// The display Stitchy lives on. The MacBook's built-in panel by default,
    /// falling back to the primary display when the lid is closed.
    @MainActor
    static func screen(for choice: DisplayChoice) -> NSScreen? {
        let screens = NSScreen.screens
        switch choice {
        case .builtIn: return screens.first(where: \.isBuiltIn) ?? screens.first
        case .primary: return screens.first
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var isBuiltIn: Bool {
        guard let id = displayID else { return false }
        return CGDisplayIsBuiltin(id) != 0
    }
}

enum Haptics {
    @MainActor
    static func tap(_ enabled: Bool) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

enum LaunchAtLogin {
    @MainActor static var status: SMAppService.Status { SMAppService.mainApp.status }

    @MainActor
    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum SystemSettingsLink {
    static let automation = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    static let filesAndFolders = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
    static let notifications = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
    static let focus = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FocusStatus")!
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let calendars = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
    static let camera = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
    static let pasteboard = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!
    static let screenRecording = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    static let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let speech = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    static let bluetooth = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
    static let loginItems = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!

    @MainActor
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

extension TimeInterval {
    /// Elapsed-style clock ("0:07"), rounding down.
    var clockStringFloor: String {
        let total = Int(self)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "4:05" or "1:02:03".
    var clockString: String {
        let total = Int(self.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension NSImage {
    /// Average colour of the image, nudged to stay readable on black.
    /// Used to tint the music visualizer and progress bar.
    func averageColor() -> NSColor? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255, alpha: 1
        )
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(sat * 1.1, 0.85), brightness: max(bri, 0.75), alpha: 1)
    }
}

import SwiftUI

extension View {
    /// Injects every observable service a Stitchy view may read.
    @MainActor
    func stitchyEnvironment(_ s: AppServices) -> some View {
        self
            .environment(s)
            .environment(s.island).environment(s.settings).environment(s.feed)
            .environment(s.battery).environment(s.network).environment(s.nowPlaying)
            .environment(s.timers).environment(s.shelf).environment(s.downloads)
            .environment(s.notifier).environment(s.clipboard).environment(s.audio)
            .environment(s.privacy).environment(s.notes).environment(s.calendar)
            .environment(s.aiUsage).environment(s.launcher)
            .environment(s.privateLock).environment(s.gate).environment(s.appleNotes)
            .environment(s.bluetooth).environment(s.drives).environment(s.controls).environment(s.lyrics)
            .environment(s.weather).environment(s.focus).environment(s.mirror).environment(s.queue).environment(s.mixer).environment(s.capture).environment(s.agents).environment(s.dictation)
            .environment(s.extensions).environment(s.extensionData)
    }
}

/// Thread-safe one-shot flag.
final class OSAllocatedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    /// Returns true the first time only.
    func set() -> Bool { lock.withLock { defer { value = true }; return !value } }
}
