// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SwiftUI

/// A user-made Stitchy extension: an optional JSON data source, a tree of
/// visual components and their appearance. Pure data: nothing in here can
/// run code, touch files or control Stitchy.
struct StitchyExtension: Codable, Identifiable, Equatable {
    /// Bump when the format changes; `ExtensionStore` migrates older files.
    static let formatVersion = 2

    var formatVersion = Self.formatVersion
    var id = UUID()
    var name: String
    var icon: String = "puzzlepiece.extension.fill"
    /// The user's own icon image (square PNG, at most 200 KB). Wins over `icon`.
    var iconImage: Data?
    var summary: String = ""
    var enabled = true
    var dataSource: DataSource?
    /// More APIs, fetched after `dataSource` (see `ExtraSource`).
    var extraSources: [ExtraSource] = []
    /// Always a container; the canvas.
    var root = ExtComponent(kind: .container)
    var automations: [ExtAutomation] = []
    var created = Date()
    var modified = Date()

    static func blank(named name: String = "Untitled Extension") -> StitchyExtension {
        StitchyExtension(name: name)
    }

    init(name: String) { self.name = name }

    /// Fields added after format 1 decode with defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? icon
        iconImage = try c.decodeIfPresent(Data.self, forKey: .iconImage)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        dataSource = try c.decodeIfPresent(DataSource.self, forKey: .dataSource)
        extraSources = try c.decodeIfPresent([ExtraSource].self, forKey: .extraSources) ?? []
        root = try c.decode(ExtComponent.self, forKey: .root)
        automations = try c.decodeIfPresent([ExtAutomation].self, forKey: .automations) ?? []
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date()
        modified = try c.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }
}

/// A generic HTTP GET returning JSON. Secrets (tokens) are not stored here:
/// they live in the Keychain (`ExtensionSecrets`) and are never exported.
struct DataSource: Codable, Equatable {
    struct Pair: Codable, Equatable, Identifiable {
        var id = UUID()
        var key = ""
        var value = ""
    }

    enum Auth: String, Codable, CaseIterable, Identifiable {
        case none, bearer, apiKeyHeader, apiKeyQuery
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: "None"
            case .bearer: "Bearer token"
            case .apiKeyHeader: "API key (header)"
            case .apiKeyQuery: "API key (query)"
            }
        }
    }

    var url = ""
    var method = "GET"
    var query: [Pair] = []
    var headers: [Pair] = []
    var auth: Auth = .none
    /// Header or query parameter name for API-key auth.
    var authName = "X-API-Key"
    /// Seconds; never below `minimumRefresh`.
    var refreshSeconds = 300

    static let minimumRefresh = 30
}

