import SwiftUI

/// Shelf page: dropped files and (when enabled) clipboard history.
struct ShelfView: View {
    enum Mode: Hashable { case files, clipboard }
    @Environment(AppSettings.self) private var settings
    @Environment(IslandModel.self) private var model
    @State private var mode: Mode = .files

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.shelfEnabled {
                Segmented(options: [(.files, "Files"), (.clipboard, "Clipboard")], selection: $mode)
            }
            Group {
                if mode == .clipboard || !settings.shelfEnabled {
                    PrivateGate { ClipboardView() }
                } else {
                    FilesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.isFileDragActive) { _, dragging in if dragging { mode = .files } }
    }
}

private struct FilesView: View {
    @Environment(FileShelf.self) private var shelf
    @Environment(IslandModel.self) private var model

    var body: some View {
        if shelf.items.isEmpty || model.isFileDragActive {
            dropZone
        } else {
            VStack(spacing: 8) {
                IslandScroll(axis: .horizontal) {
                    HStack(spacing: 4) {
                        ForEach(shelf.items) { item in FileTile(item: item) }
                    }
                    .padding(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .well(padding: 4)
                footer
            }
        }
    }

    private var dropZone: some View {
        let targeted = model.isDropTargeted
        return VStack(spacing: 6) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24, weight: .medium))
                .symbolEffect(.bounce, value: targeted)
            Text(targeted ? "Release to Add" : "Drop Files Here")
                .font(DS.title)
            Text(shelf.items.isEmpty ? "Files stay where they are. The shelf only keeps a reference." : "\(shelf.items.count) on Shelf")
                .font(DS.caption)
                .foregroundStyle(Color.secondaryText)
        }
        .foregroundStyle(targeted ? .white : .white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: DS.wellRadius, style: .continuous)
                .fill(.white.opacity(targeted ? 0.1 : 0.04))
                .strokeBorder(.white.opacity(targeted ? 0.5 : 0.16), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: targeted)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            SectionLabel(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
            if shelf.airDropInProgress != nil {
                Label("Sending…", systemImage: "airplayaudio").font(DS.caption).foregroundStyle(.blue)
            }
            Spacer(minLength: 4)
            Chip(title: "Zip", symbol: "doc.zipper") { Task { await shelf.compress() } }
                .help("Creates a .zip next to the first file. Originals are untouched.")
            Chip(title: "PDF", symbol: "doc.richtext") { shelf.combineIntoPDF() }
                .help("Combines the shelf's PDFs and images, in order, into a new PDF.")
            Chip(title: "Folder", symbol: "folder.badge.plus") { shelf.gatherIntoFolder() }
                .help("Copies the shelf's files into a new folder. Originals stay where they are.")
            Chip(title: "", symbol: "airplayaudio") { shelf.airDrop() }.help("Send with AirDrop").accessibilityLabel("Send with AirDrop")
            Chip(title: "", symbol: "magnifyingglass") { shelf.reveal() }.help("Show in Finder").accessibilityLabel("Show in Finder")
            Chip(title: "", symbol: "xmark") { withAnimation(.snappy) { shelf.clear() } }
                .accessibilityLabel("Clear shelf")
                .help("Removes unpinned items from the shelf. Files on disk are not touched.")
        }
    }
}

private struct FileTile: View {
    let item: FileShelf.Item
    @Environment(FileShelf.self) private var shelf
    @Environment(CaptureService.self) private var capture
    @Environment(AppServices.self) private var services
    @Environment(AppSettings.self) private var settings
    @State private var hovering = false

