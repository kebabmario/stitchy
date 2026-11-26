// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Marks drawn on an image, in normalized coordinates (0...1, origin top-left)
/// so the preview and the full-resolution export agree.
struct Mark: Equatable {
    enum Kind: Equatable { case arrow, box, text(String), blur }
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

enum AnnotationRenderer {
    /// Draws `marks` over `image` at its full pixel size.
    static func render(_ image: CGImage, marks: [Mark]) -> CGImage? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let size = CGSize(width: w, height: h)
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        let pixelated = marks.contains { $0.kind == .blur } ? pixelate(image) : nil
        // Flip to top-left coordinates for the marks.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        let lineWidth = max(CGFloat(min(w, h)) / 180, 3)
        for mark in marks { draw(mark, in: size, lineWidth: lineWidth, pixelated: pixelated, ctx: ctx) }
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    static func draw(_ mark: Mark, in size: CGSize, lineWidth: CGFloat, pixelated: CGImage?, ctx: CGContext) {
        func p(_ n: CGPoint) -> CGPoint { CGPoint(x: n.x * size.width, y: n.y * size.height) }
        let a = p(mark.start), b = p(mark.end)
        let r = CGRect(x: mark.rect.minX * size.width, y: mark.rect.minY * size.height, width: mark.rect.width * size.width, height: mark.rect.height * size.height)
        switch mark.kind {
        case .blur:
            guard let pixelated else { return }
            ctx.saveGState()
            ctx.clip(to: r)
            // The context is flipped; draw the (unflipped) pixelated image upright.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(pixelated, in: CGRect(origin: .zero, size: size))
            ctx.restoreGState()
        case .box:
            let path = NSBezierPath(roundedRect: r, xRadius: lineWidth, yRadius: lineWidth)
            path.lineWidth = lineWidth
            mark.color.setStroke()
            path.stroke()
        case .arrow:
            let path = NSBezierPath()
            path.move(to: a)
            path.line(to: b)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            mark.color.setStroke()
            path.stroke()
            let angle = atan2(b.y - a.y, b.x - a.x), head = lineWidth * 5
            let head1 = CGPoint(x: b.x - head * cos(angle - .pi / 6), y: b.y - head * sin(angle - .pi / 6))
            let head2 = CGPoint(x: b.x - head * cos(angle + .pi / 6), y: b.y - head * sin(angle + .pi / 6))
            let tip = NSBezierPath()
            tip.move(to: b); tip.line(to: head1); tip.line(to: head2); tip.close()
            mark.color.setFill()
            tip.fill()
        case .text(let string):
            let font = NSFont.systemFont(ofSize: lineWidth * 7, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: mark.color,
                .strokeColor: mark.color == .black ? NSColor.white : NSColor.black, .strokeWidth: -3,
            ]
            (string as NSString).draw(at: a, withAttributes: attributes)
        }
    }

    static func pixelate(_ image: CGImage) -> CGImage? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.pixellate()
        filter.inputImage = ci.clampedToExtent()
        filter.scale = Float(max(image.width, image.height)) / 60
        filter.center = .zero
        guard let out = filter.outputImage?.cropped(to: ci.extent) else { return nil }
        return CIContext().createCGImage(out, from: ci.extent)
    }
}

/// Opens an image in a small annotation window. Saving always writes a new file.
@MainActor
final class AnnotationEditor {
    private var windows: [NSWindow] = []
    var onSaved: ((URL) -> Void)?

    func open(_ url: URL, deleteSourceOnClose: Bool = false) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return }
        let saveDir = deleteSourceOnClose ? Self.screenshotFolder() : url.deletingLastPathComponent()
        let baseName = deleteSourceOnClose ? "Screenshot \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)))".replacingOccurrences(of: ":", with: ".")
                                          : url.deletingPathExtension().lastPathComponent
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560), styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Annotate"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AnnotationView(image: image) { [weak self, weak window] rendered in
            guard let rendered else { return }
            let out = FileShelf.uniqueURL(saveDir.appendingPathComponent("\(baseName) annotated").appendingPathExtension("png"))
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dest, rendered, nil)
            if CGImageDestinationFinalize(dest) { self?.onSaved?(out); window?.close() }
        })
        window.center()
        let closing = ObjectIdentifier(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if deleteSourceOnClose { try? FileManager.default.removeItem(at: url) }   // our temporary capture only
                self?.windows.removeAll { ObjectIdentifier($0) == closing }
            }
        }
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Where macOS saves screenshots (Screenshot app setting), else the Desktop.
    static func screenshotFolder() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}

