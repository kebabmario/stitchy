// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

/// Parsed JSON passed around read-only. `Any` from JSONSerialization isn't
/// Sendable; this box is only ever read after creation.
struct JSONDoc: @unchecked Sendable {
    let root: Any
}

/// "main.temp", "items[2].title", "[0].name": dot-separated keys with [index].
enum JSONPath {
    enum Segment: Equatable { case key(String), index(Int) }

    static func segments(_ path: String) -> [Segment] {
        var out: [Segment] = []
        for part in path.split(separator: ".", omittingEmptySubsequences: true) {
            var rest = Substring(part)
            if let b = rest.firstIndex(of: "[") {
                let key = rest[..<b]
                if !key.isEmpty { out.append(.key(String(key))) }
                rest = rest[b...]
                while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                    if let n = Int(rest[rest.index(after: rest.startIndex)..<close]) { out.append(.index(n)) }
                    rest = rest[rest.index(after: close)...]
                }
            } else {
                out.append(.key(String(rest)))
            }
        }
        return out
    }

    /// The value at `path`, or nil when missing. An empty path is the root.
    static func value(_ path: String?, in root: Any?) -> Any? {
        guard let root else { return nil }
        guard let path, !path.isEmpty else { return root }
        // "a ?? b": the first path that has a value (e.g. RSS `pubDate ?? updated`).
        if path.contains("??") {
            for part in path.components(separatedBy: "??") {
                let p = part.trimmingCharacters(in: .whitespaces)
                if !p.isEmpty, let v = value(segments(p), in: root) { return v }
            }
            return nil
        }
        return value(segments(path), in: root)
    }

    static func value(_ segs: [Segment], in root: Any?) -> Any? {
        guard var current = root else { return nil }
        if let combo = current as? ExtSources {
            if case .key(let k)? = segs.first, k.hasPrefix("$") { return value(Array(segs.dropFirst()), in: combo.extras[String(k.dropFirst())]) }
            return value(segs, in: combo.primary)
        }
        for seg in segs {
            switch seg {
            case .key(let k):
                guard let d = current as? [String: Any], let v = d[k] else { return nil }
                current = v
            case .index(let i):
                guard let a = current as? [Any], a.indices.contains(i) else { return nil }
                current = a[i]
            }
        }
        return current is NSNull ? nil : current
    }

    /// A display string for a JSON value (numbers without trailing .0).
    static func string(_ value: Any?) -> String? {
        switch value {
        case nil: return nil
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            return d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : String(d)
        case let a as [Any]: return "\(a.count) items"
        case let d as [String: Any]: return (d["#text"] as? String) ?? "{…}"
        default: return "\(value!)"
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): return n.doubleValue
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    /// ISO 8601 strings or Unix seconds/milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let n = number(value) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
        guard let s = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: s) { return d }
        return rfc822(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// RSS dates: "Wed, 25 Nov 2026 12:00:28 +0000" (also "GMT"/"EST", or no weekday).
    private static func rfc822(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

/// One discovered field in a sample response.
struct JSONField: Identifiable, Equatable {
    enum Kind: String { case string, number, bool, object, array, null }

    var id: String { path }
    /// Absolute path from the response root (arrays use their first item: "items[0].name").
    let path: String
    /// Path inside one array item, for list children ("name").
    let itemPath: String?
    let name: String
    let kind: Kind
    let sample: String
    var count: Int?
    var children: [JSONField]

    /// Walks the JSON (depth- and size-limited) and lists every field with a sample value.
    static func discover(_ value: Any, path: String = "", itemPath: String? = nil, name: String = "Response", depth: Int = 0) -> JSONField {
        let kind: Kind
        var children: [JSONField] = []
        var count: Int?
        switch value {
        case let combo as ExtSources:
            kind = .object
            let first = discover(combo.primary, path: path, itemPath: itemPath, name: name, depth: depth)
            children = (first.kind == .object ? first.children : [first])
                + combo.extras.keys.sorted().map { discover(combo.extras[$0]!, path: "$\($0)", name: "$\($0)", depth: depth + 1) }
        case let d as [String: Any]:
            kind = .object
            if depth < 8 {
                children = d.keys.sorted().prefix(200).map { key in
                    discover(d[key]!, path: path.isEmpty ? key : "\(path).\(key)",
                             itemPath: itemPath.map { $0.isEmpty ? key : "\($0).\(key)" }, name: key, depth: depth + 1)
                }
            }
        case let a as [Any]:
            kind = .array
            count = a.count
            // The first item stands for all items; its fields carry item-relative paths for lists.
            if let first = a.first, depth < 8 {
                let item = discover(first, path: "\(path)[0]", itemPath: "", name: "Each item", depth: depth + 1)
                children = item.kind == .object ? item.children : [item]
            }
        case let n as NSNumber:
            kind = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool : .number
        case is String: kind = .string
        default: kind = .null
        }
        let sample = kind == .object ? "\(children.count) fields" : kind == .array ? "\(count ?? 0) items" : (JSONPath.string(value) ?? "null")
        return JSONField(path: path, itemPath: itemPath, name: name, kind: kind, sample: String(sample.prefix(80)), count: count, children: children)
    }

    /// The component that best shows this field.
    var suggestedComponent: ExtComponent.Kind {
        switch kind {
        case .array: return .list
        case .bool: return .status
        case .number: return .number
        case .string:
            let s = sample.lowercased()
            if s.hasPrefix("https://"), [".png", ".jpg", ".jpeg", ".gif", ".webp", "image"].contains(where: s.contains) { return .image }
            if JSONPath.date(sample) != nil, sample.count >= 10 { return .date }
            return .text
        default: return .text
        }
    }
}

/// Fetches extension data safely: HTTPS only (HTTP only for this Mac), a
/// timeout, a response-size limit, no cookies or shared cache, and secrets
/// from the Keychain. Never logs headers, tokens or response bodies.
enum ExtensionFetcher {
    static let maxBytes = 2_000_000
    static let timeout: TimeInterval = 15

    enum Failure: Error, Equatable {
        case invalidURL(String), http(Int), tooLarge, notJSON, network(String), rateLimited(TimeInterval?)
        var message: String {
            switch self {
            case .invalidURL(let m): m
            case .http(let code): "The server answered \(code)."
            case .tooLarge: "The response is larger than 2 MB."
            case .notJSON: "The response isn't JSON or a feed (RSS/Atom/XML)."
            case .network(let m): m
            case .rateLimited: "Too many requests. Stitchy will wait before trying again."
            }
        }
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = timeout
        c.timeoutIntervalForResource = timeout * 2
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.httpShouldSetCookies = false
        return URLSession(configuration: c)
    }()

    /// Builds the request. Rejects anything but https (or http to localhost).
    static func request(for source: DataSource, token: String?) throws -> URLRequest {
        let raw = source.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: raw), let scheme = comps.scheme?.lowercased(), let host = comps.host, !host.isEmpty else {
            throw Failure.invalidURL("Enter a full address starting with https://")
        }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && local) else {
            throw Failure.invalidURL("Only https:// addresses are allowed (http only for localhost).")
        }
        var items = comps.queryItems ?? []
        items += source.query.filter { !$0.key.isEmpty }.map { URLQueryItem(name: $0.key, value: $0.value) }
        if source.auth == .apiKeyQuery, let token, !source.authName.isEmpty { items.append(URLQueryItem(name: source.authName, value: token)) }
        comps.queryItems = items.isEmpty ? nil : items
        guard let url = comps.url else { throw Failure.invalidURL("That address isn't valid.") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "GET"   // version 1: read-only GET requests
        req.setValue("application/json, application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.8", forHTTPHeaderField: "Accept")
        req.setValue("Stitchy", forHTTPHeaderField: "User-Agent")
        for h in source.headers where !h.key.isEmpty { req.setValue(h.value, forHTTPHeaderField: h.key) }
        switch source.auth {
        case .bearer: if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        case .apiKeyHeader: if let token, !source.authName.isEmpty { req.setValue(token, forHTTPHeaderField: source.authName) }
        default: break
        }
        return req
    }

    static func fetch(_ source: DataSource, token: String?) async throws -> (JSONDoc, Data) {
        let req = try request(for: source, token: token)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw Failure.network((error as NSError).localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 {
                throw Failure.rateLimited((http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init))
            }
            guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        }
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        return (try parse(data), data)
    }

    static func parse(_ data: Data) throws -> JSONDoc {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        if let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return JSONDoc(root: ExtSources.from(cache: root))
        }
        // RSS / Atom / other XML.
        if let root = ExtXML.parse(data) {
            return JSONDoc(root: root)
        }
        throw Failure.notJSON
    }
}

