// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// Puts new screenshots on the shelf (Droppy-style). A live Spotlight query
/// on `kMDItemIsScreenCapture` sees them wherever macOS saves them, with no
/// polling and no folder watch. Only screenshots taken after `start()` count.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?
    private var query: NSMetadataQuery?
    private var seen: Set<String> = []

    func start() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemContentCreationDate > %@", Date() as NSDate)
        q.searchScopes = [NSMetadataQueryLocalComputerScope]
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidUpdate, object: q)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .NSMetadataQueryDidFinishGathering, object: q)
        q.start()
        query = q
    }

    func stop() {
        guard let query else { return }
        query.stop()
        NotificationCenter.default.removeObserver(self, name: nil, object: query)
        self.query = nil
    }

    @objc private func changed() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let paths = (0..<query.resultCount).compactMap { (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String }
        for path in Self.newPaths(paths, seen: &seen) { onScreenshot?(URL(fileURLWithPath: path)) }
    }

    /// Paths not reported before, skipping macOS's temporary ".Screenshot" files.
    nonisolated static func newPaths(_ paths: [String], seen: inout Set<String>) -> [String] {
        paths.filter { path in
            guard !(path as NSString).lastPathComponent.hasPrefix("."), !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
    }
}