private struct AnnotationView: View {
    let image: CGImage
    let save: (CGImage?) -> Void
    enum Tool: String, CaseIterable { case arrow = "Arrow", box = "Box", text = "Text", blur = "Blur" }
    @State private var tool: Tool = .arrow
    @State private var color: NSColor = .systemRed
    @State private var marks: [Mark] = []
    @State private var drawing: Mark?
    @State private var textDraft = ""
    @State private var copied = false
    @State private var pixelated: CGImage?
    private let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal, 12).padding(.top, 30).padding(.bottom, 8)
            GeometryReader { geo in
                let fit = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(width: fit.width, height: fit.height)
                    Canvas { ctx, size in
                        ctx.withCGContext { cg in
                            let ns = NSGraphicsContext(cgContext: cg, flipped: true)
                            NSGraphicsContext.saveGraphicsState()
                            NSGraphicsContext.current = ns
                            for mark in marks + (drawing.map { [$0] } ?? []) {
                                AnnotationRenderer.draw(mark, in: size, lineWidth: 3, pixelated: pixelated, ctx: cg)
                            }
                            NSGraphicsContext.restoreGraphicsState()
                        }
                    }
                    .frame(width: fit.width, height: fit.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let s = norm(g.startLocation, fit), e = norm(g.location, fit)
                        switch tool {
                        case .text: break
                        case .arrow: drawing = Mark(kind: .arrow, start: s, end: e, color: color)
                        case .box: drawing = Mark(kind: .box, start: s, end: e, color: color)
                        case .blur: drawing = Mark(kind: .blur, start: s, end: e, color: color)
                        }
                    }.onEnded { g in
                        if tool == .text {
                            let t = textDraft.trimmingCharacters(in: .whitespaces)
                            if !t.isEmpty { marks.append(Mark(kind: .text(t), start: norm(g.location, fit), end: norm(g.location, fit), color: color)) }
                        } else if let d = drawing, hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 0.005 {
                            marks.append(d)
                        }
                        drawing = nil
                    })
                }
                .frame(width: fit.width, height: fit.height)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(.background)
        .task { pixelated = AnnotationRenderer.pixelate(image) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Tool", selection: $tool) { ForEach(Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).frame(width: 240).labelsHidden()
            if tool == .text {
                TextField("Type, then click the image", text: $textDraft).textFieldStyle(.roundedBorder).frame(width: 170)
            }
            HStack(spacing: 4) {
                ForEach(colors, id: \.self) { c in
                    Button { color = c } label: {
                        Circle().fill(Color(nsColor: c)).frame(width: 16, height: 16)
                            .overlay(Circle().strokeBorder(.primary.opacity(c == color ? 0.9 : 0.2), lineWidth: c == color ? 2 : 1))
                    }
                    .buttonStyle(.plainHit)
                }
            }
            Spacer()
            Button("Undo") { _ = marks.popLast() }.disabled(marks.isEmpty).keyboardShortcut("z")
            Button(copied ? "Copied" : "Copy") {
                guard let out = AnnotationRenderer.render(image, marks: marks) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([NSImage(cgImage: out, size: .zero)])
                copied = true
            }
            Button("Save Copy") { save(AnnotationRenderer.render(image, marks: marks)) }
                .keyboardShortcut("s").buttonStyle(.borderedProminent)
        }
    }

    private func fitted(in size: CGSize) -> CGSize {
        let ratio = min(size.width / CGFloat(image.width), size.height / CGFloat(image.height), 1)
        return CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
    }

    private func norm(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / size.width, 0), 1), y: min(max(p.y / size.height, 0), 1))
    }
}