/// Live data for enabled extensions: polls each one at its own interval
/// (never under 30 s, longer after errors or rate limits), caches the last
/// good response on disk, and stops polling disabled or deleted extensions.
@MainActor @Observable
final class ExtensionDataService {
    struct Entry {
        var doc: JSONDoc?
        var updated: Date?
        var error: String?
        var loading = false
    }

    private(set) var entries: [UUID: Entry] = [:]
    @ObservationIgnored private var pollers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sources: [UUID: SourceSet] = [:]
    @ObservationIgnored private let cacheDir: URL

    init(cacheDirectory: URL? = nil) {
        cacheDir = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stitchy/extensions", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func entry(_ id: UUID) -> Entry { entries[id] ?? Entry() }

    /// Starts, restarts or stops polling so it matches the enabled extensions.
    func sync(with extensions: [StitchyExtension]) {
        let wanted = Dictionary(uniqueKeysWithValues: extensions.compactMap { e in e.enabled ? e.sourceSet.map { (e.id, $0) } : nil })
        for id in pollers.keys where wanted[id] == nil {
            pollers[id]?.cancel()
            pollers[id] = nil
            sources[id] = nil
        }
        for (id, source) in wanted where sources[id] != source {
            pollers[id]?.cancel()
            sources[id] = source
            if entries[id]?.doc == nil, let cached = loadCache(id) { entries[id, default: Entry()].doc = cached.0; entries[id, default: Entry()].updated = cached.1 }
            pollers[id] = Task { [weak self] in await self?.poll(id, source) }
        }
    }

    func stopAll() {
        pollers.values.forEach { $0.cancel() }
        pollers.removeAll()
        sources.removeAll()
    }

    private func poll(_ id: UUID, _ set: SourceSet) async {
        let source = set.primary
        // Settle first so typing an address in the editor doesn't fire a request per keystroke.
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        var delay = TimeInterval(max(source.refreshSeconds, DataSource.minimumRefresh))
        // Use a fresh-enough cache instead of fetching again at launch.
        if let updated = entries[id]?.updated, Date().timeIntervalSince(updated) < delay {
            try? await Task.sleep(for: .seconds(delay - Date().timeIntervalSince(updated)))
        }
        while !Task.isCancelled {
            let backoff = await refresh(id, set)
            delay = backoff ?? TimeInterval(max(source.refreshSeconds, DataSource.minimumRefresh))
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Fetches now. Returns a longer wait after failures (nil when it worked).
    @discardableResult
    func refresh(_ id: UUID, _ set: SourceSet) async -> TimeInterval? {
        let source = set.primary
        guard entries[id]?.loading != true else { return nil }
        entries[id, default: Entry()].loading = true
        defer { entries[id, default: Entry()].loading = false }
        do {
            let (doc, data, extraError) = try await ExtensionFetcher.fetchAll(set, token: ExtensionSecrets.token(for: id))
            entries[id, default: Entry()].doc = doc
            entries[id, default: Entry()].updated = Date()
            entries[id, default: Entry()].error = extraError
            failures[id] = 0
            saveCache(id, data)
            onUpdate?(id, doc)
            return nil
        } catch let f as ExtensionFetcher.Failure {
            entries[id, default: Entry()].error = f.message
            failures[id, default: 0] += 1
            if case .rateLimited(let after) = f { return max(after ?? 0, 300) }
            return min(TimeInterval(max(source.refreshSeconds, DataSource.minimumRefresh)) * pow(2, Double(min(failures[id] ?? 1, 6))), 1800)
        } catch {
            entries[id, default: Entry()].error = error.localizedDescription
            return 600
        }
    }

    /// Called after every successful update (automations will hook in here).
    @ObservationIgnored var onUpdate: ((UUID, JSONDoc) -> Void)?
    @ObservationIgnored private var failures: [UUID: Int] = [:]

    private func cacheURL(_ id: UUID) -> URL { cacheDir.appendingPathComponent("\(id.uuidString).json") }

    private func saveCache(_ id: UUID, _ data: Data) { try? data.write(to: cacheURL(id), options: .atomic) }

    private func loadCache(_ id: UUID) -> (JSONDoc, Date)? {
        let url = cacheURL(id)
        guard let data = try? Data(contentsOf: url), let doc = try? ExtensionFetcher.parse(data),
              let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        return (doc, date)
    }

    func forget(_ id: UUID) {
        pollers[id]?.cancel()
        pollers[id] = nil
        sources[id] = nil
        entries[id] = nil
        try? FileManager.default.removeItem(at: cacheURL(id))
    }
}
