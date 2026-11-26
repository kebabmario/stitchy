// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

/// Editor hooks; nil at runtime (then nothing is selectable or droppable).
struct ExtEditorHooks: @unchecked Sendable {   // used on the main thread only
    var selected: UUID?
    var select: (UUID) -> Void
    var drop: (String, UUID) -> Bool   // payload, target container
}

private struct ExtEditorKey: EnvironmentKey { static let defaultValue: ExtEditorHooks? = nil }
extension EnvironmentValues {
    var extEditor: ExtEditorHooks? {
        get { self[ExtEditorKey.self] }
        set { self[ExtEditorKey.self] = newValue }
    }
}

/// Draws one component (and its children) from data. `scope` is the JSON the
/// component's binding is read from: the response root, or one list item.
struct ExtComponentView: View {
    let component: ExtComponent
    let scope: Any?
    @Environment(\.extEditor) private var editor

    private var value: Any? {
        guard let b = component.binding, !b.isEmpty else { return nil }
        return JSONPath.value(b, in: scope)
    }

    /// Bound value as text, through the `{value}` template or the fallback text.
    private var resolvedText: String {
        let v = JSONPath.string(value)
        if component.text.contains("{value}") { return component.text.replacingOccurrences(of: "{value}", with: v ?? "–") }
        // Button labels stay as written; the binding feeds the link.
        if component.kind == .button { return component.text.isEmpty ? (v ?? "Open") : component.text }
        return v ?? component.text
    }

    var body: some View {
        if (component.style.hidden || isEmptyAtRuntime), editor == nil {
            EmptyView()
        } else {
            content
                .modifier(ExtStyleModifier(style: component.style, kind: component.kind))
                .modifier(LinkModifier(url: editor == nil && component.kind != .button ? link : nil))
                .opacity(component.style.hidden ? 0.35 : 1)
                .modifier(SelectableModifier(component: component))
        }
    }

