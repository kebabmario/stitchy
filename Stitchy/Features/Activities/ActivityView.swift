import SwiftUI

/// Activity page: what's live, then notifications as one quiet list, then
/// short suggestions for features that are off.
struct ActivityView: View {
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(ActivityFeed.self) private var feed
    @Environment(AppSettings.self) private var settings
    @Environment(AIUsageMonitor.self) private var ai

    var body: some View {
        IslandScroll(axis: .vertical) {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if !downloads.downloads.isEmpty || settings.aiUsageEnabled {
                    HStack {
                        SectionLabel("Live")
                        Spacer()
                        if downloads.downloads.contains(where: { !$0.isActive }) {
                            Chip(title: "Clear Finished") { withAnimation(.snappy) { downloads.clearFinished() } }
                        }
                    }
                    if settings.downloadsEnabled, !downloads.accessDenied {
                        ForEach(downloads.downloads) { DownloadCard(download: $0) }
                    }
                    if settings.aiUsageEnabled { AIUsageSection() }
                }

                HStack {
                    SectionLabel("Notifications")
                    Spacer()
                    if !feed.items.isEmpty { Chip(title: "Clear") { withAnimation(.snappy) { feed.clear() } } }
                }
                .padding(.top, 2)
                if feed.items.isEmpty {
                    Text("Nothing yet. Timers, downloads, devices, builds and power changes appear here.")
                        .font(DS.caption).foregroundStyle(Color.tertiaryText)
                } else {
                    VStack(spacing: 0) {
                        ForEach(feed.items) { event in
                            NotificationRow(event: event)
                            if event.id != feed.items.last?.id {
                                Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 40)
                            }
                        }
                    }
                    .well(padding: 4)
                }

                suggestions
            }
        }
        .onAppear { feed.markRead() }
    }

    @ViewBuilder private var suggestions: some View {
        let showDownloads = !settings.downloadsEnabled || downloads.accessDenied
        if showDownloads || !settings.aiUsageEnabled {
            SectionLabel("Suggestions").padding(.top, 4)
            if !settings.downloadsEnabled {
                SuggestionRow(icon: .symbol("arrow.down.circle.fill", .blue), title: "Download progress",
                              detail: "macOS asks for access to Downloads.", action: "Turn On") { settings.downloadsEnabled = true }
            } else if downloads.accessDenied {
                SuggestionRow(icon: .symbol("arrow.down.circle.fill", .blue), title: "Downloads access is off",
                              detail: "Allow it in Privacy & Security › Files and Folders.", action: "Open Settings") {
                    SystemSettingsLink.open(SystemSettingsLink.filesAndFolders)
                }
            }
            if !settings.aiUsageEnabled {
                SuggestionRow(icon: AppIcons.icon("Claude").map(CardIcon.app) ?? .symbol("sparkle", .orange), title: "AI usage",
                              detail: "Claude Code and Codex usage from local logs.", action: "Turn On") {
                    settings.aiUsageEnabled = true
                    ai.refresh()
                }
            }
        }
    }
}

/// One compact line offering to turn a feature on.
private struct SuggestionRow: View {
    let icon: CardIcon
    let title: String
    let detail: String
    let action: String
    let run: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            CardIconView(icon: icon, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(DS.body.weight(.semibold)).lineLimit(1)
                Text(detail).font(DS.caption).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            Chip(title: action, action: run)
        }
        .padding(.vertical, 2)
    }
}

/// One notification: tinted glyph, title, detail, relative time.
private struct NotificationRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CardIconView(icon: .symbol(event.symbol, event.tint == .white ? .gray : event.tint), size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(DS.body.weight(.semibold)).lineLimit(1)
                if let detail = event.detail ?? event.trailing {
                    Text(detail).font(DS.caption).foregroundStyle(Color.secondaryText).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text(event.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.tertiaryText)
        }
        .padding(.horizontal, 6).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// An SF Symbol on a tinted rounded square, or an app icon.
struct CardIconView: View {
    let icon: CardIcon
    var size: CGFloat = 26

    var body: some View {
        switch icon {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.opacity(0.85), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        case .app(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
        }
    }
}

/// Icon for a card: an SF Symbol on a tinted rounded square, or an app icon.
enum CardIcon {
    case symbol(String, Color)
    case app(NSImage)
}

struct Card<Content: View>: View {
    let icon: CardIcon
    let app: String
    let time: Date?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            iconView.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(app.uppercased()).font(DS.label).tracking(0.8).foregroundStyle(Color.tertiaryText)
                    Spacer()
                    if let time {
                        Text(time, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.system(size: 9.5)).foregroundStyle(Color.tertiaryText)
                    }
                }
                content
            }
        }
        .well(padding: 10)
    }

    private var iconView: some View { CardIconView(icon: icon) }
}

private struct DownloadCard: View {
    let download: DownloadsMonitor.Download
    @Environment(DownloadsMonitor.self) private var downloads

