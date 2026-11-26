// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import UniformTypeIdentifiers
import SwiftUI

/// One editor window per extension.
@MainActor
final class ExtensionEditorController {
    private var windows: [UUID: NSWindow] = [:]
    private let services: AppServices

    init(services: AppServices) { self.services = services }

    func open(_ id: UUID) {
        if let w = windows[id] { NSApp.activate(); w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = services.extensions.extensionNamed(id)?.name ?? "Extension"
        w.titlebarAppearsTransparent = true
        w.minSize = NSSize(width: 980, height: 600)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: ExtensionEditorView(id: id).stitchyEnvironment(services))
        w.center()
        windows[id] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows[id] = nil
                self?.services.extensions.saveNow()
            }
        }
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}

struct ExtensionEditorView: View {
    let id: UUID
    @Environment(ExtensionStore.self) private var store
    @Environment(ExtensionDataService.self) private var data
    @State private var draft = StitchyExtension.blank()
    @State private var loaded = false
    @State private var selection: UUID?
    @State private var tab: InspectorTab = .component
    @State private var sample: JSONDoc?
    @State private var fields: JSONField?
    @State private var testing = false
    @State private var testMessage: String?
    @State private var token = ""
    @State private var previewOnly = false
    @State private var iconError: String?

    enum InspectorTab: Hashable { case extensionInfo, data, component, automations }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Divider()
            canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inspector.frame(width: 320)
        }
        .padding(.top, 28)
        .frame(minWidth: 980, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: load)
        .onChange(of: draft) { _, new in if loaded { store.update(new) } }
        .onDeleteCommand { deleteSelected() }
    }

    private func load() {
        guard !loaded, let e = store.extensionNamed(id) else { return }
        draft = e
        token = ExtensionSecrets.token(for: id) ?? ""
        sample = data.entry(id).doc
        fields = sample.map { JSONField.discover($0.root) }
        loaded = true
        if e.dataSource == nil { tab = .data }
    }

    // MARK: Sidebar: library + layers

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Components").padding(.horizontal, 14)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                ForEach(ExtComponent.Kind.allCases) { kind in
                    VStack(spacing: 4) {
                        Image(systemName: kind.symbol).font(.system(size: 15, weight: .medium)).frame(height: 18)
                        Text(kind.title).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
                    .contentShape(Rectangle())
                    .onTapGesture { add(kind) }
                    .draggable("ext-kind:\(kind.rawValue)") {
                        Label(kind.title, systemImage: kind.symbol).padding(8).background(.regularMaterial, in: Capsule())
                    }
                    .help("Click to add, or drag onto the canvas")
                }
            }
            .padding(.horizontal, 12)
            Divider().padding(.vertical, 2)
            SectionLabel("Layers").padding(.horizontal, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) { layerRows(draft.root, depth: 0) }
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 12)
    }

    private func layerRows(_ c: ExtComponent, depth: Int) -> AnyView {
        AnyView(Group {
            LayerRow(component: c, depth: depth, isRoot: c.id == draft.root.id, selected: selection == c.id) { selection = c.id; tab = .component }
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    if c.kind.isContainer { return handleDrop(payload, into: c.id, at: nil) }
                    guard let (parent, index) = draft.root.parent(of: c.id) else { return false }
                    return handleDrop(payload, into: parent, at: index)
                }
            ForEach(c.children) { child in layerRows(child, depth: depth + 1) }
        })
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 10) {
            HStack {
                Text(draft.name).font(.system(size: 15, weight: .semibold))
                if let e = data.entry(id).error, draft.dataSource != nil { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption).lineLimit(1) }
                Spacer()
                Toggle("Preview only", isOn: $previewOnly).toggleStyle(.switch).controlSize(.small)
            }
            .padding(.horizontal, 20)
            ScrollView {
                ExtensionView(ext: draft, doc: sample)
                    .environment(\.extEditor, previewOnly ? nil : ExtEditorHooks(selected: selection, select: { selection = $0; tab = .component },
                                                                                 drop: { handleDrop($0, into: $1, at: nil) }))
                    .padding(18)
                    .frame(width: 460)
                    .frame(minHeight: 220, alignment: .top)
                    .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.black))
                    .environment(\.colorScheme, .dark)
                    .padding(24)
            }
            Text(sample == nil ? "Preview uses your component text until you test the data connection." : "Preview uses the last sample from your API.")
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Extension").tag(InspectorTab.extensionInfo)
                Text("Data").tag(InspectorTab.data)
                Text("Component").tag(InspectorTab.component)
                Image(systemName: "bolt.fill").tag(InspectorTab.automations).help("Automations")
            }
            .pickerStyle(.segmented).labelsHidden().padding(12)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .extensionInfo: extensionForm
                    case .data: dataForm
                    case .component: componentForm
                    case .automations: AutomationsForm(automations: $draft.automations, fields: fields.map { Self.flatten($0.children).filter { $0.kind != .object && $0.kind != .array }.map(\.path) } ?? [], sample: sample)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var extensionForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name") { TextField("Name", text: $draft.name).textFieldStyle(.roundedBorder) }
            field("Description") { TextField("Optional", text: $draft.summary, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder) }
            field("Icon") {
                HStack(spacing: 8) {
                    ExtIcon(ext: draft, size: 18).frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.25)))
                    Button("Choose Image…", action: chooseIconImage)
                    if draft.iconImage != nil { Button("Remove Image") { draft.iconImage = nil } }
                }
                if let iconError { Text(iconError).font(.caption).foregroundStyle(.orange) }
                Text("Use your own logo for trackers (e.g. your payments app). It's saved with this extension.").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                        ForEach(Self.icons, id: \.self) { sym in
                            ExtSymbol(name: sym, size: 13).frame(width: 30, height: 28)
                                .background(RoundedRectangle(cornerRadius: 7).fill(draft.iconImage == nil && draft.icon == sym ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05)))
                                .contentShape(Rectangle())
                                .onTapGesture { draft.icon = sym; draft.iconImage = nil }
                                .help(sym == ExtIconImage.rocket ? "Rocket" : sym)
                        }
                    }
                }
                .frame(height: 190)
                TextField("SF Symbol name", text: $draft.icon).textFieldStyle(.roundedBorder).font(.caption)
            }
            Toggle("Enabled", isOn: $draft.enabled)
            Text("Enabled extensions appear in the island's Extensions tab and refresh their data. Disabled ones never contact their API.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Shown only when the symbol exists on this macOS.
    static let icons: [String] = ([ExtIconImage.rocket] + [
        "puzzlepiece.extension.fill", "chart.line.uptrend.xyaxis", "chart.line.downtrend.xyaxis", "chart.bar.fill", "chart.pie.fill",
        "dollarsign.circle.fill", "bitcoinsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill", "yensign.circle.fill",
        "pesosign.circle.fill", "indianrupeesign.circle.fill", "creditcard.fill", "banknote.fill", "wallet.bifold.fill", "wallet.pass.fill",
        "building.columns.fill", "receipt.fill", "giftcard.fill", "tag.fill", "cart.fill", "bag.fill", "basket.fill", "storefront.fill",
        "shippingbox.fill", "truck.box.fill", "arrow.up.right.circle.fill", "arrow.down.right.circle.fill", "target", "trophy.fill",
        "medal.fill", "crown.fill", "star.fill", "heart.fill", "sparkles", "flame.fill", "bolt.fill", "bell.fill", "flag.fill",
        "cloud.sun.fill", "sun.max.fill", "moon.stars.fill", "snowflake", "drop.fill", "leaf.fill", "pawprint.fill",
        "globe", "server.rack", "cpu", "terminal.fill", "chevron.left.forwardslash.chevron.right", "externaldrive.fill", "icloud.fill",
        "wifi", "antenna.radiowaves.left.and.right", "lock.fill", "key.fill", "shield.lefthalf.filled",
        "person.2.fill", "person.crop.circle.fill", "envelope.fill", "message.fill", "bubble.left.and.bubble.right.fill", "phone.fill",
        "paperplane.fill", "airplane", "airplane.departure", "car.fill", "tram.fill", "bicycle", "fuelpump.fill", "bolt.car.fill",
        "mappin.circle.fill", "location.fill", "house.fill", "clock.fill", "calendar", "hourglass", "timer",
        "gamecontroller.fill", "sportscourt.fill", "figure.run", "dumbbell.fill", "heart.text.square.fill", "pills.fill", "cross.case.fill",
        "fork.knife", "cup.and.saucer.fill", "newspaper.fill", "book.fill", "graduationcap.fill", "brain.head.profile", "atom", "flask.fill",
        "music.note", "headphones", "film.fill", "tv.fill", "play.rectangle.fill", "camera.fill", "photo.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "paintbrush.fill", "lightbulb.fill", "battery.100", "hand.thumbsup.fill",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil })

    private func chooseIconImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe), let png = ExtIconImage.normalized(data) {
            draft.iconImage = png
            iconError = nil
        } else {
            iconError = "Couldn't use that image."
        }
    }

    // MARK: Data

    private var source: Binding<DataSource> {
        Binding(get: { draft.dataSource ?? DataSource() }, set: { draft.dataSource = $0 })
    }

    private var dataForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Address") {
                TextField("https://api.example.com/data", text: source.url).textFieldStyle(.roundedBorder)
                Text("GET requests returning JSON. https only (http only for localhost).").font(.caption).foregroundStyle(.secondary)
            }
            pairs("Query parameters", source.query)
            pairs("Headers", source.headers)
            field("Authentication") {
                Picker("", selection: source.auth) { ForEach(DataSource.Auth.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                if source.wrappedValue.auth == .apiKeyHeader || source.wrappedValue.auth == .apiKeyQuery {
                    TextField(source.wrappedValue.auth == .apiKeyHeader ? "Header name" : "Parameter name", text: source.authName).textFieldStyle(.roundedBorder)
                }
                if source.wrappedValue.auth != .none {
                    SecureField("Token or key", text: $token).textFieldStyle(.roundedBorder)
                        .onChange(of: token) { _, t in ExtensionSecrets.setToken(t, for: id) }
                    Text("Stored in your Keychain. Never saved in the extension file or exported.").font(.caption).foregroundStyle(.secondary)
                }
            }
            extraSourcesForm
            field("Refresh every") {
                Stepper(value: source.refreshSeconds, in: DataSource.minimumRefresh...86_400, step: 30) {
                    Text(Self.interval(source.wrappedValue.refreshSeconds))
                }
            }
            HStack {
                Button(testing ? "Testing…" : "Test Connection") { Task { await test() } }
                    .disabled(testing || source.wrappedValue.url.isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                if let m = testMessage { Text(m).font(.caption).foregroundStyle(m.hasPrefix("✓") ? .green : .orange).lineLimit(2) }
            }
            if let fields {
                Divider()
                SectionLabel("Fields")
                Text("Select a component, then click Bind. Or + to add a component for the field.").font(.caption).foregroundStyle(.secondary)
                FieldTree(field: fields, depth: 0, canBind: selectedBindable, bind: bind, add: addFor)
            }
        }
    }

    private var extraSourcesForm: some View {
        field("More APIs") {
            ForEach($draft.extraSources) { $x in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Text("$").foregroundStyle(.secondary)
                        TextField("name", text: Binding(get: { x.name }, set: { x.name = ExtraSource.cleanName($0) })).textFieldStyle(.roundedBorder).frame(width: 90)
                        Spacer()
                        Button { draft.extraSources.removeAll { $0.id == x.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                    TextField("https://api.example.com/…", text: $x.source.url).textFieldStyle(.roundedBorder)
                    pairs("Query parameters", $x.source.query)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            Button {
                draft.extraSources.append(ExtraSource(name: "api\(draft.extraSources.count + 2)"))
            } label: { Label("Add API", systemImage: "plus") }
            .buttonStyle(.borderless).font(.caption)
            .disabled(draft.extraSources.count >= ExtraSource.maxCount || draft.dataSource == nil)
            Text("Fetched after the first API. Query values can use its fields, like {results[0].pad.latitude}; add |hour or |date for times. Bind to these with $name, e.g. $weather.hourly.cloud_cover[0]. No tokens are sent to extra APIs.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            let (doc, _, extraError) = try await ExtensionFetcher.fetchAll(SourceSet(primary: source.wrappedValue, extras: draft.extraSources),
                                                                         token: token.isEmpty ? nil : token)
            sample = doc
            fields = JSONField.discover(doc.root)
            testMessage = extraError.map { "✓ First API connected. \($0)" } ?? "✓ Connected · \(fields?.children.count ?? 0) top-level fields"
        } catch let f as ExtensionFetcher.Failure {
            testMessage = f.message
        } catch {
            testMessage = error.localizedDescription
        }
    }

    static func interval(_ s: Int) -> String {
        s < 60 ? "\(s) seconds" : s < 3600 ? "\(s / 60) min" : String(format: "%.1f h", Double(s) / 3600)
    }

    // MARK: Component inspector

    private var selected: ExtComponent? { selection.flatMap { draft.root.find($0) } }
    private var selectedBindable: Bool { selected?.kind.takesBinding == true }

    private var selectedBinding: Binding<ExtComponent>? {
        guard let c = selected else { return nil }
        return Binding(get: { draft.root.find(c.id) ?? c }, set: { draft.root.update($0) })
    }

    @ViewBuilder private var componentForm: some View {
        if let b = selectedBinding {
            ComponentInspector(component: b, isRoot: b.wrappedValue.id == draft.root.id, fieldChoices: fieldChoices(for: b.wrappedValue.id),
                               duplicate: duplicateSelected, delete: deleteSelected, move: moveSelected)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing selected").font(.headline)
                Text("Click a component on the canvas or in Layers. Add components from the library on the left.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Fields a component can bind to: item fields inside a list, otherwise every field.
    private func fieldChoices(for id: UUID) -> [(String, String)] {
        guard let fields else { return [] }
        var ancestorList: ExtComponent?
        var current = id
        while let (parent, _) = draft.root.parent(of: current) {
            if let p = draft.root.find(parent), p.kind == .list { ancestorList = p; break }
            current = parent
        }
        if let list = ancestorList, let array = Self.findField(list.binding ?? "", in: fields) {
            return Self.flatten(array.children).compactMap { f in f.itemPath.map { ($0.isEmpty ? "(item)" : $0, f.sample) } }.map { ($0.0 == "(item)" ? "" : $0.0, $0.1) }
        }
        return Self.flatten(fields.children).map { ($0.path, $0.sample) }
    }

    static func flatten(_ fields: [JSONField]) -> [JSONField] {
        fields.flatMap { f in [f] + (f.kind == .object || f.kind == .array ? flatten(f.children) : []) }
    }

    static func findField(_ path: String, in root: JSONField) -> JSONField? {
        if root.path == path { return root }
        for c in root.children { if let f = findField(path, in: c) { return f } }
        return nil
    }

    // MARK: Actions

    private var insertionTarget: UUID {
        guard let s = selected else { return draft.root.id }
        if s.kind.isContainer { return s.id }
        return draft.root.parent(of: s.id)?.0 ?? draft.root.id
    }

    private func add(_ kind: ExtComponent.Kind) {
        let c = ExtComponent(kind: kind)
        draft.root.insert(c, into: insertionTarget)
        selection = c.id
        tab = .component
    }

    private func handleDrop(_ payload: String, into target: UUID, at index: Int?) -> Bool {
        if payload.hasPrefix("ext-kind:"), let kind = ExtComponent.Kind(rawValue: String(payload.dropFirst(9))) {
            let c = ExtComponent(kind: kind)
            guard draft.root.insert(c, into: target, at: index) else { return false }
            selection = c.id
            return true
        }
        if payload.hasPrefix("ext-move:"), let moving = UUID(uuidString: String(payload.dropFirst(9))) {
            guard moving != draft.root.id, let m = draft.root.find(moving), !m.contains(target) else { return false }
            var root = draft.root
            guard let removed = root.remove(moving), root.insert(removed, into: target, at: index) else { return false }
            draft.root = root
            selection = moving
            return true
        }
        return false
    }

    private func bind(_ field: JSONField) {
        guard var c = selected, c.kind.takesBinding else { return }
        c.binding = fieldChoices(for: c.id).contains { $0.0 == (field.itemPath ?? "") } ? field.itemPath : field.path
        draft.root.update(c)
    }

    private func addFor(_ field: JSONField) {
        var c = ExtComponent(kind: field.suggestedComponent)
        let inList = fieldChoices(for: insertionTarget).contains { $0.0 == (field.itemPath ?? "\u{0}") }
        c.binding = inList ? field.itemPath : field.path
        if c.kind == .text || c.kind == .number { c.text = "" }
        if c.kind == .list, let first = field.children.first(where: { $0.kind == .string || $0.kind == .number }) {
            var row = ExtComponent(kind: first.kind == .number ? .number : .text)
            row.binding = first.itemPath
            row.text = ""
            c.children = [row]
        }
        draft.root.insert(c, into: insertionTarget)
        selection = c.id
        tab = .component
    }

    private func duplicateSelected() {
        guard let s = selected, s.id != draft.root.id, let (parent, index) = draft.root.parent(of: s.id) else { return }
        let copy = s.duplicated()
        draft.root.insert(copy, into: parent, at: index + 1)
        selection = copy.id
    }

    private func deleteSelected() {
        guard let s = selected, s.id != draft.root.id else { return }
        _ = draft.root.remove(s.id)
        selection = nil
    }

    private func moveSelected(_ delta: Int) {
        guard let s = selected, let (parent, index) = draft.root.parent(of: s.id) else { return }
        var root = draft.root
        guard let removed = root.remove(s.id) else { return }
        root.insert(removed, into: parent, at: index + delta)
        draft.root = root
    }

    // MARK: Small form helpers

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func pairs(_ title: String, _ list: Binding<[DataSource.Pair]>) -> some View {
        field(title) {
            ForEach(list) { $pair in
                HStack(spacing: 4) {
                    TextField("Name", text: $pair.key).textFieldStyle(.roundedBorder)
                    TextField("Value", text: $pair.value).textFieldStyle(.roundedBorder)
                    Button { list.wrappedValue.removeAll { $0.id == pair.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                }
            }
            Button { list.wrappedValue.append(DataSource.Pair()) } label: { Label("Add", systemImage: "plus") }.buttonStyle(.borderless).font(.caption)
        }
    }
}

/// One row in the Layers list: indented, selectable, draggable.
private struct LayerRow: View {
    let component: ExtComponent
    let depth: Int
    let isRoot: Bool
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isRoot ? "rectangle.on.rectangle" : component.kind.symbol).font(.system(size: 10)).frame(width: 14)
            Text(isRoot ? "Canvas" : label).font(.system(size: 11.5)).lineLimit(1)
            Spacer(minLength: 0)
            if component.style.hidden { Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(.secondary) }
            if let b = component.binding, !b.isEmpty { Image(systemName: "link").font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .padding(.leading, CGFloat(depth) * 12 + 6).padding(.vertical, 4).padding(.trailing, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .modifier(DraggableUnlessRoot(id: component.id, isRoot: isRoot, title: label))
    }

    private var label: String {
        let t = component.text.trimmingCharacters(in: .whitespaces)
        if [.text, .heading, .button].contains(component.kind), !t.isEmpty { return t }
        if let b = component.binding, !b.isEmpty { return "\(component.kind.title) · \(b)" }
        return component.kind.title
    }
}

private struct DraggableUnlessRoot: ViewModifier {
    let id: UUID
    let isRoot: Bool
    let title: String
    func body(content: Content) -> some View {
        if isRoot { content } else { content.draggable("ext-move:\(id.uuidString)") { Text(title).padding(6).background(.regularMaterial, in: Capsule()) } }
    }
}

/// Discovered JSON fields, expandable, with sample values.
private struct FieldTree: View {
    let field: JSONField
    let depth: Int
    let canBind: Bool
    let bind: (JSONField) -> Void
    let add: (JSONField) -> Void
    @State private var open = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(field.children) { f in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if !f.children.isEmpty {
                            Image(systemName: expanded.contains(f.path) ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                                .frame(width: 10).onTapGesture { toggle(f.path) }
                        } else {
                            Color.clear.frame(width: 10)
                        }
                        Text(f.name).font(.system(size: 11.5, weight: .medium))
                        Text(f.kind.rawValue).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4).background(Capsule().fill(Color.primary.opacity(0.08)))
                        Spacer(minLength: 4)
                        Text(f.sample).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 90, alignment: .trailing)
                        if canBind, f.kind != .object { Button("Bind") { bind(f) }.buttonStyle(.borderless).font(.system(size: 10, weight: .semibold)) }
                        if f.kind != .object { Button { add(f) } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless).help("Add a component for this field") }
                    }
                    .padding(.leading, CGFloat(depth) * 12)
                    if expanded.contains(f.path), !f.children.isEmpty {
                        FieldTree(field: f, depth: depth + 1, canBind: canBind, bind: bind, add: add)
                    }
                }
            }
        }
    }

    @State private var expanded: Set<String> = []
    private func toggle(_ p: String) { if expanded.contains(p) { expanded.remove(p) } else { expanded.insert(p) } }
}

/// Settings for the selected component.
private struct ComponentInspector: View {
    @Binding var component: ExtComponent
    let isRoot: Bool
    let fieldChoices: [(String, String)]
    let duplicate: () -> Void
    let delete: () -> Void
    let move: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(isRoot ? "Canvas" : component.kind.title, systemImage: component.kind.symbol).font(.headline)
                Spacer()
                if !isRoot {
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }.help("Move up")
                    Button { move(1) } label: { Image(systemName: "arrow.down") }.help("Move down")
                    Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate")
                    Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }.help("Delete")
                }
            }
            .buttonStyle(.borderless)

            if component.kind.takesBinding { dataSection }
            kindSection
            if component.kind != .button && component.kind != .divider {
                group("Click to open") {
                    TextField("https://… e.g. {link ?? url}", text: $component.linkURL).textFieldStyle(.roundedBorder)
                    Text("https only. {path} inserts a field from the data.").font(.caption).foregroundStyle(.secondary)
                }
            }
            typographySection
            appearanceSection
        }
    }

    private var dataSection: some View {
        group("Data") {
            HStack {
                TextField("Field path, e.g. main.temp", text: Binding(get: { component.binding ?? "" }, set: { component.binding = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                Menu {
                    if fieldChoices.isEmpty { Text("Test the data connection to list fields") }
                    Button("None") { component.binding = nil }
                    ForEach(fieldChoices, id: \.0) { path, sample in
                        Button("\(path.isEmpty ? "(the item itself)" : path)   \(sample)") { component.binding = path }
                    }
                } label: { Image(systemName: "list.bullet") }
                .menuStyle(.borderlessButton).fixedSize()
            }
            if component.kind != .list {
                TextField(component.kind == .text || component.kind == .heading || component.kind == .button ? "Text (use {value} for the field)" : "Shown when the value is missing",
                          text: $component.text).textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder private var kindSection: some View {
        switch component.kind {
        case .container, .list:
            group(component.kind == .list ? "List" : "Layout") {
                Picker("Direction", selection: $component.axis) { ForEach(ExtComponent.Axis.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    .pickerStyle(.segmented)
                if component.axis == .grid { Stepper("Columns: \(component.columns)", value: $component.columns, in: 1...6) }
                if component.kind == .list {
                    Stepper("Show up to \(component.maxItems) items", value: $component.maxItems, in: 1...50)
                    TextField("Newest first by (date path, e.g. pubDate ?? created_at)", text: $component.sortBy).textFieldStyle(.roundedBorder)
                    TextField("Remove duplicates by (e.g. title)", text: $component.dedupeBy).textFieldStyle(.roundedBorder)
                    Text("To merge lists, bind several: Hacker News = $hn.hits, Ars = $ars.rss.channel.item. Each item gets its label as @source.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Shown when the list is empty", text: $component.text).textFieldStyle(.roundedBorder)
                    Text("Components inside the list repeat for each item and read their fields from it.").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .number:
            group("Number") {
                Stepper("Decimals: \(component.decimals)", value: $component.decimals, in: 0...6)
                HStack { TextField("Prefix", text: $component.prefix); TextField("Suffix", text: $component.suffix) }.textFieldStyle(.roundedBorder)
            }
        case .progress, .ring:
            group("Range") {
                HStack { Text("Maximum"); TextField("100", value: $component.maximum, format: .number).textFieldStyle(.roundedBorder) }
                Toggle("Show the remainder (maximum − value)", isOn: $component.invert)
            }
        case .icon:
            group("Icon") { TextField("SF Symbol name", text: $component.symbol).textFieldStyle(.roundedBorder) }
        case .date:
            group("Date") {
                Picker("Format", selection: $component.dateFormat) {
                    Text("Date and time").tag(""); Text("Relative (2 hr. ago)").tag("relative"); Text("Date").tag("date"); Text("Time").tag("time")
                }
            }
        case .chart:
            group("Chart") {
                TextField("Number field in each item (optional)", text: $component.text).textFieldStyle(.roundedBorder)
                Text("Bind a list of numbers, or a list of items plus the number field above.").font(.caption).foregroundStyle(.secondary)
            }
        case .button:
            group("Action") {
                TextField("https://… (use {value})", text: $component.linkURL).textFieldStyle(.roundedBorder)
                Text("Buttons can only open https links.").font(.caption).foregroundStyle(.secondary)
            }
        case .status:
            group("Status colours") {
                ForEach(component.statusColors.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                        colorPicker(Binding(get: { component.statusColors[key] }, set: { component.statusColors[key] = $0 ?? "gray" }), fallback: .gray)
                        Button { component.statusColors[key] = nil } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                StatusAdder { component.statusColors[$0] = "green" }
                Text("Common words like ok, online, error, offline get colours automatically.").font(.caption).foregroundStyle(.secondary)
            }
        default: EmptyView()
        }
    }

    private var typographySection: some View {
        group("Text") {
            Picker("Font", selection: $component.style.design) { ForEach(ExtStyle.Design.allCases) { Text($0.rawValue.capitalized).tag($0) } }
            Picker("Weight", selection: $component.style.weight) { ForEach(ExtStyle.Weight.allCases) { Text($0.rawValue.capitalized).tag($0) } }
            HStack { Text("Size"); Slider(value: $component.style.fontSize, in: 8...64, step: 1); Text("\(Int(component.style.fontSize))").monospacedDigit().frame(width: 26) }
            Picker("Align", selection: $component.style.align) {
                Image(systemName: "text.alignleft").tag(ExtStyle.Align.leading)
                Image(systemName: "text.aligncenter").tag(ExtStyle.Align.center)
                Image(systemName: "text.alignright").tag(ExtStyle.Align.trailing)
            }
            .pickerStyle(.segmented)
            Stepper(component.style.lineLimit.map { "At most \($0) line\($0 == 1 ? "" : "s")" } ?? "Any number of lines",
                    onIncrement: { component.style.lineLimit = min((component.style.lineLimit ?? 0) + 1, 12) },
                    onDecrement: { component.style.lineLimit = (component.style.lineLimit ?? 1) <= 1 ? nil : component.style.lineLimit! - 1 })
            HStack { Text("Text colour"); Spacer(); colorPicker($component.style.textColor, fallback: .white) }
            HStack { Text("Accent"); Spacer(); colorPicker($component.style.accentColor, fallback: .accentColor) }
        }
    }

    private var appearanceSection: some View {
        group("Appearance") {
            HStack { Text("Background"); Spacer(); colorPicker($component.style.background, fallback: .clear) }
            if component.style.background != nil { slider("Opacity", $component.style.backgroundOpacity, 0...1, step: 0.05, format: "%.2f") }
            slider("Padding", $component.style.padding, 0...40)
            slider("Gap", $component.style.spacing, 0...40)
            slider("Corners", $component.style.cornerRadius, 0...40)
            slider("Border", $component.style.borderWidth, 0...6, step: 0.5, format: "%.1f")
            if component.style.borderWidth > 0 { HStack { Text("Border colour"); Spacer(); colorPicker($component.style.borderColor, fallback: .white) } }
            HStack {
                optionalNumber("Width", $component.style.width)
                optionalNumber("Height", $component.style.height)
            }
            if !isRoot { Toggle("Hidden", isOn: $component.style.hidden) }
        }
    }

    // helpers

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title)
            content()
        }
        .controlSize(.small)
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, step: Double = 1, format: String = "%.0f") -> some View {
        HStack { Text(title).frame(width: 60, alignment: .leading); Slider(value: value, in: range, step: step); Text(String(format: format, value.wrappedValue)).monospacedDigit().frame(width: 34) }
    }

    private func optionalNumber(_ title: String, _ value: Binding<Double?>) -> some View {
        HStack(spacing: 4) {
            Text(title)
            TextField("Auto", value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
        }
    }

    /// A colour well bound to an optional hex string; the × resets to the default.
    private func colorPicker(_ hex: Binding<String?>, fallback: Color) -> some View {
        HStack(spacing: 4) {
            ColorPicker("", selection: Binding(get: { ExtColor.color(hex.wrappedValue) ?? fallback }, set: { hex.wrappedValue = ExtColor.hex($0) }))
                .labelsHidden()
            if hex.wrappedValue != nil {
                Button { hex.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("Use default")
            }
        }
    }
}

private struct StatusAdder: View {
    let add: (String) -> Void
    @State private var value = ""
    var body: some View {
        HStack {
            TextField("Value, e.g. delayed", text: $value).textFieldStyle(.roundedBorder)
            Button("Add") { let v = value.trimmingCharacters(in: .whitespaces); if !v.isEmpty { add(v); value = "" } }
        }
    }
}

/// Settings › Extensions: the list of user-made extensions.
struct ExtensionsSettingsView: View {
    @Environment(AppServices.self) private var services
    @Environment(ExtensionStore.self) private var store
    @Environment(ExtensionDataService.self) private var data
    @State private var confirmDelete: StitchyExtension?
    @State private var shareMessage: String?

    var body: some View {
        Form {
            Section {
                if store.extensions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No extensions yet").font(.headline)
                        Text("Build your own island tab from any JSON API: pick components, bind them to fields and style them. No code needed.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                ForEach(store.extensions) { ext in row(ext) }
            } header: {
                Text("Your Extensions")
            } footer: {
                Text("Enabled extensions show in the island's Extensions tab. Tokens stay in your Keychain.")
            }
            Section {
                HStack {
                    Button { services.extensionEditor.open(store.create().id) } label: { Label("New Extension", systemImage: "plus") }
                    Button("Import…", action: importFile)
                }
                if let shareMessage { Text(shareMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .alert("Delete \(confirmDelete?.name ?? "extension")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let e = confirmDelete { store.delete(e.id); data.forget(e.id) }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This removes its layout, cached data and saved token. It can't be undone.")
        }
    }

    private func row(_ ext: StitchyExtension) -> some View {
        HStack(spacing: 10) {
            ExtIcon(ext: ext, size: 14).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(ext.name)
                Text(subtitle(ext)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { ext.enabled }, set: { store.setEnabled(ext.id, $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
            Button("Edit") { services.extensionEditor.open(ext.id) }
            Menu {
                Button("Duplicate") { _ = store.duplicate(ext.id) }
                Button("Export…") { export(ext) }
                if let s = ext.sourceSet, ext.enabled { Button("Refresh Now") { Task { await data.refresh(ext.id, s) } } }
                Divider()
                Button("Delete…", role: .destructive) { confirmDelete = ext }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
    }

    private func export(_ ext: StitchyExtension) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(ext.name).\(ExtensionShare.fileExtension)"
        panel.message = "Tokens, API keys and passwords are left out."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExtensionShare.exportData(ext).write(to: url, options: .atomic)
            shareMessage = "Exported \(ext.name). Tokens and keys were left out."
        } catch {
            shareMessage = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: ExtensionShare.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ExtensionShare.maxImportBytes { throw ExtensionShare.Failure.tooLarge }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let ext = store.add(imported: try ExtensionShare.importData(data))
            shareMessage = "Imported \(ext.name). It's off until you review and enable it; add your own token if it needs one."
        } catch let f as ExtensionShare.Failure {
            shareMessage = f.message
        } catch {
            shareMessage = "Couldn't read that file."
        }
    }

    private func subtitle(_ ext: StitchyExtension) -> String {
        if !ext.summary.isEmpty { return ext.summary }
        if let e = data.entry(ext.id).error { return e }
        guard let host = ext.dataSource.flatMap({ URL(string: $0.url)?.host }) else { return "No data source" }
        return host
    }
}

/// WHEN data updates · IF conditions · THEN alert.
private struct AutomationsForm: View {
    @Binding var automations: [ExtAutomation]
    let fields: [String]
    let sample: JSONDoc?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automations").font(.headline)
            Text("When new data arrives and the conditions match, Stitchy shows an alert. Automations can only notify you: they never open links or change anything.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach($automations) { $a in
                AutomationCard(automation: $a, fields: fields, sample: sample) { automations.removeAll { $0.id == a.id } }
            }
            Button { automations.append(ExtAutomation()) } label: { Label("Add Automation", systemImage: "plus") }
                .disabled(automations.count >= ExtAutomation.maxPerExtension)
        }
    }
}

private struct AutomationCard: View {
    @Binding var automation: ExtAutomation
    let fields: [String]
    let sample: JSONDoc?
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("", isOn: $automation.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                TextField("Name", text: $automation.name).textFieldStyle(.plain).font(.system(size: 12, weight: .semibold))
                Button(role: .destructive, action: delete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            step("WHEN") { Text("the data refreshes").font(.system(size: 11)) }
            step("IF") {
                Picker("", selection: $automation.matchAll) { Text("All match").tag(true); Text("Any matches").tag(false) }
                    .pickerStyle(.segmented).labelsHidden()
                ForEach($automation.conditions) { $c in
                    HStack(spacing: 4) {
                        Menu {
                            if fields.isEmpty { Text("Test the data connection to list fields") }
                            ForEach(fields, id: \.self) { f in Button(f) { c.path = f } }
                        } label: { Text(c.path.isEmpty ? "Field" : c.path).lineLimit(1) }
                        .menuStyle(.borderlessButton).frame(maxWidth: 110)
                        Picker("", selection: $c.op) { ForEach(ExtAutomation.Op.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 84)
                        if c.op.needsValue { TextField("value", text: $c.value).textFieldStyle(.roundedBorder) }
                        Button { automation.conditions.removeAll { $0.id == c.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button { automation.conditions.append(.init()) } label: { Label("Condition", systemImage: "plus") }.buttonStyle(.borderless).font(.caption)
            }
            step("THEN") {
                Picker("", selection: $automation.delivery) { ForEach(ExtAutomation.Delivery.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                TextField("Title, e.g. Price {price}", text: $automation.title).textFieldStyle(.roundedBorder)
                TextField("Message (optional)", text: $automation.message).textFieldStyle(.roundedBorder)
                Stepper("At most every \(automation.cooldownMinutes) min", value: $automation.cooldownMinutes, in: ExtAutomation.minimumCooldown...1440)
            }
            if let sample {
                let now = automation.matches(doc: sample.root, previous: nil)
                Label(now ? "Matches the current sample: \(ExtAutomation.fill(automation.title, doc: sample.root))" : "Doesn't match the current sample",
                      systemImage: now ? "checkmark.circle.fill" : "circle")
                    .font(.caption).foregroundStyle(now ? .green : .secondary).lineLimit(2)
            }
        }
        .controlSize(.small)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func step<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 9.5, weight: .heavy)).tracking(0.8).foregroundStyle(.purple)
            content()
        }
    }
}
