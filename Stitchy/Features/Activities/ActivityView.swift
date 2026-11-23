import SwiftUI

/// Downloads in progress plus the feed of Stitchy's own notifications.
struct ActivityView: View {
    @Environment(DownloadsMonitor.self) private var downloads
    @Environment(ActivityFeed.self) private var feed
    @Environment(AppSettings.self) private var settings

    var body: some View {
        IslandScroll(axis: .vertical) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Downloads", onClear: downloads.downloads.contains { !$0.isActive } ? { downloads.clearFinished() } : nil)
                downloadsSection
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
