// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import Security

/// Saves extensions to `~/Library/Application Support/Stitchy/extensions.json`
/// as a versioned envelope, so future format changes can migrate old files.
@MainActor @Observable
final class ExtensionStore {
    struct Envelope: Codable {
        var formatVersion: Int
        var extensions: [StitchyExtension]
    }

    private(set) var extensions: [StitchyExtension] = []
    private(set) var loadError: String?
    @ObservationIgnored private let file: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stitchy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent("extensions.json")
        load()
    }

    var enabled: [StitchyExtension] { extensions.filter(\.enabled) }

    func extensionNamed(_ id: UUID) -> StitchyExtension? { extensions.first { $0.id == id } }

    // MARK: Editing

    @discardableResult
    func create() -> StitchyExtension {
        let ext = StitchyExtension.blank(named: uniqueName("Untitled Extension"))
        extensions.append(ext)
        scheduleSave()
        return ext
    }

    func update(_ ext: StitchyExtension) {
        guard let i = extensions.firstIndex(where: { $0.id == ext.id }) else { return }
        var e = ext
        e.modified = Date()
        extensions[i] = e
        scheduleSave()
    }

    @discardableResult
    func duplicate(_ id: UUID) -> StitchyExtension? {
        guard let original = extensionNamed(id) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.name = uniqueName(original.name + " Copy")
        copy.root = original.root.duplicated()
        copy.automations = original.automations.map { var a = $0; a.id = UUID(); return a }
        copy.created = Date()
        copy.modified = Date()
        extensions.append(copy)
        ExtensionSecrets.copy(from: original.id, to: copy.id)
        scheduleSave()
        return copy
    }

    /// Adds an imported extension (already sanitised by `ExtensionShare`).
    @discardableResult
    func add(imported ext: StitchyExtension) -> StitchyExtension {
        var e = ext
        e.name = uniqueName(ext.name)
        extensions.append(e)
        scheduleSave()
        return e
    }

    func delete(_ id: UUID) {
        extensions.removeAll { $0.id == id }
        ExtensionSecrets.delete(id)
        scheduleSave()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = extensions.firstIndex(where: { $0.id == id }) else { return }
        extensions[i].enabled = on
        scheduleSave()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(extensions.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            let envelope = try JSONDecoder.extensions.decode(Envelope.self, from: data)
            extensions = Self.migrate(envelope).extensions
        } catch {
            // Keep the unreadable file for recovery instead of overwriting it.
            loadError = "Couldn't read your extensions. The file was kept as extensions.unreadable.json."
            try? FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent("extensions.unreadable.json"))
        }
    }

    /// Upgrades older envelopes. Version 2 added automations (decoded with defaults).
    nonisolated static func migrate(_ envelope: Envelope) -> Envelope {
        var e = envelope
        e.extensions = e.extensions.map { ext in var x = ext; x.formatVersion = StitchyExtension.formatVersion; return x }
        e.formatVersion = StitchyExtension.formatVersion
        return e
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        let envelope = Envelope(formatVersion: StitchyExtension.formatVersion, extensions: extensions)
        guard let data = try? JSONEncoder.extensions.encode(envelope) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

extension JSONEncoder {
    static var extensions: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var extensions: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// API tokens for extensions, in the login Keychain (never in the JSON file, logs or exports).
enum ExtensionSecrets {
    private static let service = "app.stitchy.extensions"

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }

    static func token(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?, for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var item = query(id)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecAttrLabel as String] = "Stitchy extension token"
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }

    static func copy(from: UUID, to: UUID) { if let t = token(for: from) { setToken(t, for: to) } }
}
