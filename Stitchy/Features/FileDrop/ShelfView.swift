import SwiftUI

/// The file shelf. Drop anywhere on the expanded island to add files.
struct ShelfView: View {
    @Environment(FileShelf.self) private var shelf
    @Environment(IslandModel.self) private var model

    var body: some View {
        if shelf.items.isEmpty || model.isFileDragActive {
            dropZone
        } else {
            VStack(spacing: 10) {
                IslandScroll(axis: .horizontal) {
                    HStack(spacing: 6) {
                        ForEach(shelf.items) { item in FileTile(item: item) }
                    }
                }
                .frame(height: 90)
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
                .font(.system(size: 13, weight: .semibold))
            Text(shelf.items.isEmpty ? "Files stay where they are. The shelf only keeps a reference." : "\(shelf.items.count) on Shelf")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
        }
        .foregroundStyle(targeted ? .white : .white.opacity(0.75))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(targeted ? 0.1 : 0.03))
                .strokeBorder(.white.opacity(targeted ? 0.55 : 0.18), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: targeted)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(shelf.items.count == 1 ? "1 item" : "\(shelf.items.count) items")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondaryText)
            Spacer()
            PillButton(title: "AirDrop", symbol: "airplayaudio") { shelf.airDrop() }
            PillButton(title: "Reveal", symbol: "folder") { shelf.reveal() }
            PillButton(title: "Clear", symbol: "xmark") { withAnimation(.snappy) { shelf.clear() } }
                .help("Removes items from the shelf. Files on disk are not touched.")
        }
    }
}

private struct FileTile: View {
    let item: FileShelf.Item
    @Environment(FileShelf.self) private var shelf
    @State private var hovering = false

    var body: some View {
        let exists = shelf.exists(item)
        VStack(spacing: 4) {
            Image(nsImage: shelf.icon(for: item))
                .resizable()
                .frame(width: 46, height: 46)
                .opacity(exists ? 1 : 0.35)
            Text(exists ? item.name : "Missing")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation(.snappy) { shelf.remove(item) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Remove from Shelf (file is kept)")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(count: 2) { if exists { shelf.open(item) } }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { shelf.open(item) }.disabled(!exists)
            Button("Show in Finder") { shelf.reveal([item]) }.disabled(!exists)
            Button("AirDrop") { shelf.airDrop([item]) }.disabled(!exists)
            Divider()
            Button("Remove from Shelf") { shelf.remove(item) }
        }
        .help(item.url.path)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.name)
    }
}