/// One visual component. Containers hold children; a list repeats its
/// children for every item of the array it's bound to (child bindings are
/// then relative to the item).
struct ExtComponent: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case text, heading, image, icon, number, date, countdown, progress, ring, status, list, chart, button, divider, container
        var id: String { rawValue }

        var title: String {
            switch self {
            case .ring: "Progress Ring"
            case .progress: "Progress Bar"
            case .status: "Status"
            default: rawValue.capitalized
            }
        }

        var symbol: String {
            switch self {
            case .text: "text.alignleft"
            case .heading: "textformat.size"
            case .image: "photo"
            case .icon: "star.square"
            case .number: "number"
            case .date: "calendar"
            case .countdown: "timer"
            case .progress: "chart.bar.fill"
            case .ring: "circle.dashed"
            case .status: "circle.fill"
            case .list: "list.bullet"
            case .chart: "chart.xyaxis.line"
            case .button: "button.horizontal"
            case .divider: "minus"
            case .container: "square.dashed"
            }
        }

        var isContainer: Bool { self == .container || self == .list }
        /// Kinds that show a bound value.
        var takesBinding: Bool { ![.divider, .container, .icon].contains(self) }
    }

    enum Axis: String, Codable, CaseIterable, Identifiable {
        case vertical, horizontal, grid
        var id: String { rawValue }
    }

    var id = UUID()
    var kind: Kind
    /// JSON path into the data ("main.temp", "items[0].title"); relative to the item inside a list.
    var binding: String?
    /// Static text, or the fallback when the bound value is missing. `{value}` inserts the value.
    var text = ""
    var symbol = "star.fill"
    var style = ExtStyle()
    var children: [ExtComponent] = []
    // Container / list
    var axis: Axis = .vertical
    var columns = 2
    var maxItems = 5
    // Number
    var decimals = 0
    var prefix = ""
    var suffix = ""
    // Progress / ring
    var maximum: Double = 100
    // Status: value → colour name ("green", "red", "#FF9500")
    var statusColors: [String: String] = [:]
    // Button: open a URL (https only), possibly from a binding
    var linkURL = ""
    // Progress / ring: show maximum − value (e.g. 100 − rain chance).
    var invert = false
    // List: newest first by this date path (e.g. "pubDate ?? created_at"); drop items whose path repeats.
    var sortBy = ""
    var dedupeBy = ""
    // Date: "" full, "relative" (2 hr. ago), "date", "time".
    var dateFormat = ""

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .heading: text = "Heading"; style.fontSize = 20; style.weight = .bold
        case .text: text = "Text"
        case .number: text = "–"; style.fontSize = 28; style.weight = .semibold; style.design = .rounded
        case .button: text = "Open"
        case .container: style.padding = 0
        case .list: maxItems = 5
        default: break
        }
    }

    /// Every field but `id` and `kind` is optional, so files from older Stitchy versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExtComponent(kind: try c.decode(Kind.self, forKey: .kind))
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = d.kind
        binding = try c.decodeIfPresent(String.self, forKey: .binding)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? d.text
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? d.symbol
        style = try c.decodeIfPresent(ExtStyle.self, forKey: .style) ?? d.style
        children = try c.decodeIfPresent([ExtComponent].self, forKey: .children) ?? []
        axis = try c.decodeIfPresent(Axis.self, forKey: .axis) ?? d.axis
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? d.columns
        maxItems = try c.decodeIfPresent(Int.self, forKey: .maxItems) ?? d.maxItems
        decimals = try c.decodeIfPresent(Int.self, forKey: .decimals) ?? d.decimals
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        maximum = try c.decodeIfPresent(Double.self, forKey: .maximum) ?? d.maximum
        statusColors = try c.decodeIfPresent([String: String].self, forKey: .statusColors) ?? [:]
        linkURL = try c.decodeIfPresent(String.self, forKey: .linkURL) ?? ""
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
        sortBy = try c.decodeIfPresent(String.self, forKey: .sortBy) ?? ""
        dedupeBy = try c.decodeIfPresent(String.self, forKey: .dedupeBy) ?? ""
        dateFormat = try c.decodeIfPresent(String.self, forKey: .dateFormat) ?? ""
    }

    /// Finds a component anywhere in the tree.
    func find(_ id: UUID) -> ExtComponent? {
        if self.id == id { return self }
        for c in children { if let f = c.find(id) { return f } }
        return nil
    }

    /// Replaces the component with the same id. Returns whether it was found.
    @discardableResult
    mutating func update(_ component: ExtComponent) -> Bool {
        if id == component.id { self = component; return true }
        for i in children.indices where children[i].update(component) { return true }
        return false
    }

    /// Removes and returns a component from anywhere below this one.
    mutating func remove(_ id: UUID) -> ExtComponent? {
        if let i = children.firstIndex(where: { $0.id == id }) { return children.remove(at: i) }
        for i in children.indices { if let r = children[i].remove(id) { return r } }
        return nil
    }

    /// Inserts into the container `parent` at `index` (clamped). Returns false if `parent` isn't a container here.
    @discardableResult
    mutating func insert(_ component: ExtComponent, into parent: UUID, at index: Int? = nil) -> Bool {
        if id == parent, kind.isContainer {
            children.insert(component, at: min(max(index ?? children.count, 0), children.count))
            return true
        }
        for i in children.indices where children[i].insert(component, into: parent, at: index) { return true }
        return false
    }

    /// The container holding `id`, and its index there.
    func parent(of id: UUID) -> (UUID, Int)? {
        if let i = children.firstIndex(where: { $0.id == id }) { return (self.id, i) }
        for c in children { if let p = c.parent(of: id) { return p } }
        return nil
    }

    /// Whether `id` is this component or inside it (to refuse moving a container into itself).
    func contains(_ id: UUID) -> Bool { find(id) != nil }

    /// A copy with fresh ids throughout (for Duplicate).
    func duplicated() -> ExtComponent {
        var copy = self
        copy.id = UUID()
        copy.children = children.map { $0.duplicated() }
        return copy
    }

    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }
}

