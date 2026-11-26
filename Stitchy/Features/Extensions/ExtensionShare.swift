// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Export and import of extensions as `.stitchyext` JSON files.
/// Exports never contain tokens (they live in the Keychain), sensitive
/// header or query values, or URL credentials. Imports arrive turned off
/// with automations off, so nothing from a shared file runs until the
/// user has looked at it.
enum ExtensionShare {
    static let fileExtension = "stitchyext"
    static let maxImportBytes = 1_000_000
    static let maxComponents = 500

    struct Package: Codable {
        var stitchyExtensionPackage = 1
        var exported = Date()
        var `extension`: StitchyExtension
    }

    enum Failure: Error, Equatable {
        case tooLarge, unreadable, newerVersion, tooComplex
        var message: String {
            switch self {
            case .tooLarge: "That file is too large to be a Stitchy extension."
            case .unreadable: "That file isn't a Stitchy extension."
            case .newerVersion: "That extension was made with a newer Stitchy. Update Stitchy to import it."
            case .tooComplex: "That extension has too many components."
            }
        }
    }

    private static let sensitive = ["auth", "token", "key", "secret", "password", "passwd", "cookie", "session", "signature", "credential", "bearer"]

    static func isSensitive(_ name: String) -> Bool {
        let n = name.lowercased()
        return sensitive.contains { n.contains($0) }
    }

    /// A copy that is safe to give to someone else.
    static func sanitized(_ ext: StitchyExtension) -> StitchyExtension {
        var e = ext
        e.extraSources = e.extraSources.prefix(ExtraSource.maxCount).map { x in
            var y = x
            y.name = ExtraSource.cleanName(x.name)
            y.source = sanitized(source: x.source)
            return y
        }
        e.dataSource = e.dataSource.map(sanitized(source:))
        return e
    }

    static func sanitized(source: DataSource) -> DataSource {
        var s = source
        s.headers = s.headers.map { var p = $0; if isSensitive(p.key) { p.value = "" }; return p }
        s.query = s.query.map { var p = $0; if isSensitive(p.key) { p.value = "" }; return p }
        // Rebuild the address only when there's something to strip: rebuilding
        // percent-encodes `{path}` templates and would break them.
        if var c = URLComponents(string: s.url),
           c.user != nil || c.password != nil || c.queryItems?.contains(where: { isSensitive($0.name) && !($0.value ?? "").isEmpty }) == true {
            c.user = nil
            c.password = nil
            c.queryItems = c.queryItems?.map { isSensitive($0.name) ? URLQueryItem(name: $0.name, value: "") : $0 }
            s.url = c.string ?? s.url
        }
        return s
    }

    static func exportData(_ ext: StitchyExtension) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(Package(extension: sanitized(ext)))
    }

    static func importData(_ data: Data) throws -> StitchyExtension {
        guard data.count <= maxImportBytes else { throw Failure.tooLarge }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let pkg = try? dec.decode(Package.self, from: data) else { throw Failure.unreadable }
        var e = pkg.extension
        guard e.formatVersion <= StitchyExtension.formatVersion, pkg.stitchyExtensionPackage <= 1 else { throw Failure.newerVersion }
        guard e.root.count <= maxComponents, e.root.kind == .container else { throw Failure.tooComplex }
        e = sanitized(e)
        e.formatVersion = StitchyExtension.formatVersion
        e.id = UUID()
        e.name = String(e.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)).isEmpty ? "Imported Extension" : String(e.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        e.enabled = false
        e.automations = e.automations.prefix(ExtAutomation.maxPerExtension).map { var a = $0; a.id = UUID(); a.enabled = false; return a }
        e.root = e.root.duplicated()
        // Only keep an icon that decodes as an image; re-encode it.
        e.iconImage = e.iconImage.flatMap(ExtIconImage.normalized)
        e.created = Date()
        e.modified = Date()
        return e
    }
}
