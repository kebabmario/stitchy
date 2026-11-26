// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Notes page: Apple Notes first; legacy notes saved by earlier Stitchy
/// versions appear under "On This Mac" until you move them.
struct NotesView: View {
    enum Source: Hashable { case apple, local }
    @Environment(NotesStore.self) private var local
    @State private var source: Source = .apple

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !local.notes.isEmpty {
                Segmented(options: [(.apple, "Apple Notes"), (.local, "On This Mac")], selection: $source)
            }
            if source == .local, !local.notes.isEmpty { LocalNotesView() } else { AppleNotesView() }
        }
    }
}

/// Notes saved inside Stitchy by earlier versions. Kept until moved.
struct LocalNotesView: View {
    @Environment(NotesStore.self) private var notes
    @Environment(AppleNotesService.self) private var apple
    @State private var confirmMove = false
    @State private var moveStatus: String?
    @State private var query = ""
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    SearchField(text: $query, prompt: "Search")
                    IconButton(symbol: "arrow.up.forward.app", size: 10, diameter: 24, help: "Move all to Apple Notes") {
                        confirmMove = true
                    }
                }
                IslandScroll(axis: .vertical) {
                    VStack(spacing: 2) {
                        ForEach(notes.search(query)) { note in
                            Button { select(note) } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                    Text(note.updated, format: .relative(presentation: .named))
                                        .font(.system(size: 9.5)).foregroundStyle(Color.tertiaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(notes.selectedID == note.id ? 0.12 : 0)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plainHit)
                        }
                    }
                }
            }
            .frame(width: 150)

            Group {
                if let selected = notes.selected {
                    VStack(alignment: .trailing, spacing: 4) {
                        TextEditor(text: $draft)
                            .font(.system(size: 12.5))
                            .scrollContentBackground(.hidden)
                            .focused($editorFocused)
                            .onChange(of: draft) { _, text in notes.update(selected.id, text: text) }
                        Button { notes.delete(selected.id) } label: {
                            Label("Delete", systemImage: "trash").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.tertiaryText)
                        }
                        .buttonStyle(.plainHit)
                    }
                    .padding(8)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "note.text").font(.system(size: 20)).foregroundStyle(Color.tertiaryText)
                        Text(notes.notes.isEmpty ? "No notes yet" : "Select a note").font(.system(size: 12, weight: .semibold))
                        Text("Saved on this Mac only.").font(.system(size: 10.5)).foregroundStyle(Color.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { draft = notes.selected?.text ?? "" }
        .onDisappear { notes.saveNow() }
        .overlay(alignment: .bottomLeading) {
            if let moveStatus { Text(moveStatus).font(.system(size: 10)).foregroundStyle(Color.secondaryText) }
        }
        .confirmationDialog("Move \(notes.notes.count) notes to Apple Notes?", isPresented: $confirmMove) {
            Button("Move to Apple Notes") { Task { await moveAll() } }
        } message: {
            Text("Each note is created in Apple Notes first; the copy in Stitchy is removed only after Apple Notes confirms it was saved.")
        }
    }

    /// Explicit migration: create in Apple Notes, then delete locally on success.
    private func moveAll() async {
        var moved = 0
        for note in notes.notes {
            if await apple.create(text: note.text, folderID: nil) != nil {
                notes.delete(note.id)
                moved += 1
            }
        }
        notes.saveNow()
        moveStatus = moved == 0 ? "Nothing moved. Check Apple Notes access." : "Moved \(moved) notes to Apple Notes."
    }

    private func select(_ note: NotesStore.Note) {
        notes.selectedID = note.id
        draft = note.text
    }
}

/// Compact search field styled for the island.
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var focusToken: Int = 0
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.secondaryText)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.tertiaryText) }
                    .buttonStyle(.plainHit)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.white.opacity(0.08), in: Capsule())
        .onChange(of: focusToken) { _, _ in focused = true }
        .onAppear { if focusToken > 0 { focused = true } }
    }
}