    var body: some View {
        Card(icon: .symbol(download.isActive ? "arrow.down" : download.status == .stopped ? "xmark" : "checkmark",
                           download.isActive ? .blue : download.status == .stopped ? .gray : .green),
             app: "Downloads", time: download.finishedAt) {
            HStack {
                Text(download.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                Text(statusText).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.secondaryText)
                if !download.isActive {
                    Button { downloads.reveal(download) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.plainHit).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.secondaryText)
                        .help("Show in Finder")
                }
            }
            if download.isActive {
                if let f = download.fraction {
                    ProgressView(value: f).progressViewStyle(.linear).tint(.blue).controlSize(.small)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(.blue).controlSize(.small)
                }
            }
        }
    }

    /// Real numbers only: a percentage when the browser publishes progress,
    /// otherwise the size on disk so far.
    private var statusText: String {
        switch download.status {
        case .completed: return "Done"
        case .stopped: return "Stopped"
        case .inProgress:
            if let f = download.fraction { return f.formatted(.percent.precision(.fractionLength(0))) }
            return download.bytes.map { "\($0.byteString) so far" } ?? "In progress"
        }
    }
}

/// Coding-agent usage from local logs, with the tools' real app icons
/// (taken from the installed apps). Claude's icon breathes while a Claude
/// Code session is active. Codex has no installed app here, so a symbol is
/// used; no logo artwork is bundled with Stitchy.
private struct AIUsageSection: View {
    @Environment(AIUsageMonitor.self) private var ai
    @Environment(AppSettings.self) private var settings

    var body: some View {
        // Shown only when AI Usage is on; the page offers turning it on as a suggestion.
        do {
            VStack(spacing: 8) {
                claudeCard
                codexCard
                Card(icon: AppIcons.icon("Cursor").map(CardIcon.app) ?? .symbol("cursorarrow.rays", .gray), app: "Cursor", time: nil) {
                    Text(ai.cursorInstalled ? "Cursor keeps no documented local usage data." : "Not installed")
                        .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                }
            }
            .task(id: settings.aiUsageEnabled) {
                while !Task.isCancelled {
                    ai.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    private var claudeCard: some View {
        Card(icon: .symbol("sparkle", .orange), app: "Claude Code", time: ai.claude?.lastActivity) {
            if let c = ai.claude {
                Text("\(Self.tokens(c.blockTokens)) this 5-hour block").font(.system(size: 12, weight: .semibold))
                Text("\(Self.tokens(c.todayTokens)) today · \(c.todayMessages) messages\(c.activeSessions > 0 ? " · \(c.activeSessions) active" : "")")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                if let end = c.blockEnd {
                    Text("Block resets at \(end.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(Color.tertiaryText)
                }
            } else {
                Text(ai.lastRefresh == nil ? "Reading logs…" : (ai.claudeFound ? "No recent activity" : "No Claude Code logs found"))
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
            }
        }
        .overlay(alignment: .topLeading) {
            ClaudeMark(active: (ai.claude?.activeSessions ?? 0) > 0).frame(width: 26, height: 26).padding(10)
        }
    }

    private var codexCard: some View {
        Card(icon: AppIcons.icon("Codex").map(CardIcon.app) ?? .symbol("chevron.left.forwardslash.chevron.right", .gray),
             app: "Codex", time: ai.codex?.lastActivity) {
            if let p = ai.codex?.primary {
                Text("\(Int(p.usedPercent))% of limit used").font(.system(size: 12, weight: .semibold))
                ProgressView(value: min(p.usedPercent / 100, 1)).tint(p.usedPercent > 80 ? .orange : .green).controlSize(.small)
                Text([ai.codex?.secondary.map { "Weekly \(Int($0.usedPercent))%" }, p.resetsAt.map { "resets \($0.formatted(date: .omitted, time: .shortened))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(Color.tertiaryText)
            } else {
                Text(ai.codexFound ? "No rate-limit data in recent sessions" : "Not installed")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
            }
        }
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM tokens", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fK tokens", Double(n) / 1e3) : "\(n) tokens"
    }
}

/// Claude's app icon from the installed Claude app; breathes while active.
private struct ClaudeMark: View {
    let active: Bool
    @State private var pulse = false

    var body: some View {
        Group {
            if let icon = AppIcons.icon("Claude") {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "sparkle").foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .scaleEffect(active && pulse ? 1.08 : 1)
        .shadow(color: .orange.opacity(active && pulse ? 0.6 : 0), radius: 6)
        .onAppear { pulse = active }
        .onChange(of: active) { _, a in pulse = a }
        .animation(active ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default, value: pulse)
        .accessibilityLabel(active ? "Claude Code active" : "Claude Code")
    }
}

/// Icons of installed apps, looked up once.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage?] = [:]
    private static let candidates: [String: [String]] = [
        "Claude": ["com.anthropic.claudefordesktop"],
        "Cursor": ["com.todesktop.230313mzl4w4u92"],
        "Codex": ["com.openai.codex", "com.openai.chat"],
    ]

    static func icon(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        let ws = NSWorkspace.shared
        let url = (candidates[name] ?? []).lazy.compactMap { ws.urlForApplication(withBundleIdentifier: $0) }.first
            ?? ["/Applications/\(name).app"].map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
        let image = url.map { ws.icon(forFile: $0.path) }
        cache[name] = image
        return image
    }
}
