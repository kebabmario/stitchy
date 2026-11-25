import SwiftUI

/// Searchable command interface: launcher items, Stitchy actions, apps.
struct LauncherView: View {
    @Environment(Launcher.self) private var launcher
    @Environment(IslandModel.self) private var model
    @State private var query = ""
    @State private var selection = 0

    var body: some View {
        let results = launcher.search(query)
        VStack(spacing: 8) {
            SearchField(text: $query, prompt: "Search apps, folders, shortcuts and actions", focusToken: model.focusSearchToken) {
                run(results)
            }
            .onKeyPress(.downArrow) { selection = min(selection + 1, max(results.count - 1, 0)); return .handled }
            .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
            .onChange(of: query) { _, _ in selection = 0 }
            IslandScroll(axis: .vertical) {
                VStack(spacing: 1) {
                    ForEach(Array(results.prefix(30).enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, highlighted: index == selection)
                            .onTapGesture { selection = index; run(results) }
                    }
                    if results.isEmpty {
                        Text("No matches").font(.system(size: 11)).foregroundStyle(Color.tertiaryText).padding(.top, 20)
                    }
                }
            }
            HStack {
                if let error = launcher.lastError {
                    Text(error).foregroundStyle(.red.opacity(0.8))
                } else {
                    Text("Add apps, folders and Shortcuts in Settings › Launcher.")
                }
                Spacer()
                Text("↩ open  ·  ↑↓ choose  ·  type 12*7 or todo …").foregroundStyle(Color.tertiaryText)
            }
            .font(DS.caption).foregroundStyle(Color.tertiaryText)
        }
    }

    private func run(_ results: [Launcher.Result]) {
        guard results.indices.contains(selection) else { return }
        let result = results[selection]
        launcher.run(result)
        if case .action = result { return }
        model.collapse()
    }
}

private struct ResultRow: View {
    let result: Launcher.Result
    let highlighted: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            icon.frame(width: 22, height: 22)
            Text(title).font(DS.body).lineLimit(1)
            Spacer()
            Text(kind).font(DS.caption).foregroundStyle(Color.tertiaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(highlighted ? 0.13 : hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var title: String {
        switch result {
        case .item(let i): i.name
        case .action(let a): a.title
        case .app(let u): u.deletingPathExtension().lastPathComponent
        }
    }

    private var kind: String {
        switch result {
        case .item(let i): i.kind == .shortcut ? "Shortcut" : i.kind == .folder ? "Folder" : "App"
        case .action: "Stitchy"
        case .app: "App"
        }
    }

    @ViewBuilder private var icon: some View {
        switch result {
        case .item(let i) where i.kind != .shortcut:
            Image(nsImage: NSWorkspace.shared.icon(forFile: i.target)).resizable()
        case .item:
            CardIconView(icon: .symbol("square.2.layers.3d.fill", .pink), size: 22)
        case .action(let a):
            CardIconView(icon: .symbol(a.symbol, a.id == "calc" ? .orange : .indigo), size: 22)
        case .app(let u):
            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path)).resizable()
        }
    }
}
