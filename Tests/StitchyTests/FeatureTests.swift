// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Stitchy

@MainActor
struct StopwatchTests {
    final class Clock { var now = Date(timeIntervalSince1970: 0) }

    @Test func accumulatesAcrossPauses() {
        let clock = Clock()
        let sw = Stopwatch(now: { clock.now })
        sw.start(); clock.now += 10; sw.pause()
        clock.now += 100
        sw.start(); clock.now += 5
        #expect(sw.elapsed() == 15)
        sw.lap()
        #expect(sw.laps == [15])
        sw.reset()
        #expect(!sw.isActive)
    }
}

@MainActor
struct PomodoroTests {
    @Test func cyclesFocusAndBreaks() {
        let p = Pomodoro(settings: nil, notifier: nil)
        #expect(p.phase == .focus)
        for _ in 0..<3 {
            p.advance()                     // focus done
            #expect(p.phase == .shortBreak)
            p.advance()                     // break done
            #expect(p.phase == .focus)
        }
        p.advance()                          // 4th focus -> long break
        #expect(p.phase == .longBreak)
        #expect(p.todayFocusCount == 4)
        #expect(p.timer.total == 15 * 60)
    }
}

@MainActor
struct TimerStoreTests {
    @Test func multipleCountdownsSortedByUrgency() {
        let store = TimerStore(settings: nil, notifier: nil)
        let long = store.addCountdown(seconds: 600, label: "Long")
        let short = store.addCountdown(seconds: 120, label: "Short")
        #expect(store.activeCountdowns.map(\.label) == ["Short", "Long"])
        long.finish()
        #expect(store.activeCountdowns.first?.label == "Long")   // finished first
        store.remove(short)
        #expect(store.countdowns.count == 1)
        store.stopAll()
    }
}

@MainActor
struct ClipboardTests {
    @Test func dedupesAndCapsHistory() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "stitchy.tests.\(UUID())")!)
        settings.clipboardHistorySize = 3
        let history = ClipboardHistory(settings: settings)
        for text in ["a", "b", "c", "a", "d"] { history.record(.init(content: .text(text), sourceApp: nil)) }
        #expect(history.entries.map(\.preview) == ["d", "a", "c"])
    }
}

@MainActor
struct NotesTests {
    @Test func persistsAndSearches() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = NotesStore(directory: dir)
        let note = store.create("Shopping\nmilk")
        store.update(note.id, text: "Shopping\nmilk, eggs")
        store.saveNow()
        let reloaded = NotesStore(directory: dir)
        #expect(reloaded.notes.first?.text == "Shopping\nmilk, eggs")
        #expect(reloaded.notes.first?.title == "Shopping")
        #expect(reloaded.search("eggs").count == 1)
        #expect(reloaded.search("bread").isEmpty)
    }
}

struct UsageScannerTests {
    @Test func dedupesClaudeMessagesAndReadsIncrementally() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let project = home.appendingPathComponent(".claude/projects/demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = iso.string(from: Date())
        func line(_ id: String, _ input: Int, _ output: Int) -> String {
            #"{"type":"assistant","timestamp":"\#(now)","requestId":"r-\#(id)","message":{"id":"m-\#(id)","model":"claude-test","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":50}}}"#
        }
        let file = project.appendingPathComponent("s.jsonl")
        // Same message logged twice (streaming chunks) must count once.
        try (line("1", 10, 20) + "\n" + line("1", 10, 20) + "\n" + #"{"type":"user"}"# + "\n").write(to: file, atomically: true, encoding: .utf8)
        let scanner = UsageScanner(home: home)
        var result = scanner.scan()
        #expect(result.claude?.todayTokens == 30)
        #expect(result.claude?.todayMessages == 1)
        #expect(result.claude?.todayCacheReads == 50)
        #expect(result.claude?.blockTokens == 30)
        #expect(result.codexFound == false)

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data((line("2", 5, 5) + "\n").utf8))
        try handle.close()
        result = scanner.scan()
        #expect(result.claude?.todayTokens == 40)
        #expect(result.claude?.todayMessages == 2)
    }

    @Test func readsCodexRateLimits() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent(".codex/sessions/2026/11/23")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let json = #"{"timestamp":"2026-11-23T10:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":42.5,"window_minutes":300,"resets_in_seconds":600},"secondary":{"used_percent":10,"window_minutes":10080}}}}"#
        try (json + "\n").write(to: dir.appendingPathComponent("rollout.jsonl"), atomically: true, encoding: .utf8)
        let result = UsageScanner(home: home).scan()
        #expect(result.codexFound)
        #expect(result.codex?.primary?.usedPercent == 42.5)
        #expect(result.codex?.primary?.windowMinutes == 300)
        #expect(result.codex?.secondary?.usedPercent == 10)
    }
}

@MainActor
struct GeometryTests {
    @Test func notchDefaultsToMenuBarHeight() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "stitchy.tests.\(UUID())")!)
        let model = IslandModel(settings: settings)
        model.menuBarHeight = 30
        let g = model.geometry
        #expect(g.compact.height == 30)
        #expect(g.compact.width == 190 + 2 * IslandGeometry.shoulder)
        #expect(g.size(.expanded, tab: .home).width > g.compact.width)
        settings.notchHeight = 36
        #expect(model.geometry.compact.height == 36)
    }

    @Test func settingsResetKeepsUserData() {
        let defaults = UserDefaults(suiteName: "stitchy.tests.\(UUID())")!
        let settings = AppSettings(defaults: defaults)
        settings.notchWidth = 240
        settings.setData(["x"], key: "launcherItems")
        settings.reset()
        #expect(settings.notchWidth == 190)
        #expect(settings.data([String].self, key: "launcherItems") == ["x"])
        #expect(AppSettings(defaults: defaults).notchWidth == 190)
    }
}

/// Opt-in check against the real local logs: STITCHY_REAL_USAGE=1 Scripts/test.sh --filter realLogs
struct RealUsageCheck {
    @Test func realLogs() {
        guard ProcessInfo.processInfo.environment["STITCHY_REAL_USAGE"] == "1" else { return }
        let r = UsageScanner().scan()
        print("REAL claude today tokens=\(r.claude?.todayTokens ?? -1) msgs=\(r.claude?.todayMessages ?? -1) block=\(r.claude?.blockTokens ?? -1) blockStart=\(String(describing: r.claude?.blockStart)) active=\(r.claude?.activeSessions ?? -1)")
    }
}
