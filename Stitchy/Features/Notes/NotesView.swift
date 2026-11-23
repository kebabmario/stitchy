import SwiftUI

/// Quick Notes: searchable list on the left, editor on the right.
struct NotesView: View {
    @Environment(NotesStore.self) private var notes
    @State private var query = ""
    @State private var draft = ""
    @FocusState private var editorFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    SearchField(text: $query, prompt: "Search")
                    IconButton(symbol: "square.and.pencil", size: 10, diameter: 24, help: "New Note") {
                        let note = notes.create()
                        draft = note.text
                        editorFocused = true
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
                            .buttonStyle(.plain)
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
                        .buttonStyle(.plain)
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
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.white.opacity(0.08), in: Capsule())
        .onChange(of: focusToken) { _, _ in focused = true }
        .onAppear { if focusToken > 0 { focused = true } }
    }
}
