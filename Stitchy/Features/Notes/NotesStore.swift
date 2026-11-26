// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// Quick Notes, saved as JSON in ~/Library/Application Support/Stitchy/notes.json.
@MainActor @Observable
final class NotesStore {
    struct Note: Identifiable, Codable, Equatable {
        var id = UUID()
        var text: String
        var updated = Date()

        var title: String {
            let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return first.isEmpty ? "New Note" : first
        }
    }

    private(set) var notes: [Note] = []
    var selectedID: UUID?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stitchy", isDirectory: true)
        fileURL = dir.appendingPathComponent("notes.json")
        if let data = try? Data(contentsOf: fileURL), let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func search(_ query: String) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sorted = notes.sorted { $0.updated > $1.updated }
        return q.isEmpty ? sorted : sorted.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    @discardableResult
    func create(_ text: String = "") -> Note {
        let note = Note(text: text)
        notes.insert(note, at: 0)
        selectedID = note.id
        scheduleSave()
        return note
    }

    func update(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updated = Date()
        scheduleSave()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        scheduleSave()
    }

    /// Debounced so typing doesn't write on every keystroke.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: fileURL, options: [.atomic])
        } catch {
            islandLog.error("notes save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
