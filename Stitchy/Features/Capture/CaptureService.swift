import AppKit
import PDFKit
import Vision

/// Text capture (OCR) and background removal, all on this Mac with Vision.
///  - Screen text: `screencapture -i` lets you drag a region (macOS asks for
///    Screen Recording the first time); the image is read and deleted.
///  - Files: images, and PDFs (embedded text first, OCR for scanned pages).
@MainActor @Observable
final class CaptureService {
    private(set) var lastText: String?
    private(set) var isWorking = false
    private(set) var lastError: String?
    @ObservationIgnored var onEvent: ((ActivityEvent) -> Void)?

    /// Drag-select part of the screen; its text goes to the clipboard.
    func captureTextFromScreen() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-ocr-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let ok = await Self.run("/usr/sbin/screencapture", ["-i", "-x", "-o", file.path])
        guard ok, FileManager.default.fileExists(atPath: file.path) else { return }   // cancelled with Esc
        await deliver(text: try? await Self.text(from: file), source: "selection")
    }

    /// Drag-select part of the screen and return the image file (the caller deletes it), or nil if cancelled.
    func captureRegion() async -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("stitchy-capture-\(UUID().uuidString).png")
        guard await Self.run("/usr/sbin/screencapture", ["-i", "-x", file.path]), FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// Text from an image or PDF file, copied to the clipboard.
    func copyText(from url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await deliver(text: try? await Self.text(from: url), source: url.lastPathComponent)
    }

    /// Shows text as the last capture and copies it (OCR results, dictation).
    func deliver(text: String?, source: String) async {
        guard let text, !text.isEmpty else {
            lastError = "No text found."
            onEvent?(ActivityEvent(symbol: "text.viewfinder", tint: .orange, title: "No text found", detail: source, tab: .tools, recordsInFeed: false))
            return
        }
        lastText = text
        lastError = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let lines = text.split(separator: "\n").count
        onEvent?(ActivityEvent(symbol: "text.viewfinder", tint: .cyan, title: "Text copied",
                               detail: lines == 1 ? String(text.prefix(60)) : "\(lines) lines", tab: .tools))
    }

    /// Saves "<name> no background.png" next to the original and returns it.
    @discardableResult
    func removeBackground(_ url: URL) async -> URL? {
        guard !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        let out = FileShelf.uniqueURL(url.deletingLastPathComponent()
            .appendingPathComponent("\(url.deletingPathExtension().lastPathComponent) no background").appendingPathExtension("png"))
        let ok = await Task.detached { (try? Self.writeCutout(from: url, to: out)) ?? false }.value
        onEvent?(ActivityEvent(symbol: ok ? "person.crop.rectangle" : "exclamationmark.triangle.fill", tint: ok ? .purple : .orange,
                               title: ok ? "Background removed" : "No subject found", detail: ok ? out.lastPathComponent : url.lastPathComponent,
                               tab: .shelf))
        return ok ? out : nil
    }

    // MARK: Vision

    nonisolated static func text(from url: URL) async throws -> String {
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            var pages: [String] = []
            for i in 0..<min(pdf.pageCount, 50) {
                guard let page = pdf.page(at: i) else { continue }
                if let s = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    pages.append(s)
                } else if let image = render(page) {
                    pages.append(try recognize(image))   // scanned page
                }
            }
            return pages.joined(separator: "\n\n")
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return "" }
        return try recognize(image)
    }

    nonisolated static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    nonisolated private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2.0
        guard let ctx = CGContext(data: nil, width: Int(bounds.width * scale), height: Int(bounds.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// Foreground subject(s) on transparency (Vision, macOS 14).
    nonisolated static func writeCutout(from url: URL, to out: URL) throws -> Bool {
        guard !FileManager.default.fileExists(atPath: out.path),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
        guard let cg = try subjectCutout(image),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// The image's foreground subject(s) on transparency, same size as the input; nil if none.
    nonisolated static func subjectCutout(_ image: CGImage) throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ci, from: ci.extent)
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
}