    var body: some View {
        let exists = shelf.exists(item)
        VStack(spacing: 3) {
            Group {
                if settings.shelfPreviews, exists, let thumb = shelf.thumbnail(for: item, size: 96) {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(nsImage: shelf.icon(for: item)).resizable()
                }
            }
            .frame(width: 48, height: 48)
            .opacity(exists ? 1 : 0.35)
            Text(exists ? item.name : "Missing")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.kind)
                .font(.system(size: 9))
                .foregroundStyle(Color.tertiaryText)
                .lineLimit(1)
        }
        .frame(width: 74)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topLeading) {
            if shelf.isPinned(item) {
                Image(systemName: "pin.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
                    .padding(4).background(Circle().fill(.black.opacity(0.6))).padding(2)
                    .accessibilityLabel("Pinned")
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(.snappy) { shelf.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plainHit)
                .help("Remove from Shelf (file is kept)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(count: 2) { if exists { shelf.open(item) } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .modifier(ReorderDrop(item: item))
        .contextMenu {
            Button("Open") { shelf.open(item) }.disabled(!exists)
            Button("Show in Finder") { shelf.reveal([item]) }.disabled(!exists)
            Button("AirDrop") { shelf.airDrop([item]) }.disabled(!exists)
            Divider()
            Button("Compress to Zip") { Task { await shelf.compress([item]) } }.disabled(!exists)
            if shelf.isImage(item) {
                Button("Save a PNG Copy") { shelf.convertImage(item, toPNG: true) }
                Button("Save a JPEG Copy") { shelf.convertImage(item, toPNG: false) }
                Menu("Save a Resized Copy") {
                    ForEach([3840, 2560, 1920, 1280, 1024, 512], id: \.self) { px in
                        Button("\(px) px (longest side)") { shelf.resizeImage(item, maxPixels: px) }
                    }
                }
            }
            if shelf.isImage(item) {
                Button("Save a Compressed Copy") { shelf.compressImage(item) }.disabled(!exists)
            }
            if shelf.isVideo(item) {
                Button("Save a Compressed Copy (HEVC 1080p)") { Task { await shelf.compressVideo(item) } }.disabled(!exists)
            }
            if shelf.isImage(item) || item.url.pathExtension.lowercased() == "pdf" {
                Button("Copy Text (OCR)") { Task { await capture.copyText(from: item.url) } }.disabled(!exists)
            }
            if shelf.isImage(item) {
                Button("Annotate…") { services.annotator.open(item.url) }.disabled(!exists)
                Button("Remove Background") {
                    Task { if let out = await capture.removeBackground(item.url) { shelf.add([out]) } }
                }.disabled(!exists)
            }
            if shelf.isZip(item) {
                Button("Unzip Here") { Task { await shelf.unzip(item) } }.disabled(!exists)
            }
            if shelf.isPDF(item) {
                Button("Save a Smaller PDF") { shelf.shrinkPDF(item) }.disabled(!exists)
            }
            Button("Copy Path") { shelf.copyPaths([item]) }
            Divider()
            Button(shelf.isPinned(item) ? "Unpin" : "Pin to Shelf") { shelf.togglePin(item) }
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
    }
}

private struct ClipboardView: View {
    @Environment(ClipboardHistory.self) private var clipboard
    @Environment(AppSettings.self) private var settings
    @State private var query = ""

    var body: some View {
        if !settings.clipboardEnabled {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 22, weight: .medium)).foregroundStyle(Color.secondaryText)
                Text("Clipboard History is off").font(.system(size: 13, weight: .semibold))
                Text("When on, Stitchy keeps your recent copies in memory only. Password managers and concealed items are never recorded.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText).multilineTextAlignment(.center).frame(maxWidth: 330)
                PillButton(title: "Turn On", tint: .white, prominent: true) { settings.clipboardEnabled = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if clipboard.entries.isEmpty {
            Text("Copy something and it appears here. Click an entry to copy it again.")
                .font(.system(size: 11)).foregroundStyle(Color.tertiaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                SearchField(text: $query, prompt: "Search clipboard")
                IslandScroll(axis: .vertical) {
                    VStack(spacing: 2) {
                        ForEach(clipboard.search(query)) { ClipRow(entry: $0) }
                    }
                }
                HStack {
                    Text("\(clipboard.entries.count) of \(Int(settings.clipboardHistorySize))")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.tertiaryText)
                    Spacer()
                    Button("Clear History") { withAnimation(.snappy) { clipboard.clear() } }
                        .buttonStyle(.plainHit).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Color.secondaryText)
                }
            }
        }
    }
}

private struct ClipRow: View {
    let entry: ClipboardHistory.Entry
    @Environment(ClipboardHistory.self) private var clipboard
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if case .image(let image) = entry.content {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: entry.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.preview).font(entry.isCode ? .system(size: 11, weight: .medium, design: .monospaced) : .system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Text([entry.sourceApp, entry.date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 9.5)).foregroundStyle(Color.tertiaryText)
            }
            Spacer(minLength: 4)
            smartAction
            if copied {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
            } else if hovering || entry.pinned {
                Button { withAnimation(.snappy) { clipboard.togglePin(entry) } } label: {
                    Image(systemName: entry.pinned ? "pin.fill" : "pin").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.pinned ? Color.orange : Color.secondaryText)
                }
                .buttonStyle(PressableStyle()).help(entry.pinned ? "Unpin" : "Pin (kept when clearing)")
                if hovering {
                    Button { withAnimation(.snappy) { clipboard.delete(entry) } } label: {
                        Image(systemName: "trash").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.secondaryText)
                    }
                    .buttonStyle(PressableStyle()).help("Delete entry")
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            clipboard.copy(entry)
            withAnimation { copied = true }
            Task { try? await Task.sleep(for: .seconds(1)); withAnimation { copied = false } }
        }
        .help("Click to copy")
    }

    @ViewBuilder private var smartAction: some View {
        switch entry.smart {
        case .link(let url):
            Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "safari").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(PressableStyle()).foregroundStyle(.blue).help("Open link")
        case .email(let address):
            Button { if let u = URL(string: "mailto:\(address)") { NSWorkspace.shared.open(u) } } label: {
                Image(systemName: "envelope").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(PressableStyle()).foregroundStyle(.blue).help("New email")
        case .color(let color):
            Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white.opacity(0.3)))
                .help("Colour")
        case nil:
            EmptyView()
        }
    }
}

/// Dropping onto a tile reorders shelf files or inserts new ones there.
private struct ReorderDrop: ViewModifier {
    let item: FileShelf.Item
    @Environment(FileShelf.self) private var shelf
    @State private var targeted = false

    func body(content: Content) -> some View {
        if SnapshotRenderer.isRendering {
            content
        } else {
            content
                .overlay(alignment: .leading) {
                    if targeted { Capsule().fill(.white).frame(width: 3).padding(.vertical, 8).offset(x: -4).transition(.opacity) }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    // New files onto a folder tile are copied into it; shelf files dropped anywhere reorder.
                    let onShelf = Set(shelf.items.map(\.url))
                    let incoming = urls.map(\.standardizedFileURL).filter { !onShelf.contains($0) }
                    if shelf.isFolder(item), !incoming.isEmpty, incoming.count == urls.count {
                        shelf.copy(incoming, intoFolder: item)
                        return true
                    }
                    return withAnimation(.snappy) { shelf.place(urls, before: item) }
                } isTargeted: { t in withAnimation(.easeOut(duration: 0.12)) { targeted = t } }
        }
    }
}