    /// A bound text, date, status or image whose value is missing and that has
    /// no fallback text disappears instead of showing a placeholder.
    private var isEmptyAtRuntime: Bool {
        guard let b = component.binding, !b.isEmpty else { return false }
        // A bound button with nothing to link to has nothing to do.
        if component.kind == .button { return JSONPath.string(value) == nil }
        guard [.text, .heading, .date, .status, .image, .number].contains(component.kind) else { return false }
        let missing = component.kind == .image ? Self.imageURL(JSONPath.string(value)) == nil : (JSONPath.string(value) ?? "").isEmpty
        // "{value} points" hides too: its words only make sense with the value.
        return missing && (component.text.contains("{value}") || component.text.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private var link: URL? {
        component.linkURL.isEmpty ? nil : Self.linkURL(component.linkURL, value: JSONPath.string(value), scope: scope)
    }

    @ViewBuilder private var content: some View {
        let s = component.style
        let accent = ExtColor.color(s.accentColor) ?? .accentColor
        switch component.kind {
        case .text, .heading:
            Text(resolvedText).multilineTextAlignment(s.align.text)
        case .number:
            if let n = JSONPath.number(value) {
                Text(component.prefix + n.formatted(.number.precision(.fractionLength(component.decimals))) + component.suffix)
            } else {
                Text(component.text.isEmpty ? "–" : component.text)
            }
        case .date:
            if let d = JSONPath.date(value) {
                switch component.dateFormat {
                case "relative": TimelineView(.periodic(from: .timelineAnchor, by: 60)) { ctx in Text(Self.relative(d, now: ctx.date)) }
                case "date": Text(d, format: .dateTime.day().month(.abbreviated).year())
                case "time": Text(d, format: .dateTime.hour().minute())
                default: Text(d, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                }
            } else {
                Text(resolvedText)
            }
        case .countdown:
            if let d = JSONPath.date(value) {
                TimelineView(.periodic(from: .timelineAnchor, by: 1)) { ctx in Text(Self.countdown(to: d, now: ctx.date)) }
            } else {
                Text(component.text.isEmpty ? "–" : component.text)
            }
        case .progress:
            let f = fraction
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.2))
                    Capsule().fill(accent).frame(width: g.size.width * f)
                }
            }
            .frame(height: max(4, s.h ?? 6))
        case .ring:
            ZStack {
                ProgressRing(fraction: fraction, color: accent, lineWidth: 4)
                Text(JSONPath.number(value) == nil ? (component.text.isEmpty ? "–" : component.text) : "\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .frame(width: s.w ?? 44, height: s.w ?? 44)
        case .status:
            let label = JSONPath.string(value) ?? component.text
            HStack(spacing: 6) {
                Circle().fill(statusColor(label)).frame(width: 8, height: 8)
                Text(label.isEmpty ? "–" : label)
            }
        case .image:
            if let url = Self.imageURL(JSONPath.string(value) ?? component.text) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().aspectRatio(contentMode: .fill) }
                    else { Rectangle().fill(.white.opacity(0.06)).overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3))) }
                }
                .frame(width: s.w, height: s.h ?? 80)
                .frame(maxWidth: s.w == nil ? .infinity : nil)
                .clipShape(RoundedRectangle(cornerRadius: CGFloat(s.cornerRadius), style: .continuous))
            } else {
                Rectangle().fill(.white.opacity(0.06)).frame(height: s.h ?? 80)
                    .overlay(Image(systemName: "photo").foregroundStyle(.white.opacity(0.3)))
            }
        case .icon:
            Image(systemName: NSImage(systemSymbolName: component.symbol, accessibilityDescription: nil) == nil ? "questionmark.square" : component.symbol)
                .foregroundStyle(accent)
        case .chart:
            ExtChart(values: chartValues, color: accent).frame(height: s.h ?? 60)
        case .button:
            Button {
                if let url = Self.linkURL(component.linkURL, value: JSONPath.string(value), scope: scope) { NSWorkspace.shared.open(url) }
            } label: {
                Text(resolvedText).padding(.horizontal, 12).frame(height: 26)
                    .background(Capsule().fill(accent.opacity(0.9)))
                    .foregroundStyle(.black)
            }
            .buttonStyle(PressableStyle())
            .disabled(editor != nil)
        case .divider:
            Rectangle().fill(ExtColor.color(s.borderColor) ?? .white.opacity(0.15)).frame(height: max(1, CGFloat(s.borderWidth)))
        case .container:
            ExtContainer(component: component, items: component.children.map { ($0, scope) })
        case .list:
            let items = Self.listRows(component, scope: scope)
            if items.isEmpty, editor == nil {
                Text(component.text.isEmpty ? "Nothing to show" : component.text).foregroundStyle(.white.opacity(0.5))
            } else {
                // Each item repeats the list's children, reading from that item.
                let template = component.children
                let rows: [Any?] = items.isEmpty ? [nil] : items.map { $0 }
                ExtListContent(list: component, template: template, rows: rows)
            }
        }
    }

    private var fraction: Double {
        guard let n = JSONPath.number(value), component.maximum > 0 else { return 0 }
        let f = min(max(n / component.maximum, 0), 1)
        return component.invert ? 1 - f : f
    }

    private var chartValues: [Double] {
        guard let array = value as? [Any] else { return [] }
        let key = component.text
        return array.compactMap { JSONPath.number($0) ?? JSONPath.number(JSONPath.value(key, in: $0)) }
    }

    private func statusColor(_ label: String) -> Color {
        if let mapped = component.statusColors.first(where: { $0.key.caseInsensitiveCompare(label) == .orderedSame }) {
            return ExtColor.color(mapped.value) ?? .gray
        }
        switch label.lowercased() {
        case "true", "ok", "up", "online", "active", "success", "passed", "open": return .green
        case "false", "down", "offline", "error", "failed", "closed": return .red
        case "warning", "degraded", "pending": return .orange
        default: return ExtColor.color(component.style.accentColor) ?? .gray
        }
    }

    // MARK: Helpers (pure, tested)

    static func countdown(to date: Date, now: Date) -> String {
        let s = Int(date.timeIntervalSince(now).rounded(.down))
        guard s > 0 else { return "Now" }
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h" }
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Only https images.
    static func imageURL(_ s: String?) -> URL? {
        guard let s, let url = URL(string: s.trimmingCharacters(in: .whitespaces)), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// Links open https only. `{value}` inserts the bound value (percent-encoded);
    /// other `{path}`s insert fields from the data as written (e.g. `{link ?? url}`).
    nonisolated static func linkURL(_ template: String, value: String?, scope: Any? = nil) -> URL? {
        let encoded = value?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var s = template.contains("{value}") ? template.replacingOccurrences(of: "{value}", with: encoded) : (template.isEmpty ? (value ?? "") : template)
        if s.contains("{") { guard let filled = ExtTemplate.resolve(s, root: scope) else { return nil }; s = filled }
        guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    static func relative(_ d: Date, now: Date) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 && s > -60 { return "now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: now)
    }

    /// Items for a list. The binding may name several arrays to merge,
    /// "Label = path, Label = path"; each item then carries its label as `@source`.
    /// A single object counts as a one-item list (feeds with one entry).
    nonisolated static func listRows(_ list: ExtComponent, scope: Any?) -> [Any] {
        let parts = (list.binding ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let merging = parts.count > 1 || parts.first?.contains("=") == true
        var rows: [Any] = []
        for part in parts {
            let pieces = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let (label, path) = pieces.count == 2 ? (pieces[0], pieces[1]) : (part, part)
            let v = JSONPath.value(path, in: scope)
            let items: [Any] = v as? [Any] ?? (v is [String: Any] ? [v!] : [])
            rows += merging ? items.map { item in
                guard var d = item as? [String: Any] else { return item }
                d["@source"] = label
                return d
            } : items
        }
        if !list.sortBy.isEmpty {
            let keyed = rows.map { (JSONPath.date(JSONPath.value(list.sortBy, in: $0)), $0) }
            rows = keyed.enumerated().sorted { a, b in
                switch (a.element.0, b.element.0) {
                case let (x?, y?): return x != y ? x > y : a.offset < b.offset
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.offset < b.offset
                }
            }.map(\.element.1)
        }
        if !list.dedupeBy.isEmpty {
            var seen = Set<String>()
            rows = rows.filter { item in
                guard let raw = JSONPath.string(JSONPath.value(list.dedupeBy, in: item)) else { return true }
                let key = String(raw.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
                return key.isEmpty || seen.insert(key).inserted
            }
        }
        return Array(rows.prefix(max(1, list.maxItems)))
    }
}

/// Lays out children vertically, horizontally or in a grid.
struct ExtContainer: View {
    let component: ExtComponent
    let items: [(ExtComponent, Any?)]
    @Environment(\.extEditor) private var editor

    var body: some View {
        let s = component.style
        Group {
            switch component.axis {
            case .vertical:
                VStack(alignment: s.align.horizontal, spacing: s.spacing) { children }
            case .horizontal:
                HStack(alignment: .center, spacing: s.spacing) { children }
            case .grid:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: s.spacing), count: max(1, min(component.columns, 6))),
                          alignment: s.align.horizontal, spacing: s.spacing) { children }
            }
        }
        .frame(maxWidth: .infinity, alignment: s.align.frame)
        .overlay {
            if editor != nil, items.isEmpty {
                Text(component.kind == .list ? "Drop components for each item" : "Drop components here")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.white.opacity(0.2)))
            }
        }
        .frame(minHeight: editor != nil && items.isEmpty ? 36 : nil)
        .modifier(ContainerDrop(target: component.id))
    }

    @ViewBuilder private var children: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, pair in ExtComponentView(component: pair.0, scope: pair.1) }
    }
}

