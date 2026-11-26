// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The island's Extensions tab: enabled user extensions, one at a time.
struct ExtensionsTabView: View {
    @Environment(ExtensionStore.self) private var store
    @Environment(ExtensionDataService.self) private var data
    @AppStorage("extensions.selected") private var selectedID = ""

    private var enabled: [StitchyExtension] { store.extensions.filter(\.enabled) }
    private var current: StitchyExtension? { enabled.first { $0.id.uuidString == selectedID } ?? enabled.first }

    var body: some View {
        if let ext = current {
            VStack(alignment: .leading, spacing: 8) {
                header(ext)
                IslandScroll(axis: .vertical) {
                    ExtensionView(ext: ext, doc: data.entry(ext.id).doc)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            EmptyState(symbol: "puzzlepiece.extension.fill", tint: .purple, title: "No extensions",
                       message: "Create one in Settings › Extensions.")
        }
    }

    private func header(_ ext: StitchyExtension) -> some View {
        let entry = data.entry(ext.id)
        return HStack(spacing: 6) {
            if enabled.count > 1 {
                ForEach(enabled) { e in
                    Button { selectedID = e.id.uuidString } label: {
                        HStack(spacing: 4) {
                            ExtIcon(ext: e, size: 10)
                            if e.id == ext.id { Text(e.name).font(.system(size: 11, weight: .semibold)).lineLimit(1) }
                        }
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Capsule().fill(.white.opacity(e.id == ext.id ? 0.18 : 0.07)))
                    }
                    .buttonStyle(.plainHit)
                }
            } else {
                HStack(spacing: 5) { ExtIcon(ext: ext, size: 10); Text(ext.name) }.font(DS.label).foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 4)
            if let error = entry.error {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 10)).help(error)
            }
            if let updated = entry.updated {
                Text(updated, style: .relative).font(DS.caption).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            if let source = ext.sourceSet {
                Button { Task { await data.refresh(ext.id, source) } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(entry.loading ? 180 : 0)).animation(.easeInOut, value: entry.loading)
                }
                .buttonStyle(.plainHit).disabled(entry.loading).help("Refresh")
            }
        }
    }
}
