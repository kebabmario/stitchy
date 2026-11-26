// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import Stitchy

@MainActor
struct TimerServiceTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000) }

    @Test func pauseResumeKeepsRemainingTime() {
        let clock = Clock()
        let timer = TimerService(settings: nil, notifier: nil, now: { clock.now })
        timer.setDuration(300)
        timer.start()
        clock.now += 100
        #expect(timer.remaining() == 200)
        timer.pause()
        clock.now += 1_000  // time passes while paused
        #expect(timer.remaining() == 200)
        timer.resume()
        clock.now += 50
        #expect(timer.remaining() == 150)
        #expect(abs(timer.fraction() - 0.5) < 0.0001)
    }

    @Test func finishAndReset() {
        let timer = TimerService(settings: nil, notifier: nil)
        var events = 0
        timer.onEvent = { _ in events += 1 }
        timer.setDuration(60)
        timer.start()
        timer.finish()
        #expect(timer.phase == .finished)
        #expect(events == 1)
        timer.reset()
        #expect(timer.phase == .idle)
        #expect(timer.remaining() == 60)
    }

    @Test func durationIsClamped() {
        let timer = TimerService(settings: nil, notifier: nil)
        timer.setDuration(5)
        #expect(timer.total == 60)
    }
}

struct DownloadNamingTests {
    @Test func finalNames() {
        #expect(DownloadsMonitor.finalName(forPartial: "report.pdf.crdownload") == "report.pdf")
        #expect(DownloadsMonitor.finalName(forPartial: "movie.mp4.download") == "movie.mp4")
        #expect(DownloadsMonitor.finalName(forPartial: "a.zip.part") == "a.zip")
        #expect(DownloadsMonitor.finalName(forPartial: "Unconfirmed 1234.crdownload") == nil)
        #expect(DownloadsMonitor.finalName(forPartial: "notes.txt") == nil)
    }
}

@MainActor
struct FileShelfTests {
    @Test func addSkipsDuplicatesAndMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("hi".utf8).write(to: file)

        let shelf = FileShelf()
        #expect(shelf.add([file, file, dir.appendingPathComponent("missing.txt")]) == 1)
        #expect(shelf.add([file]) == 0)
        shelf.clear()
        #expect(shelf.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))  // clearing never deletes
    }
}

struct FormattingTests {
    @Test func clockString() {
        #expect(TimeInterval(65).clockString == "1:05")
        #expect(TimeInterval(3723).clockString == "1:02:03")
        #expect(TimeInterval(0.2).clockString == "0:01")
    }
}

@MainActor
struct DownloadsMonitorTests {
    @Test func partialFileCompletes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = DownloadsMonitor(folder: dir)
        var events: [String] = []
        monitor.onEvent = { events.append($0.title) }
        monitor.start()
        defer { monitor.stop() }

        let partial = dir.appendingPathComponent("report.pdf.crdownload")
        try Data(count: 1024).write(to: partial)
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.active.first?.name == "report.pdf")
        #expect(monitor.active.first?.fraction == nil)      // no invented progress
        #expect(monitor.active.first?.bytes == 1024)

        try FileManager.default.moveItem(at: partial, to: dir.appendingPathComponent("report.pdf"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.active.isEmpty)
        #expect(events == ["Download Complete"])
    }

    @Test func publishedProgressIsShown() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let monitor = DownloadsMonitor(folder: dir)
        monitor.start()
        defer { monitor.stop() }

        let file = dir.appendingPathComponent("big.iso")
        try Data(count: 10).write(to: file)
        let progress = Progress(totalUnitCount: 100)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = file
        progress.completedUnitCount = 40
        progress.publish()
        defer { progress.unpublish() }
        for _ in 0..<20 where monitor.active.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        let fraction = try #require(monitor.active.first?.fraction)
        #expect(abs(fraction - 0.4) < 0.01)
    }
}
