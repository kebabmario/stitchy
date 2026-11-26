// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Apple Notes in the island: list, search, folders, preview/edit, create,
/// Open in Notes. Everything is read from and written to Apple Notes.
struct AppleNotesView: View {
    @Environment(AppleNotesService.self) private var notes
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var folderID: String?

    var body: some View {
        Group {
            if !settings.appleNotesEnabled {
                connect
            } else {
                switch notes.status {
                case .denied: denied
                case .failed(let message) where notes.notes.isEmpty: failure(message)
                default: browser
                }
            }
        }
        .task(id: settings.appleNotesEnabled) {
            if settings.appleNotesEnabled { await notes.refresh() }
        }
    }

    private var browser: some View {
        HStack(spacing: 12) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    SearchField(text: $query, prompt: "Search Notes")
                    IconButton(symbol: "square.and.pencil", size: 10, diameter: 24, help: "New Note in Apple Notes") { notes.startCompose() }
                }
                HStack(spacing: 4) {
                    folderMenu
                    Spacer(minLength: 0)
                    if case .loading = notes.status {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button { Task { await notes.refresh(force: true) } } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plainHit).foregroundStyle(Color.secondaryText).help("Refresh from Apple Notes")
                    }
                }
                IslandScroll(axis: .vertical) {
                    VStack(spacing: 1) {
                        ForEach(notes.search(query, folderID: folderID).prefix(150)) { note in
                            Button { Task { await notes.select(note.id) } } label: { NoteRow(note: note, selected: notes.selectedID == note.id) }
                                .buttonStyle(.plainHit)
                        }
                        if notes.search(query, folderID: folderID).isEmpty, case .ready = notes.status {
                            Text(query.isEmpty ? "No notes" : "No matches").font(.system(size: 10.5)).foregroundStyle(Color.tertiaryText).padding(.top, 12)
                        }
                    }
                }
            }
            .frame(width: 168)

            NoteDetailPane(folderID: folderID)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var folderMenu: some View {
        Menu {
            Button("All Notes") { folderID = nil }
            let accounts = Dictionary(grouping: notes.folders, by: \.account)
            ForEach(accounts.keys.sorted(), id: \.self) { account in
                Section(account) {
                    ForEach(accounts[account] ?? []) { folder in Button(folder.name) { folderID = folder.id } }
                }
            }
        } label: {
            Text(notes.folders.first { $0.id == folderID }.map { "\($0.name) · \($0.account)" } ?? "All Notes")
                .font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(Color.secondaryText)
    }

    private var connect: some View {
        EmptyState(symbol: "note.text", tint: .yellow, title: "Apple Notes in Stitchy",
                   message: "Browse, search and create notes in iCloud and On My Mac. Notes stay in Apple Notes; macOS asks once to let Stitchy control Notes.",
                   actionTitle: "Connect Apple Notes") { settings.appleNotesEnabled = true }
    }

    private var denied: some View {
        VStack(spacing: DS.Space.s) {
            EmptyState(symbol: "hand.raised.fill", tint: .orange, title: "Stitchy isn't allowed to control Notes",
                       message: "Turn on Notes for Stitchy in Privacy & Security › Automation, then try again.")
            HStack(spacing: DS.Space.s) {
                Chip(title: "Open Automation Settings") { SystemSettingsLink.open(SystemSettingsLink.automation) }
                Chip(title: "Try Again") { Task { await notes.refresh(force: true) } }
            }
            .padding(.bottom, DS.Space.s)
        }
    }

    private func failure(_ message: String) -> some View {
        EmptyState(symbol: "exclamationmark.triangle.fill", tint: .orange, title: "Couldn't read Apple Notes", message: message,
                   actionTitle: "Try Again") { Task { await notes.refresh(force: true) } }
    }
}

private struct NoteRow: View {
    let note: AppleNotesService.Note
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if note.locked { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(Color.secondaryText) }
                Text(note.name.isEmpty ? "Untitled" : note.name).font(DS.body.weight(.semibold)).lineLimit(1)
            }
            Text("\(note.folder) · \(note.modified.formatted(.relative(presentation: .named)))")
                .font(.system(size: 9.5)).foregroundStyle(Color.tertiaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(selected ? 0.12 : 0)))
        .contentShape(Rectangle())
    }
}

