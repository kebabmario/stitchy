import Foundation

/// Xcode (and xcodebuild) build results. Each finished build updates
/// `DerivedData/<project>/Logs/Build/LogStoreManifest.plist`; Stitchy watches
/// for that file and reads the newest entry (scheme, duration, errors).
/// Read-only; nothing in DerivedData is changed.
@MainActor
final class XcodeBuildMonitor {
    struct Build: Equatable {
        let scheme: String
        let succeeded: Bool
        let errors: Int
        let warnings: Int
        let duration: TimeInterval
        let finished: Date
    }

    var onBuild: ((Build) -> Void)?
    private var watcher: FileWatcher?
    private var lastReported: Date = .distantPast
    let root: URL

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")) {
        self.root = root
    }

    func start() {
        guard watcher == nil else { return }
        lastReported = Date()   // only builds that finish from now on
        watcher = FileWatcher(paths: [root.path], latency: 1) { [weak self] paths in
            for path in Set(paths) where path.hasSuffix("LogStoreManifest.plist") { self?.manifestChanged(URL(fileURLWithPath: path)) }
        }
    }

    func stop() { watcher = nil }

    private func manifestChanged(_ url: URL) {
        guard let data = try? Data(contentsOf: url), let build = Self.latestBuild(in: data), build.finished > lastReported else { return }
        lastReported = build.finished
        onBuild?(build)
    }

    nonisolated static func latestBuild(in manifest: Data) -> Build? {
        guard let plist = try? PropertyListSerialization.propertyList(from: manifest, format: nil) as? [String: Any],
              let logs = plist["logs"] as? [String: [String: Any]] else { return nil }
        let entries = logs.values.compactMap { log -> Build? in
            guard let stopped = (log["timeStoppedRecording"] as? NSNumber)?.doubleValue else { return nil }
            let started = (log["timeStartedRecording"] as? NSNumber)?.doubleValue ?? stopped
            let observable = log["primaryObservable"] as? [String: Any] ?? [:]
            let errors = (observable["totalNumberOfErrors"] as? NSNumber)?.intValue ?? 0
            let status = observable["highLevelStatus"] as? String ?? (errors > 0 ? "E" : "S")
            let scheme = log["schemeIdentifier-schemeName"] as? String
                ?? (log["title"] as? String)?.replacingOccurrences(of: "Build ", with: "") ?? "Build"
            return Build(scheme: scheme, succeeded: status != "E" && errors == 0, errors: errors,
                         warnings: (observable["totalNumberOfWarnings"] as? NSNumber)?.intValue ?? 0,
                         duration: max(stopped - started, 0), finished: Date(timeIntervalSinceReferenceDate: stopped))
        }
        return entries.max { $0.finished < $1.finished }
    }
}
