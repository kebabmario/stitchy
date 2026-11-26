// SPDX-License-Identifier: GPL-3.0-or-later
import AVFoundation
import AppKit
import ImageIO
import PDFKit
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
    /// Pinned files survive Clear and relaunches (paths kept in user data).
    private(set) var pinned: Set<URL> = Set((UserDefaults.standard.stringArray(forKey: "data.shelfPinned") ?? []).map { URL(fileURLWithPath: $0) })
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

    /// Drops onto a tile: a shelf file moves before `target`; new files are
    /// inserted there. Returns whether anything changed.
    @discardableResult
    func place(_ urls: [URL], before target: Item) -> Bool {
        var changed = false
        for url in urls.map(\.standardizedFileURL) {
            if let from = items.firstIndex(where: { $0.url == url }) {
                guard items[from].id != target.id else { continue }
                let moved = items.remove(at: from)
                items.insert(moved, at: items.firstIndex(where: { $0.id == target.id }) ?? items.endIndex)
                changed = true
            } else if add([url]) > 0, let new = items.popLast() {
                items.insert(new, at: items.firstIndex(where: { $0.id == target.id }) ?? items.endIndex)
                changed = true
            }
        }
        return changed
    }

    /// Writes a resized copy (longest side = `maxPixels`) next to the original,
    /// same format. The original is never touched.
    func resizeImage(_ item: Item, maxPixels: Int) {
        let base = item.url.deletingPathExtension().lastPathComponent
        let out = Self.uniqueURL(item.url.deletingLastPathComponent()
            .appendingPathComponent("\(base) \(maxPixels)px").appendingPathExtension(item.url.pathExtension))
        if Self.writeResized(from: item.url, to: out, maxPixels: maxPixels) {
            add([out])
        } else {
            onTransferEvent?(ActivityEvent(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't resize", detail: item.name, tab: .shelf))
        }
    }

    nonisolated static func writeResized(from source: URL, to out: URL, maxPixels: Int) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil), let type = CGImageSourceGetType(src),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary),
              !FileManager.default.fileExists(atPath: out.path),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, type, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: Transform (always writes new files next to the originals)

    /// Combines the shelf's PDFs and images, in shelf order, into one new PDF.
    func combineIntoPDF() {
        let sources = items.filter { isImage($0) || $0.url.pathExtension.lowercased() == "pdf" }.map(\.url)
        guard let first = sources.first else {
            onTransferEvent?(ActivityEvent(symbol: "doc.richtext", tint: .orange, title: "Add PDFs or images first", tab: .shelf))
            return
        }
        let out = Self.uniqueURL(first.deletingLastPathComponent().appendingPathComponent("Combined.pdf"))
        let pages = Self.writeCombinedPDF(sources, to: out)
        if pages > 0 { add([out]) }
        onTransferEvent?(ActivityEvent(symbol: pages > 0 ? "doc.richtext" : "exclamationmark.triangle.fill", tint: pages > 0 ? .red : .orange,
                                       title: pages > 0 ? "Combined \(pages) pages" : "Couldn't combine",
                                       detail: pages > 0 ? out.lastPathComponent : nil, tab: .shelf))
    }

    /// Returns the page count written (0 on failure). Never overwrites.
    nonisolated static func writeCombinedPDF(_ sources: [URL], to out: URL) -> Int {
        guard !FileManager.default.fileExists(atPath: out.path) else { return 0 }
        let doc = PDFDocument()
        for url in sources {
            if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
                for i in 0..<pdf.pageCount { if let page = pdf.page(at: i)?.copy() as? PDFPage { doc.insert(page, at: doc.pageCount) } }
            } else if let image = NSImage(contentsOf: url), let page = PDFPage(image: image) {
                doc.insert(page, at: doc.pageCount)
            }
        }
        guard doc.pageCount > 0, doc.write(to: out) else { return 0 }
        return doc.pageCount
    }

    /// Smaller JPEG copy (quality 0.6, same pixel size, orientation kept).
    func compressImage(_ item: Item) {
        let out = Self.uniqueURL(item.url.deletingLastPathComponent()
            .appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent) compressed").appendingPathExtension("jpg"))
        guard let saved = Self.writeCompressedJPEG(from: item.url, to: out, quality: 0.6) else {
            onTransferEvent?(ActivityEvent(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't compress", detail: item.name, tab: .shelf))
            return
        }
        add([out])
        onTransferEvent?(ActivityEvent(symbol: "photo", tint: .teal, title: "Compressed image", detail: saved, tab: .shelf))
    }

    /// Returns "2.4 MB → 610 KB" on success.
    nonisolated static func writeCompressedJPEG(from source: URL, to out: URL, quality: Double) -> String? {
        guard !FileManager.default.fileExists(atPath: out.path),
              let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        if let orientation = props[kCGImagePropertyOrientation] { options[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        func size(_ u: URL) -> String {
            ByteCountFormatter.string(fromByteCount: Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file)
        }
        return "\(size(source)) → \(size(out))"
    }

    func isVideo(_ item: Item) -> Bool {
        (try? item.url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .movie)) == true
    }

    /// HEVC 1080p copy via AVFoundation (hardware encoder). Original untouched.
    func compressVideo(_ item: Item) async {
        let out = Self.uniqueURL(item.url.deletingLastPathComponent()
            .appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent) compressed").appendingPathExtension("mp4"))
        onTransferEvent?(ActivityEvent(symbol: "film", tint: .teal, title: "Compressing video…", detail: item.name, tab: .shelf, recordsInFeed: false))
        let ok = await Self.exportVideo(item.url, to: out)
        if ok { add([out]) }
        onTransferEvent?(ActivityEvent(symbol: ok ? "film" : "exclamationmark.triangle.fill", tint: ok ? .teal : .orange,
                                       title: ok ? "Video compressed" : "Couldn't compress video",
                                       detail: ok ? out.lastPathComponent : item.name, tab: .shelf))
    }

    nonisolated static func exportVideo(_ source: URL, to out: URL) async -> Bool {
        let asset = AVURLAsset(url: source)
        let preset = AVAssetExportPresetHEVC1920x1080
        guard !FileManager.default.fileExists(atPath: out.path),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else { return false }
        session.outputURL = out
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        nonisolated(unsafe) let s = session   // AVAssetExportSession isn't Sendable; used only here
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in s.exportAsynchronously { c.resume() } }
        return s.status == .completed
    }

    /// Removes the item from the shelf only. The file itself is untouched.
    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
        icons[item.url] = nil
        thumbnails[item.url] = nil
    }

    /// Empties the shelf except pinned items. Files on disk are untouched.
    func clear() {
        items.removeAll { !pinned.contains($0.url) }
        icons = icons.filter { pinned.contains($0.key) }
        thumbnails = thumbnails.filter { pinned.contains($0.key) }
    }

    func isPinned(_ item: Item) -> Bool { pinned.contains(item.url) }

    func togglePin(_ item: Item) {
        if pinned.contains(item.url) { pinned.remove(item.url) } else { pinned.insert(item.url) }
        UserDefaults.standard.set(pinned.map(\.path).sorted(), forKey: "data.shelfPinned")
    }

    /// Puts pinned files (that still exist) back on the shelf at launch.
    func restorePinned() {
        let existing = pinned.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        let known = Set(items.map(\.url))
        items.insert(contentsOf: existing.subtracting(known).sorted { $0.path < $1.path }.map { Item(url: $0) }, at: 0)
    }

    // MARK: File tray actions (new files only; originals are never moved or changed)

    func isZip(_ item: Item) -> Bool { item.url.pathExtension.lowercased() == "zip" }
    func isPDF(_ item: Item) -> Bool { item.url.pathExtension.lowercased() == "pdf" }
    func isFolder(_ item: Item) -> Bool { (try? item.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && item.url.pathExtension != "app" }

    /// Extracts an archive into a new folder beside it.
    func unzip(_ item: Item) async {
        let out = Self.uniqueURL(item.url.deletingPathExtension())
        let ok = await Self.run("/usr/bin/ditto", ["-x", "-k", item.url.path, out.path])
        if ok { add([out]) }
        onTransferEvent?(ActivityEvent(symbol: ok ? "archivebox" : "exclamationmark.triangle.fill", tint: ok ? .teal : .orange,
                                       title: ok ? "Unzipped" : "Couldn't unzip", detail: ok ? out.lastPathComponent : item.name, tab: .shelf))
    }

    /// Smaller PDF copy: images re-saved as JPEG at screen resolution (PDFKit).
    func shrinkPDF(_ item: Item) {
        let out = Self.uniqueURL(item.url.deletingLastPathComponent()
            .appendingPathComponent("\(item.url.deletingPathExtension().lastPathComponent) smaller").appendingPathExtension("pdf"))
        let result = Self.writeSmallerPDF(from: item.url, to: out)
        if result != nil { add([out]) }
        onTransferEvent?(ActivityEvent(symbol: result != nil ? "doc.richtext" : "exclamationmark.triangle.fill", tint: result != nil ? .red : .orange,
                                       title: result != nil ? "Smaller PDF saved" : "Couldn't shrink PDF", detail: result ?? item.name, tab: .shelf))
    }

    nonisolated static func writeSmallerPDF(from source: URL, to out: URL) -> String? {
        guard !FileManager.default.fileExists(atPath: out.path), let doc = PDFDocument(url: source),
              doc.write(to: out, withOptions: [.saveImagesAsJPEGOption: true, .optimizeImagesForScreenOption: true]) else { return nil }
        func size(_ u: URL) -> String {
            ByteCountFormatter.string(fromByteCount: Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file)
        }
        return "\(size(source)) → \(size(out))"
    }

    /// Copies the shelf's files into a new folder beside the first one.
    func gatherIntoFolder() {
        let sources = items.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let first = sources.first else { return }
        let folder = Self.uniqueURL(first.deletingLastPathComponent().appendingPathComponent("Gathered Files"))
        let copied = Self.copy(sources, into: folder, createFolder: true)
        if copied > 0 { add([folder]) }
        onTransferEvent?(ActivityEvent(symbol: "folder.fill.badge.plus", tint: .blue, title: copied > 0 ? "Gathered \(copied) files" : "Couldn't gather files",
                                       detail: copied > 0 ? "\(folder.lastPathComponent) (copies; originals stay put)" : nil, tab: .shelf))
    }

    /// Copies dropped files into a folder on the shelf.
    func copy(_ urls: [URL], intoFolder folder: Item) {
        let n = Self.copy(urls, into: folder.url, createFolder: false)
        onTransferEvent?(ActivityEvent(symbol: "folder.fill", tint: .blue, title: n > 0 ? "Copied \(n) to \(folder.name)" : "Couldn't copy", tab: .shelf))
    }

    /// Returns how many were copied. Never overwrites: name clashes get " 2".
    nonisolated static func copy(_ urls: [URL], into folder: URL, createFolder: Bool) -> Int {
        let fm = FileManager.default
        if createFolder { try? fm.createDirectory(at: folder, withIntermediateDirectories: false) }
        var n = 0
        for u in urls where u.standardizedFileURL != folder.standardizedFileURL {
            if (try? fm.copyItem(at: u, to: uniqueURL(folder.appendingPathComponent(u.lastPathComponent)))) != nil { n += 1 }
        }
        return n
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

    // MARK: Quick actions (always create new files; originals untouched)

    /// Zips the items next to the first one with Apple's `ditto`, then adds
    /// the archive to the shelf.
    func compress(_ selection: [Item]? = nil) async {
        let urls = (selection ?? items).map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard let first = urls.first else { return }
        let dir = first.deletingLastPathComponent()
        let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let out = Self.uniqueURL(dir.appendingPathComponent(base).appendingPathExtension("zip"))
        let ok = await Self.run("/usr/bin/ditto", urls.count == 1
            ? ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, out.path]
            : ["-c", "-k", "--sequesterRsrc"] + [Self.stage(urls)?.path ?? "", out.path])
        if ok { add([out]) }
        onTransferEvent?(ActivityEvent(symbol: ok ? "doc.zipper" : "exclamationmark.triangle.fill", tint: ok ? .teal : .orange,
                                       title: ok ? "Compressed" : "Couldn't compress", detail: ok ? out.lastPathComponent : nil,
                                       tab: .shelf, showsAlert: true))
    }

    /// Writes a converted copy (PNG or JPEG) next to the original.
    func convertImage(_ item: Item, toPNG: Bool) {
        guard let image = NSImage(contentsOf: item.url), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: toPNG ? .png : .jpeg, properties: toPNG ? [:] : [.compressionFactor: 0.85]) else {
            onTransferEvent?(ActivityEvent(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Not an image", tab: .shelf))
            return
        }
        let out = Self.uniqueURL(item.url.deletingPathExtension().appendingPathExtension(toPNG ? "png" : "jpg"))
        do {
            try data.write(to: out, options: .withoutOverwriting)
            add([out])
        } catch {
            onTransferEvent?(ActivityEvent(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't convert", detail: error.localizedDescription, tab: .shelf))
        }
    }

    func copyPaths(_ selection: [Item]? = nil) {
        let text = (selection ?? items).map(\.url.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func isImage(_ item: Item) -> Bool {
        (try? item.url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
    }

    /// "photo.png" -> "photo 2.png" if taken. Never overwrites.
    nonisolated static func uniqueURL(_ url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// Several items: copied into a temporary folder that ditto archives.
    private static func stage(_ urls: [URL]) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("StitchyZip-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for u in urls { try FileManager.default.copyItem(at: u, to: dir.appendingPathComponent(u.lastPathComponent)) }
            return dir
        } catch { return nil }
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) async -> Bool {
        await withCheckedContinuation { c in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool)
                p.arguments = args
                do { try p.run(); p.waitUntilExit(); c.resume(returning: p.terminationStatus == 0) } catch { c.resume(returning: false) }
            }
        }
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
