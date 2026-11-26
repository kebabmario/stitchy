// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// WHEN new data arrives, IF conditions match, THEN show an alert.
/// Deliberately limited: automations can only tell the user something.
/// They never open links, run code or change settings.
struct ExtAutomation: Codable, Identifiable, Equatable {
    enum Op: String, Codable, CaseIterable, Identifiable {
        case equals, notEquals, contains, greater, less, isTrue, isFalse, exists, missing, changes
        var id: String { rawValue }
        var title: String {
            switch self {
            case .equals: "is"
            case .notEquals: "is not"
            case .contains: "contains"
            case .greater: "is above"
            case .less: "is below"
            case .isTrue: "is true"
            case .isFalse: "is false"
            case .exists: "exists"
            case .missing: "is missing"
            case .changes: "changes"
            }
        }
        var needsValue: Bool { [.equals, .notEquals, .contains, .greater, .less].contains(self) }
    }

    struct Condition: Codable, Identifiable, Equatable {
        var id = UUID()
        var path = ""
        var op: Op = .changes
        var value = ""
    }

    enum Delivery: String, Codable, CaseIterable, Identifiable {
        case island, islandAndNotification
        var id: String { rawValue }
        var title: String { self == .island ? "Island alert" : "Island alert + notification" }
    }

    static let maxPerExtension = 10
    static let minimumCooldown = 1

    var id = UUID()
    var name = "New Automation"
    var enabled = true
    var conditions: [Condition] = [Condition()]
    /// All conditions (true) or any of them (false).
    var matchAll = true
    var delivery: Delivery = .island
    /// `{field.path}` inserts a value from the data.
    var title = "Update"
    var message = ""
    /// Minutes between alerts from this automation.
    var cooldownMinutes = 15

    // MARK: Evaluation (pure)

    static func holds(_ c: Condition, doc: Any?, previous: Any?) -> Bool {
        let v = JSONPath.value(c.path, in: doc)
        let s = JSONPath.string(v)
        switch c.op {
        case .exists: return v != nil && !(v is NSNull)
        case .missing: return v == nil || v is NSNull
        case .isTrue: return (v as? Bool) == true || s?.lowercased() == "true"
        case .isFalse: return (v as? Bool) == false || s?.lowercased() == "false"
        case .equals, .notEquals:
            let equal: Bool
            if let a = JSONPath.number(v), let b = Double(c.value) { equal = a == b } else { equal = s?.lowercased() == c.value.lowercased() }
            return c.op == .equals ? equal : !equal
        case .contains: return s?.localizedCaseInsensitiveContains(c.value) == true
        case .greater, .less:
            guard let a = JSONPath.number(v), let b = Double(c.value) else { return false }
            return c.op == .greater ? a > b : a < b
        case .changes:
            guard let previous else { return false }
            return JSONPath.string(JSONPath.value(c.path, in: previous)) != s
        }
    }

    func matches(doc: Any?, previous: Any?) -> Bool {
        let active = conditions.filter { !$0.path.isEmpty }
        guard !active.isEmpty else { return false }
        return matchAll ? active.allSatisfy { Self.holds($0, doc: doc, previous: previous) }
                        : active.contains { Self.holds($0, doc: doc, previous: previous) }
    }

    /// Replaces `{path}` with values from the data (length-capped).
    static func fill(_ template: String, doc: Any?) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let path = String(rest[rest.index(after: open)..<close])
            out += JSONPath.string(JSONPath.value(path, in: doc)).map { String($0.prefix(120)) } ?? "–"
            rest = rest[rest.index(after: close)...]
        }
        return String((out + rest).prefix(300))
    }
}

/// Runs automations when an extension's data updates.
/// Edge-triggered: an automation fires when its conditions become true,
/// not on every refresh while they stay true, and then waits its cooldown.
@MainActor
final class ExtensionAutomationEngine {
    struct Alert: Equatable { var extensionID: UUID; var automationID: UUID; var title: String; var message: String; var notify: Bool }

    private var previous: [UUID: JSONDoc] = [:]
    private var wasTrue: [UUID: Bool] = [:]
    private var lastFired: [UUID: Date] = [:]
    var onAlert: ((Alert, StitchyExtension) -> Void)?

    /// Returns the alerts it raised (also passed to `onAlert`).
    @discardableResult
    func evaluate(_ ext: StitchyExtension, doc: JSONDoc, now: Date = Date()) -> [Alert] {
        defer { previous[ext.id] = doc }
        guard ext.enabled else { return [] }
        // The first data after launch only sets the baseline, so restarting Stitchy doesn't repeat alerts.
        guard let prior = previous[ext.id] else {
            for a in ext.automations { wasTrue[a.id] = a.matches(doc: doc.root, previous: nil) }
            return []
        }
        var raised: [Alert] = []
        for a in ext.automations.prefix(ExtAutomation.maxPerExtension) where a.enabled {
            let now_ = a.matches(doc: doc.root, previous: prior.root)
            defer { wasTrue[a.id] = now_ }
            let changeOnly = a.conditions.contains { $0.op == .changes }
            guard now_, changeOnly || wasTrue[a.id] != true else { continue }
            let cooldown = TimeInterval(max(a.cooldownMinutes, ExtAutomation.minimumCooldown) * 60)
            if let last = lastFired[a.id], now.timeIntervalSince(last) < cooldown { continue }
            lastFired[a.id] = now
            let alert = Alert(extensionID: ext.id, automationID: a.id,
                              title: ExtAutomation.fill(a.title, doc: doc.root).isEmpty ? ext.name : ExtAutomation.fill(a.title, doc: doc.root),
                              message: ExtAutomation.fill(a.message, doc: doc.root), notify: a.delivery == .islandAndNotification)
            raised.append(alert)
            onAlert?(alert, ext)
        }
        return raised
    }

    func forget(_ id: UUID) { previous[id] = nil }
}