/// A list's rows: every item gets the list's children, laid out by the list's axis.
private struct ExtListContent: View {
    let list: ExtComponent
    let template: [ExtComponent]
    let rows: [Any?]

    var body: some View {
        let s = list.style
        let row: (Any?) -> AnyView = { item in
            AnyView(VStack(alignment: s.align.horizontal, spacing: max(2, s.spacing / 2)) {
                ForEach(template) { ExtComponentView(component: $0, scope: item) }
            })
        }
        Group {
            switch list.axis {
            case .vertical: VStack(alignment: s.align.horizontal, spacing: s.spacing) { ForEach(rows.indices, id: \.self) { row(rows[$0]) } }
            case .horizontal: HStack(spacing: s.spacing) { ForEach(rows.indices, id: \.self) { row(rows[$0]) } }
            case .grid:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: s.spacing), count: max(1, min(list.columns, 6))), spacing: s.spacing) {
                    ForEach(rows.indices, id: \.self) { row(rows[$0]) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: s.align.frame)
        .overlay {
            if template.isEmpty {
                Text("Drop components for each item").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(.white.opacity(0.2)))
            }
        }
        .modifier(ContainerDrop(target: list.id))
    }
}

/// Fonts, colours, spacing, borders and size from the component's style.
private struct ExtStyleModifier: ViewModifier {
    let style: ExtStyle
    let kind: ExtComponent.Kind

