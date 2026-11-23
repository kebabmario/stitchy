import SwiftUI

struct MusicView: View {
    @Environment(NowPlayingService.self) private var music

    var body: some View {
        if let track = music.track {
            nowPlaying(track)
        } else {
            empty
        }
    }

    private func nowPlaying(_ track: NowPlayingService.Track) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ArtworkView(image: music.artwork, size: 72, radius: 14, placeholderIcon: nil)
                    .shadow(color: music.accent.opacity(music.artwork == nil ? 0 : 0.35), radius: 12, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    if let player = music.player {
                        HStack(spacing: 4) {
                            if let icon = player.icon { Image(nsImage: icon).resizable().frame(width: 12, height: 12) }
                            Text(player.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.tertiaryText)
                        }
                    }
                    Text(track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(track.artist.isEmpty ? track.album : track.artist)
                        .font(.system(size: 13)).foregroundStyle(Color.secondaryText).lineLimit(1)
                    Spacer(minLength: 0)
                    progress(track)
                }
                .frame(height: 72)
                if music.controlsEnabled {
                    EqualizerView(color: NSColor(music.accent), animating: music.isPlaying)
                        .frame(width: 18, height: 16)
                        .padding(.top, 2)
                        .frame(maxHeight: 72, alignment: .top)
                }
            }
            controls
        }
    }

    @ViewBuilder private func progress(_ track: NowPlayingService.Track) -> some View {
        if let duration = track.duration, duration > 0, music.position != nil {
            TimelineView(.periodic(from: .now, by: music.isPlaying ? 1 : 3600)) { context in
                let elapsed = music.elapsed(at: context.date) ?? 0
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(music.accent).frame(width: geo.size.width * min(elapsed / duration, 1))
                        }
                    }
                    .frame(height: 4)
                    HStack {
                        Text(elapsed.clockString)
                        Spacer()
                        Text("-" + max(duration - elapsed, 0).clockString)
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.tertiaryText)
                }
            }
        } else if let duration = track.duration {
            Text(duration.clockString)
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.tertiaryText)
        }
    }

    @ViewBuilder private var controls: some View {
        if music.controlsEnabled, music.permission != .denied {
            HStack(spacing: 28) {
                IconButton(symbol: "backward.fill", size: 15, diameter: 34, help: "Previous Track") { music.previous() }
                IconButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 18, diameter: 42, filled: true, help: music.isPlaying ? "Pause" : "Play") {
                    music.playPause()
                }
                .contentTransition(.symbolEffect(.replace))
                IconButton(symbol: "forward.fill", size: 15, diameter: 34, help: "Next Track") { music.next() }
            }
        } else if music.permission == .denied {
            permissionNote("Playback control was denied.", button: "Open Privacy Settings") {
                SystemSettingsLink.open(SystemSettingsLink.automation)
            }
        } else {
            permissionNote("Artwork, progress and controls need one-time Automation access.", button: "Enable Controls") {
                Task { await music.enableControls() }
            }
        }
    }

    private func permissionNote(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(text).font(.system(size: 11)).foregroundStyle(Color.secondaryText).lineLimit(2)
            Spacer(minLength: 0)
            PillButton(title: button, tint: .white, action: action)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.tertiaryText)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Nothing Playing").font(.system(size: 14, weight: .semibold))
            Text("Play something in Music or Spotify. Other players and browsers aren't supported by macOS APIs.")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
