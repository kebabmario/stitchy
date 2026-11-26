// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// "Tracked folder": files that appear in a folder you pick land on the
/// shelf. FSEvents on that one folder; only top-level, non-hidden items that
/// weren't there when tracking started (or last checked) count.
@MainActor
final class FolderTracker {
    var onNewFiles: (([URL]) -> Void)?
    private var watcher: FileWatcher?
    private var known: Set<String> = []
    private(set) var folder: URL?

    func start(_ folder: URL) {
        guard folder != self.folder || watcher == nil else { return }
        stop()
        self.folder = folder
        known = Set(Self.entries(in: folder))
        watcher = FileWatcher(paths: [folder.path], latency: 1) { [weak self] _ in self?.scan() }
    }

    func stop() {
        watcher = nil
        folder = nil
        known = []
    }

    private func scan() {
        guard let folder else { return }
        let now = Self.entries(in: folder)
        let added = Self.newEntries(now, known: known)
        known = Set(now)
        if !added.isEmpty { onNewFiles?(added.map { folder.appendingPathComponent($0) }) }
    }

    /// Names in `now` not seen before, skipping partial downloads.
    nonisolated static func newEntries(_ now: [String], known: Set<String>) -> [String] {
        now.filter { !known.contains($0) && !$0.hasSuffix(".download") && !$0.hasSuffix(".crdownload") && !$0.hasSuffix(".part") }.sorted()
    }

    nonisolated static func entries(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }
    }
}
