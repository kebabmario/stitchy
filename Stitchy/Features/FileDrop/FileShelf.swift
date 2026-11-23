import AppKit
import Observation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Temporary holding area for dropped files (inspired by Droppy).
///
/// The shelf only stores *references* to files. Removing an item or clearing
/// the shelf never touches the file on disk; nothing is ever moved, copied
/// or deleted unless the user drags it somewhere themselves.
@MainActor @Observable
final class FileShelf: NSObject, NSSharingServiceDelegate {
    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        /// Finder display name ("Calculator", not "Calculator.app").
        var name: String { FileManager.default.displayName(atPath: url.path) }
        /// Human-readable type ("PDF document", "Folder").
        var kind: String {
            (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? ""
        }
    }

    private(set) var items: [Item] = []
    @ObservationIgnored var onAdd: ((Int) -> Void)?
    @ObservationIgnored private var icons: [URL: NSImage] = [:]
    /// QuickLook thumbnails, generated asynchronously when previews are on.
    private(set) var thumbnails: [URL: NSImage] = [:]
    /// Outgoing AirDrop: macOS reports start and finish, not byte progress.
    private(set) var airDropInProgress: Int?
    @ObservationIgnored var onTransferEvent: ((ActivityEvent) -> Void)?

    /// Adds existing file URLs, skipping duplicates. Returns how many were added.
    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let known = Set(items.map { $0.url.standardizedFileURL })
        var seen = known
        var added: [Item] = []
        for url in urls where url.isFileURL {
            let standardized = url.standardizedFileURL
            guard !seen.contains(standardized),
                  FileManager.default.fileExists(atPath: standardized.path) else { continue }
            seen.insert(standardized)
            added.append(Item(url: standardized))
        }
        guard !added.isEmpty else { return 0 }
        items.append(contentsOf: added)
        islandLog.info("shelf added \(added.count, privacy: .public)")
        onAdd?(added.count)
        return added.count
    }

    /// Removes the item from the shelf only. The file itself is untouched.
    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        icons[item.url] = nil
        thumbnails[item.url] = nil
    }

    /// Empties the shelf. Files on disk are untouched.
    func clear() {
        items.removeAll()
        icons.removeAll()
        thumbnails.removeAll()
    }

    func exists(_ item: Item) -> Bool {
        FileManager.default.fileExists(atPath: item.url.path)
    }

    func thumbnail(for item: Item, size: CGFloat) -> NSImage? {
        if let image = thumbnails[item.url] { return image }
        let url = item.url
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let cg = rep?.cgImage else { return }
            let image = NSImage(cgImage: cg, size: .zero)
            Task { @MainActor [weak self] in self?.thumbnails[url] = image }
        }
        return nil
    }

    func icon(for item: Item) -> NSImage {
        if let cached = icons[item.url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: item.url.path)
        icons[item.url] = image
        return image
    }

    func reveal(_ selection: [Item]? = nil) {
        let urls = (selection ?? items).map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    func airDrop(_ selection: [Item]? = nil) {
        let urls = (selection ?? items).map(\.url)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.delegate = self
        service.perform(withItems: urls)
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        airDropInProgress = items.count
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        airDropInProgress = nil
        onTransferEvent?(ActivityEvent(symbol: "airplayaudio", tint: .blue, title: "AirDrop Sent",
                                       detail: items.count == 1 ? "1 item" : "\(items.count) items", tab: .shelf))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        airDropInProgress = nil
        let cancelled = (error as NSError).code == NSUserCancelledError
        onTransferEvent?(ActivityEvent(symbol: "airplayaudio", tint: .gray, title: cancelled ? "AirDrop Cancelled" : "AirDrop Failed",
                                       detail: cancelled ? nil : error.localizedDescription, tab: .shelf, showsAlert: !cancelled))
    }
}