/// Preview/edit pane for the selected note, or the composer.
private struct NoteDetailPane: View {
    let folderID: String?
    @Environment(AppleNotesService.self) private var notes
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""
    @State private var preview = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if notes.isComposing {
                header(title: "New Note", subtitle: "Saves to \(targetFolderName)")
                editor
                HStack {
                    statusText
                    Spacer()
                    PillButton(title: "Cancel") { notes.isComposing = false }
                    PillButton(title: "Save to Apple Notes", symbol: "square.and.arrow.down", tint: .yellow, prominent: true) {
                        Task { await notes.create(text: draft, folderID: folderID ?? (settings.notesFolderID.isEmpty ? nil : settings.notesFolderID)) }
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else if let id = notes.selectedID, let note = notes.notes.first(where: { $0.id == id }) {
                header(title: note.name, subtitle: "\(note.folder) · \(note.account)")
                if notes.isLoadingDetail {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let detail = notes.detail, detail.id == id {
                    if let reason = detail.readOnlyReason {
                        IslandScroll(axis: .vertical) {
                            Text(detail.text.isEmpty ? reason : detail.text).font(.system(size: 12)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Label(reason, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(Color.secondaryText)
                    } else {
                        editor
                    }
                }
                HStack {
                    statusText
                    Spacer()
                    PillButton(title: "Open in Notes", symbol: "arrow.up.forward.app") { notes.open(id) }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "note.text").font(.system(size: 20)).foregroundStyle(Color.tertiaryText)
                    Text(notes.notes.isEmpty ? "No notes yet" : "Select a note").font(.system(size: 12, weight: .semibold))
                    if case .ready(let date) = notes.status {
                        Text("Synced \(date.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(Color.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: notes.detail?.id) { _, _ in draft = notes.detail?.text ?? "" }
        .onChange(of: notes.isComposing) { _, composing in if composing { draft = ""; focused = true } }
        .onAppear { draft = notes.isComposing ? "" : notes.detail?.text ?? "" }
        .onDisappear { flush() }
    }

    private var editor: some View {
        Group {
            if preview {
                MarkdownPreview(text: $draft).font(.system(size: 12.5))
            } else {
                TextEditor(text: $draft)
                    .font(.system(size: 12.5))
                    .scrollContentBackground(.hidden)
                    .focused($focused)
            }
        }
        .well(padding: 6)
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: preview ? "pencil" : "eye", size: 9, diameter: 20, help: preview ? "Edit" : "Markdown preview (tick - [ ] tasks)") {
                withAnimation(.snappy) { preview.toggle() }
            }
            .padding(4)
        }
        .onChange(of: draft) { _, _ in scheduleSave() }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.isEmpty ? "Untitled" : title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.tertiaryText).lineLimit(1)
        }
    }

    @ViewBuilder private var statusText: some View {
        switch notes.saveState {
        case .idle: EmptyView()
        case .saving: Label("Saving…", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(Color.secondaryText)
        case .saved: Label("Saved to Apple Notes", systemImage: "checkmark").font(.system(size: 10)).foregroundStyle(.green)
        case .conflict:
            Button { if let id = notes.selectedID { Task { await notes.select(id) } } } label: {
                Label("Changed in Apple Notes. Reload", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plainHit).font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
        case .failed(let m): Label(m, systemImage: "exclamationmark.triangle").font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1)
        }
    }

    private var targetFolderName: String {
        let id = folderID ?? settings.notesFolderID
        return notes.folders.first { $0.id == id }.map { "\($0.name) · \($0.account)" } ?? "your default Notes folder"
    }

    /// Edits are written to Apple Notes after a short pause in typing.
    private func scheduleSave() {
        guard !notes.isComposing, notes.detail?.readOnlyReason == nil else { return }
        saveTask?.cancel()
        let text = draft
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await notes.save(text: text)
        }
    }

    private func flush() {
        guard saveTask != nil, !notes.isComposing else { return }
        saveTask?.cancel()
        let text = draft
        Task { await notes.save(text: text) }
    }
}