struct ExtStyle: Codable, Equatable {
    enum Design: String, Codable, CaseIterable, Identifiable {
        case standard, rounded, serif, monospaced
        var id: String { rawValue }
        var font: Font.Design {
            switch self {
            case .standard: .default
            case .rounded: .rounded
            case .serif: .serif
            case .monospaced: .monospaced
            }
        }
    }

    enum Weight: String, Codable, CaseIterable, Identifiable {
        case regular, medium, semibold, bold, heavy
        var id: String { rawValue }
        var font: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .heavy: .heavy
            }
        }
    }

    enum Align: String, Codable, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: String { rawValue }
        var horizontal: HorizontalAlignment { self == .leading ? .leading : self == .center ? .center : .trailing }
        var frame: Alignment { self == .leading ? .leading : self == .center ? .center : .trailing }
        var text: TextAlignment { self == .leading ? .leading : self == .center ? .center : .trailing }
    }

    var design: Design = .standard
    var fontSize: Double = 13
    var weight: Weight = .regular
    var align: Align = .leading
    /// Hex colours ("#RRGGBB"); nil = Stitchy default.
    var textColor: String?
    var accentColor: String?
    var background: String?
    var backgroundOpacity: Double = 1
    var borderColor: String?
    var borderWidth: Double = 0
    var cornerRadius: Double = 10
    var padding: Double = 0
    var spacing: Double = 8
    var width: Double?
    var height: Double?
    var hidden = false
    /// Text: at most this many lines (nil = no limit).
    var lineLimit: Int?

    var w: CGFloat? { width.map { CGFloat($0) } }
    var h: CGFloat? { height.map { CGFloat($0) } }

    init() {}

    /// Every field optional, so older files keep loading as styles grow.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ExtStyle()
        design = try c.decodeIfPresent(Design.self, forKey: .design) ?? d.design
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        weight = try c.decodeIfPresent(Weight.self, forKey: .weight) ?? d.weight
        align = try c.decodeIfPresent(Align.self, forKey: .align) ?? d.align
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor)
        background = try c.decodeIfPresent(String.self, forKey: .background)
        backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? d.backgroundOpacity
        borderColor = try c.decodeIfPresent(String.self, forKey: .borderColor)
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? d.borderWidth
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? d.padding
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? d.spacing
        width = try c.decodeIfPresent(Double.self, forKey: .width)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        lineLimit = try c.decodeIfPresent(Int.self, forKey: .lineLimit)
    }
}

/// Colours from names or hex, used by styles and status mappings.
enum ExtColor {
    static let named: [String: Color] = ["red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "mint": .mint,
                                         "teal": .teal, "blue": .blue, "indigo": .indigo, "purple": .purple, "pink": .pink,
                                         "gray": .gray, "white": .white, "black": .black]

    static func color(_ value: String?) -> Color? {
        guard let v = value?.trimmingCharacters(in: .whitespaces).lowercased(), !v.isEmpty else { return nil }
        if let c = named[v] { return c }
        var hex = v.hasPrefix("#") ? String(v.dropFirst()) : v
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((n >> 16) & 0xff) / 255, green: Double((n >> 8) & 0xff) / 255, blue: Double(n & 0xff) / 255)
    }

    static func hex(_ color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
