import AppKit
import Observation
import SwiftUI

/// Watches ~/Downloads for in-progress downloads.
///
/// Two real data sources, nothing invented:
///  - A kqueue directory watch (DispatchSource) sees partial files appear
///    and disappear: Safari `.download`, Chrome `.crdownload`, Firefox `.part`.
///  - `Progress.addSubscriber(forFileURL:)` receives the file progress that
///    browsers publish for Finder's progress bars, giving a real fraction.
/// When no progress is published, the item is shown as indeterminate with
/// its current size on disk.
@MainActor @Observable
final class DownloadsMonitor {
    struct Download: Identifiable, Equatable {
        enum Status: Equatable { case inProgress, completed(URL), stopped }

        let id: String          // path of the partial file / published progress
        var name: String
        var fraction: Double?
        var bytes: Int64?
        var status: Status = .inProgress
        var finishedAt: Date?

        var isActive: Bool { status == .inProgress }
    }

    private(set) var downloads: [Download] = []
    private(set) var isRunning = false
    private(set) var accessDenied = false
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var source: DispatchSourceFileSystemObject?
    @ObservationIgnored private var progressBridge: ProgressBridge?
    @ObservationIgnored private var sizeTimer: Timer?
    @ObservationIgnored private var publishedPaths: Set<String> = []

    init(folder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.folder = folder
    }

    var active: [Download] { downloads.filter(\.isActive) }

    func start() {
        guard source == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            accessDenied = true
            return
        }
        accessDenied = false
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.rescan() }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        isRunning = true
        progressBridge = ProgressBridge(folder: folder) { [weak self] path, fraction, ended in
            Task { @MainActor in self?.progressChanged(path: path, fraction: fraction, ended: ended) }
        }
        rescan()
    }

    func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        progressBridge = nil
        sizeTimer?.invalidate()
        sizeTimer = nil
        isRunning = false
        downloads.removeAll()
    }

    func clearFinished() {
        downloads.removeAll { !$0.isActive }
    }

    func reveal(_ download: Download) {
        if case .completed(let url) = download.status {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: download.id)])
        }
    }

    // MARK: Partial-file naming (pure, tested)

    nonisolated static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]

    nonisolated static func isPartial(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// "report.pdf.crdownload" -> "report.pdf". Chrome's "Unconfirmed 123.crdownload" has no final name.
    nonisolated static func finalName(forPartial name: String) -> String? {
        guard isPartial(name) else { return nil }
        let base = (name as NSString).deletingPathExtension
        if base.hasPrefix("Unconfirmed ") || base.isEmpty { return nil }
        return base
    }

    // MARK: Scanning

    private func rescan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let partials = Set(names.filter(Self.isPartial).map { folder.appendingPathComponent($0).path })

        // Newly appeared partial files.
        for path in partials where !downloads.contains(where: { $0.id == path }) {
            let name = (path as NSString).lastPathComponent
            downloads.insert(Download(id: path, name: Self.finalName(forPartial: name) ?? name, bytes: size(of: path)), at: 0)
        }
        // Partial files that vanished: completed or cancelled.
        for index in downloads.indices where downloads[index].isActive {
            let item = downloads[index]
            guard Self.isPartial(item.id), !partials.contains(item.id), !publishedPaths.contains(item.id) else { continue }
            let finalURL = folder.appendingPathComponent(item.name)
            complete(at: index, finalURL: FileManager.default.fileExists(atPath: finalURL.path) ? finalURL : nil)
        }
        refreshSizes()
        trimFinished()
    }

    private func progressChanged(path: String, fraction: Double, ended: Bool) {
        if ended {
            publishedPaths.remove(path)
            guard let index = downloads.firstIndex(where: { $0.id == path && $0.isActive }) else { return }
            if Self.isPartial(path) {
                rescan()  // completion decided by the partial file disappearing
            } else {
                let url = URL(fileURLWithPath: path)
                complete(at: index, finalURL: (downloads[index].fraction ?? 0) >= 0.999 && FileManager.default.fileExists(atPath: path) ? url : nil)
            }
            return
        }
        publishedPaths.insert(path)
        if let index = downloads.firstIndex(where: { $0.id == path }) {
            // Avoid re-rendering for sub-percent changes.
            if abs((downloads[index].fraction ?? -1) - fraction) >= 0.005 || fraction >= 1 {
                downloads[index].fraction = fraction
            }
        } else {
            let name = (path as NSString).lastPathComponent
            downloads.insert(Download(id: path, name: Self.finalName(forPartial: name) ?? name, fraction: fraction), at: 0)
        }
        refreshSizes()
    }

    private func complete(at index: Int, finalURL: URL?) {
        downloads[index].status = finalURL.map { .completed($0) } ?? .stopped
        downloads[index].finishedAt = Date()
        downloads[index].fraction = finalURL == nil ? downloads[index].fraction : 1
        if let finalURL {
            onEvent?(ActivityEvent(
                symbol: "arrow.down.circle.fill", tint: .blue, title: "Download Complete",
                detail: finalURL.lastPathComponent, tab: .activity
            ))
        }
    }

    private func trimFinished() {
        let finished = downloads.filter { !$0.isActive }
        if finished.count > 5, let cutoff = finished.dropFirst(5).first?.finishedAt {
            downloads.removeAll { !$0.isActive && ($0.finishedAt ?? .distantPast) <= cutoff }
        }
    }

    /// Indeterminate downloads show their size on disk; refresh it every 2 s
    /// only while such downloads exist.
    private func refreshSizes() {
        for index in downloads.indices where downloads[index].isActive {
            downloads[index].bytes = size(of: downloads[index].id) ?? downloads[index].bytes
        }
        let needsTimer = downloads.contains { $0.isActive && $0.fraction == nil }
        if needsTimer, sizeTimer == nil {
            sizeTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSizes() }
            }
        } else if !needsTimer {
            sizeTimer?.invalidate()
            sizeTimer = nil
        }
    }

    private func size(of path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        }
        // Safari .download bundles hold the partial file inside.
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return contents.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    }
}

/// Bridges Foundation's cross-process file progress into plain values.
/// Callbacks arrive on arbitrary threads, hence the lock and @unchecked Sendable.
private final class ProgressBridge: @unchecked Sendable {
    typealias Handler = @Sendable (_ path: String, _ fraction: Double, _ ended: Bool) -> Void

    private var subscriber: Any?
    private var observations: [String: NSKeyValueObservation] = [:]
    private let lock = NSLock()

    init(folder: URL, handler: @escaping Handler) {
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            guard let url = progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL else { return nil }
            let path = url.standardizedFileURL.path
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { p, _ in
                handler(path, p.fractionCompleted, false)
            }
            self?.lock.withLock { self?.observations[path] = observation }
            return { [weak self] in
                self?.lock.withLock { self?.observations[path] = nil }
                handler(path, 1, true)
            }
        }
    }

    deinit {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        lock.withLock { observations.removeAll() }
    }
}