    func body(content: Content) -> some View {
        let fixedWidth: CGFloat? = kind == .image || kind == .ring ? nil : style.w
        let fixedHeight: CGFloat? = [.image, .progress, .chart, .ring].contains(kind) ? nil : style.h
        // A sized image keeps its width; otherwise it would take half of a row.
        let stretch = kind.isContainer || [.progress, .chart, .divider].contains(kind) || (kind == .image && style.w == nil)
        let radius = CGFloat(style.cornerRadius)
        return content
            .font(.system(size: CGFloat(style.fontSize), weight: style.weight.font, design: style.design.font))
            .lineLimit(style.lineLimit)
            .foregroundStyle(ExtColor.color(style.textColor) ?? .white)
            .frame(width: fixedWidth, height: fixedHeight)
            .frame(maxWidth: stretch ? .infinity : nil, alignment: style.align.frame)
            .padding(CGFloat(style.padding))
            .background {
                if let bg = ExtColor.color(style.background) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(bg.opacity(style.backgroundOpacity))
                }
            }
            .overlay {
                if style.borderWidth > 0, kind != .divider {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(ExtColor.color(style.borderColor) ?? .white.opacity(0.2), lineWidth: CGFloat(style.borderWidth))
                }
            }
    }
}

/// Makes any component open a link when clicked, with a light hover response.
private struct LinkModifier: ViewModifier {
    let url: URL?
    @State private var hovering = false

    func body(content: Content) -> some View {
        if let url {
            content
                .contentShape(Rectangle())
                .opacity(hovering ? 0.75 : 1)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .onTapGesture { NSWorkspace.shared.open(url) }
                .help(url.host ?? url.absoluteString)
        } else {
            content
        }
    }
}

/// In the editor: click to select, outline the selection.
private struct SelectableModifier: ViewModifier {
    let component: ExtComponent
    @Environment(\.extEditor) private var editor

    func body(content: Content) -> some View {
        if let editor {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(editor.selected == component.id ? Color.accentColor : .clear, lineWidth: 1.5)
                        .padding(-3)
                }
                .contentShape(Rectangle())
                .onTapGesture { editor.select(component.id) }
        } else {
            content
        }
    }
}

/// In the editor, containers accept library items and moved components.
private struct ContainerDrop: ViewModifier {
    let target: UUID
    @Environment(\.extEditor) private var editor
    @State private var targeted = false

    func body(content: Content) -> some View {
        if let editor {
            content
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(targeted ? 0.15 : 0)).padding(-4))
                .dropDestination(for: String.self) { items, _ in
                    items.first.map { editor.drop($0, target) } ?? false
                } isTargeted: { targeted = $0 }
        } else {
            content
        }
    }
}

/// A small line chart for numeric arrays.
struct ExtChart: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { g in
            if values.count > 1, let lo = values.min(), let hi = values.max() {
                let span = max(hi - lo, 0.0001)
                let pts = values.enumerated().map { i, v in
                    CGPoint(x: g.size.width * CGFloat(i) / CGFloat(values.count - 1), y: g.size.height * (1 - CGFloat((v - lo) / span)))
                }
                ZStack {
                    Path { p in p.move(to: CGPoint(x: 0, y: g.size.height)); pts.forEach { p.addLine(to: $0) }; p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)) }
                        .fill(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.05))
                    .overlay(Text("Bind a list of numbers").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)))
            }
        }
    }
}

/// A whole extension, as it appears in the island and in the editor preview.
struct ExtensionView: View {
    let ext: StitchyExtension
    let doc: JSONDoc?

    var body: some View {
        ExtComponentView(component: ext.root, scope: doc?.root)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
