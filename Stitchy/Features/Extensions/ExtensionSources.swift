// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A second (third, …) API for an extension. Its query values may use
/// `{path}` from earlier responses, e.g. a latitude from the first API.
/// Paths into its response start with `$name`, e.g. `$weather.hourly.cloud_cover[0]`.
struct ExtraSource: Codable, Equatable, Identifiable {
    var id = UUID()
    var name = "api2"
    var source = DataSource()

    static let maxCount = 12

    /// Letters, digits and _ only, so `$name.field` paths stay unambiguous.
    static func cleanName(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(20))
    }
}

/// The first response plus the named extra responses.
struct ExtSources: @unchecked Sendable {
    let primary: Any
    let extras: [String: Any]

    static let primaryKey = "$stitchyPrimary", extrasKey = "$stitchyExtras"

    var cacheObject: [String: Any] { [Self.primaryKey: primary, Self.extrasKey: extras] }

    static func from(cache object: Any) -> Any {
        guard let d = object as? [String: Any], let p = d[primaryKey] else { return object }
        return ExtSources(primary: p, extras: d[extrasKey] as? [String: Any] ?? [:])
    }
}

/// Everything an extension fetches, compared to restart polling when it changes.
struct SourceSet: Equatable {
    var primary: DataSource
    var extras: [ExtraSource] = []
}

extension StitchyExtension {
    var sourceSet: SourceSet? { dataSource.map { SourceSet(primary: $0, extras: extraSources) } }
}

/// `{path}` templates for request URLs and links.
/// `{@now}` is the current time. Filters (dates are UTC):
/// `|hour` → `2026-11-27T08:00`, `|date` → `2026-11-27`, `|unix` → seconds,
/// and `|date-7` / `|unix-2` go that many days back.
enum ExtTemplate {
    /// Nil when a referenced value is missing, or fails `allowed`.
    static func resolve(_ template: String, root: Any?, now: Date = Date(), allowed: (String) -> Bool = { _ in true }) -> String? {
        guard template.contains("{") else { return template }
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let inner = rest[rest.index(after: open)..<close].split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let path = inner.first ?? ""
            let raw = path == "@now" ? ISO8601DateFormatter().string(from: now) : JSONPath.string(JSONPath.value(path, in: root))
            guard let raw else { return nil }
            let filled = inner.count > 1 ? apply(inner[1], to: raw) : raw
            guard let filled, allowed(filled) else { return nil }
            out += filled
            rest = rest[rest.index(after: close)...]
        }
        return String((out + rest).prefix(2000))
    }

    static func apply(_ filter: String, to value: String) -> String? {
        guard var d = JSONPath.date(value) else { return nil }
        let parts = filter.split(separator: "-", maxSplits: 1)
        if parts.count == 2 { guard let days = Double(parts[1]) else { return nil }; d -= days * 86_400 }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        switch parts.first.map(String.init) {
        case "hour": f.dateFormat = "yyyy-MM-dd'T'HH:00"
        case "date": f.dateFormat = "yyyy-MM-dd"
        case "unix": return String(Int(d.timeIntervalSince1970))
        default: return nil
        }
        return f.string(from: d)
    }

    /// Values allowed in a URL path: one safe segment, no `/`, `..` or `@`.
    static func isPathSafe(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && s != "." && s != ".." && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) }
    }

    /// Fills `{…}` in a URL's path only. The scheme and host must be written out,
    /// so data can never choose where a request goes.
    static func resolveURL(_ url: String, root: Any?, now: Date = Date()) -> String? {
        guard url.contains("{") else { return url }
        guard let scheme = url.range(of: "://"), let slash = url[scheme.upperBound...].firstIndex(of: "/"),
              !url[..<slash].contains("{") else { return nil }
        return resolve(String(url[slash...]), root: root, now: now, allowed: isPathSafe).map { String(url[..<slash]) + $0 }
    }
}

extension ExtensionFetcher {
    /// The first API (its failure fails the update), then each extra in order.
    /// Extras never get the Keychain token, and templates only fill query values,
    /// so data from one API can't choose which host the next request goes to.
    static func fetchAll(_ set: SourceSet, token: String?) async throws -> (doc: JSONDoc, cache: Data, extraError: String?) {
        // The first API can use {@now} in its query (nothing else exists yet).
        var primary = set.primary
        primary.query = try primary.query.map { p in
            var q = p
            guard let v = ExtTemplate.resolve(p.value, root: nil) else { throw Failure.invalidURL("\(p.key): only {@now} can be used in the first API") }
            q.value = v
            return q
        }
        let (doc, data) = try await fetch(primary, token: token)
        guard !set.extras.isEmpty else { return (doc, data, nil) }
        var extras: [String: Any] = [:]
        var errors: [String] = []
        for x in set.extras.prefix(ExtraSource.maxCount) where !x.name.isEmpty {
            var s = x.source
            s.auth = .none
            var missing = false
            let scope = ExtSources(primary: doc.root, extras: extras)
            s.query = s.query.map { p in
                var q = p
                if let v = ExtTemplate.resolve(p.value, root: scope) { q.value = v } else { missing = true }
                return q
            }
            if let url = ExtTemplate.resolveURL(s.url, root: scope) { s.url = url } else { missing = true }
            if missing { errors.append("\(x.name): waiting for a value it uses"); continue }
            do {
                extras[x.name] = try await fetch(s, token: nil).0.root
            } catch let f as Failure {
                errors.append("\(x.name): \(f.message)")
            } catch {
                errors.append("\(x.name): \(error.localizedDescription)")
            }
        }
        let combined = ExtSources(primary: doc.root, extras: extras)
        let cache = (try? JSONSerialization.data(withJSONObject: combined.cacheObject, options: [.fragmentsAllowed])) ?? data
        return (JSONDoc(root: combined), cache, errors.isEmpty ? nil : errors.joined(separator: " · "))
    }
}
