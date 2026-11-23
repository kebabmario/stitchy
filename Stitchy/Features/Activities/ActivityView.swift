import SwiftUI

/// Downloads in progress plus the feed of Stitchy's own notifications.
struct ActivityView: View {
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(ActivityFeed.self) private var feed
    @Environment(AppSettings.self) private var settings
    @Environment(AIUsageMonitor.self) private var ai

    var body: some View {
        IslandScroll(axis: .vertical) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Downloads", onClear: downloads.downloads.contains { !$0.isActive } ? { downloads.clearFinished() } : nil)
                downloadsSection
                sectionHeader("AI Usage", onClear: nil).padding(.top, 4)
                AIUsageSection()
                sectionHeader("Recent", onClear: feed.items.isEmpty ? nil : { feed.clear() })
                    .padding(.top, 4)
                if feed.items.isEmpty {
                    placeholder("No recent activity. Timers, downloads, power changes and shelf drops appear here.")
                }
                ForEach(feed.items) { FeedRow(event: $0) }
            }
        }
        .onAppear { feed.markRead() }
    }

    @ViewBuilder private var downloadsSection: some View {
        if !settings.downloadsEnabled {
            HStack(spacing: 10) {
                Text("See download progress here. macOS will ask for access to Downloads.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                PillButton(title: "Turn On") { settings.downloadsEnabled = true }
            }
        } else if downloads.accessDenied {
            HStack(spacing: 10) {
                Text("Stitchy can't read Downloads.").font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                Spacer(minLength: 0)
                PillButton(title: "Open Settings") { SystemSettingsLink.open(SystemSettingsLink.filesAndFolders) }
            }
        } else if downloads.downloads.isEmpty {
            placeholder("No active downloads.")
        } else {
            ForEach(downloads.downloads) { DownloadRow(download: $0) }
        }
    }

    private func sectionHeader(_ title: String, onClear: (() -> Void)?) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.tertiaryText)
            Spacer()
            if let onClear {
                Button("Clear") { withAnimation(.snappy) { onClear() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(Color.tertiaryText)
    }
}

private struct DownloadRow: View {
    let download: DownloadsMonitor.Download
    @Environment(DownloadsMonitor.self) private var downloads

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(download.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(statusText).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(Color.secondaryText)
                }
                if download.isActive {
                    if let fraction = download.fraction {
                        ProgressView(value: fraction).progressViewStyle(.linear).tint(.blue).controlSize(.small)
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(.blue).controlSize(.small)
                    }
                }
            }
            if !download.isActive {
                IconButton(symbol: "magnifyingglass", size: 10, diameter: 22, help: "Show in Finder") { downloads.reveal(download) }
            }
        }
    }

    private var symbol: String {
        switch download.status {
        case .inProgress: "arrow.down"
        case .completed: "checkmark"
        case .stopped: "xmark"
        }
    }

    private var tint: Color {
        switch download.status {
        case .inProgress: .blue
        case .completed: .green
        case .stopped: .gray
        }
    }

    /// Real numbers only: a percentage when the browser publishes progress,
    /// otherwise the size on disk so far.
    private var statusText: String {
        switch download.status {
        case .completed: return "Completed"
        case .stopped: return "Stopped"
        case .inProgress:
            if let fraction = download.fraction { return fraction.formatted(.percent.precision(.fractionLength(0))) }
            return download.bytes.map { "\($0.byteString) so far" } ?? "In progress"
        }
    }
}

private struct FeedRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(event.tint)
                .frame(width: 28, height: 28)
                .background(event.tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if let detail = event.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(event.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.tertiaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Coding-agent usage from local logs. Shows only what the logs contain.
private struct AIUsageSection: View {
    @Environment(AIUsageMonitor.self) private var ai
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if !settings.aiUsageEnabled {
            HStack(spacing: 10) {
                Text("Read Claude Code and Codex usage from their local logs on this Mac. Nothing is uploaded.")
                    .font(.system(size: 11)).foregroundStyle(Color.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                PillButton(title: "Turn On") { settings.aiUsageEnabled = true; ai.refresh() }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                claudeRow
                codexRow
                row(symbol: "cursorarrow.rays", tint: .gray, title: "Cursor",
                    detail: ai.cursorInstalled ? "No documented local usage data" : "Not installed", value: nil)
            }
            .task(id: settings.aiUsageEnabled) {
                // Refresh while visible: every 60 s, reading only new log lines.
                while !Task.isCancelled {
                    ai.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    @ViewBuilder private var claudeRow: some View {
        if let c = ai.claude {
            let detail: String = {
                var parts = ["\(Self.tokens(c.todayTokens)) today · \(c.todayMessages) msgs"]
                if c.activeSessions > 0 { parts.append("\(c.activeSessions) active") }
                return parts.joined(separator: " · ")
            }()
            let value = c.blockEnd.map { "block resets " + $0.formatted(date: .omitted, time: .shortened) }
            row(symbol: "sparkle", tint: .orange, title: "Claude Code · \(Self.tokens(c.blockTokens)) this block", detail: detail, value: value)
        } else {
            row(symbol: "sparkle", tint: .orange, title: "Claude Code",
                detail: ai.lastRefresh == nil ? "Reading logs…" : (ai.claudeFound ? "No recent activity" : "No logs found"), value: nil)
        }
    }

    @ViewBuilder private var codexRow: some View {
        if let p = ai.codex?.primary {
            row(symbol: "chevron.left.forwardslash.chevron.right", tint: .green, title: "Codex · \(Int(p.usedPercent))% of limit used",
                detail: ai.codex?.secondary.map { "Weekly \(Int($0.usedPercent))%" } ?? "As reported by Codex",
                value: p.resetsAt.map { "resets " + $0.formatted(date: .omitted, time: .shortened) })
        } else {
            row(symbol: "chevron.left.forwardslash.chevron.right", tint: .green, title: "Codex",
                detail: ai.codexFound ? "No rate-limit data in recent sessions" : "Not installed", value: nil)
        }
    }

    private func row(symbol: String, tint: Color, title: String, detail: String, value: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 28, height: 28).background(tint.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(Color.secondaryText).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let value { Text(value).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.tertiaryText) }
        }
    }

    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM tokens", Double(n) / 1e6) : n >= 1000 ? String(format: "%.0fK tokens", Double(n) / 1e3) : "\(n) tokens"
    }
}
