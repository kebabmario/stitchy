# Stitchy

A native macOS Dynamic Island for Macs without a notch. Stitchy draws a black
capsule at the top centre of the display that grows downward into a small
dashboard: clock, battery, network, music, a timer, a file shelf, downloads and
an activity feed.

Built with Swift 6, SwiftUI and AppKit (`NSPanel` + `NSHostingView`). No
third-party dependencies, no web views.

## Requirements

- macOS 14 Sonoma or later (developed and tested on macOS 26.5, Apple silicon)
- Swift 6 toolchain: either Xcode 16+ or just the Command Line Tools
  (`xcode-select --install`)

## Build and run

```bash
Scripts/build-app.sh            # release build -> build/Stitchy.app
open build/Stitchy.app
```

Other options:

```bash
Scripts/build-app.sh --install  # also copies to ~/Applications
Scripts/build-app.sh --debug    # debug configuration
Scripts/test.sh                 # unit + integration tests (Swift Testing)
swift Scripts/make-icon.swift   # regenerate Stitchy/Resources/AppIcon.icns
```

**Xcode:** open `Package.swift` in Xcode to browse, edit and debug. The
package is the project file. For notifications and launch-at-login, macOS needs
a real app bundle, so use `build-app.sh` (or set `STITCHY_SIGN_IDENTITY` to your
Apple Development certificate) to produce `Stitchy.app`.

**Signing:** without `STITCHY_SIGN_IDENTITY`, the app is ad-hoc signed. Ad-hoc
signatures change on every build, so macOS may ask for Automation or Downloads
access again after a rebuild. Signing with a stable identity avoids that:

```bash
STITCHY_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/build-app.sh --install
```

## Using it

| Action | Result |
|---|---|
| Hover the island | Expands after a short delay; collapses when the pointer leaves |
| Click the island | Expands and stays open (pinned) |
| Click inside a hover-opened island | Pins it |
| Click empty header space, press Esc, or click elsewhere | Collapses |
| Drag files toward the island | Opens the Shelf as a drop target |
| Menu bar icon (capsule) | Open Stitchy, Show/Hide Island, Settings…, Quit |
| Open Stitchy.app again while running | Opens Settings |

## Features

- **Dashboard.** Time and date, a battery tile, a network tile and an overview
  of what's live (timer, music, downloads, shelf). Each overview row opens its tab.
- **Music.** Track, artist, artwork, progress and transport controls for
  Apple Music and Spotify. See *Music support* below.
- **Timer.** Presets plus ±1 minute steps; start, pause, resume, reset. Runs as a
  live activity in the compact island (ring + countdown). On completion it shows
  a live alert and posts a system notification.
- **File Shelf.** Drop files onto the island to hold references to them. Icons,
  names, remove (×), Reveal in Finder, Open, AirDrop, drag back out, Clear.
  The shelf never moves, copies or deletes files; Clear only empties the list.
- **Downloads.** Watches `~/Downloads` (opt-in). Uses the file progress that
  Safari and Chrome publish for Finder, so percentages are real. Downloads
  without published progress show the size on disk so far, never a made-up
  percentage. Completed downloads can be revealed in Finder.
- **Activity / notifications.** A feed of Stitchy's own events (timer done,
  downloads finished, charger connected/disconnected, low battery, files added)
  plus brief live alerts in the compact island.
- **Battery.** Percentage, charging state, time to full/empty, adapter wattage,
  Low Power Mode, from IOKit power-source notifications.
- **Settings.** Launch at login, show/hide island, display choice, hover
  expansion and delay, collapse-on-exit, click expansion, haptics, animation
  style (Natural / Snappy / Gentle / Minimal), visualizer animation, vertical and
  horizontal position, feature toggles, permission status, Reset Settings. All
  stored in UserDefaults.

## Permissions

Stitchy asks for each permission only when you first use the feature that needs it.

| Feature | Permission | When it's requested |
|---|---|---|
| Timer completion notification | Notifications | First time you start a timer |
| Music artwork, progress, play/pause/skip | Automation (Apple Events) for Music / Spotify | When you click **Enable Controls** in the Music tab |
| Download progress | Files & Folders → Downloads | When you turn on Downloads (Activity tab or Settings) |
| Launch at login | Login Items approval (sometimes) | When you enable it in Settings |

Not needed and never requested: Accessibility, Input Monitoring, Screen
Recording, Location, Full Disk Access. Track titles, battery, network status,
hover/click handling and file drops all work with no permission at all.

## Architecture

```
Stitchy/
  App/            main.swift, AppDelegate, StatusBarController (menu bar)
  Core/           AppSettings (UserDefaults), AppServices (owns + wires services),
                  ActivityEvent, Support (screen lookup, haptics, login item, logging),
                  SnapshotRenderer (dev aid)
  Windows/        IslandPanel (borderless non-activating NSPanel),
                  IslandWindowController (positioning, pointer/drag/keyboard behaviour)
  Island/         IslandModel (state + geometry), IslandView (the morphing shape),
                  CompactIslandView, ExpandedIslandView, Components
  Features/
    Dashboard/    DashboardView, NetworkMonitor
    Music/        NowPlayingService, AppleScriptRunner, MusicView
    Timer/        TimerService, TimerView
    Notifications/ ActivityFeed, SystemNotifier
    FileDrop/     FileShelf, ShelfView
    Activities/   DownloadsMonitor, ActivityView
    Battery/      BatteryMonitor
  Settings/       SettingsWindowController (toolbar tabs), SettingsViews
  Resources/      Info.plist, AppIcon.icns
Tests/StitchyTests  Timer, shelf, downloads (incl. real Progress publishing), formatting
Scripts/          build-app.sh, test.sh, make-icon.swift
```

### Key decisions

- **One shape.** `IslandView` owns a single black `UnevenRoundedRectangle`
  whose size and corner radii animate between compact, alert and expanded. The
  content is swapped inside it and clipped by it, so every state reads as the
  same object growing down from the top edge.
- **Fixed transparent panel, selective hit-testing.** The panel is a fixed
  560×320 pt transparent canvas at status-bar level. It ignores mouse events
  everywhere except the island's current shape, so it never blocks the menu bar
  or windows underneath. Global and local `NSEvent` monitors (no permission
  required, event-driven) track the pointer. The hit rect comes from the same
  `IslandMetrics.size(…)` function the view uses for its target size, never from
  mid-animation layout, which avoids flicker. The hit area also extends up to
  the top edge of the screen, so pushing the cursor to the top centre counts.
- **Focus.** The panel is non-activating: clicking it never brings Stitchy
  forward. It becomes key only while pinned open (so Esc works) and hands focus
  back when it collapses.
- **File drags.** A changed `NSPasteboard(name: .drag).changeCount` during a
  mouse drag means a drag session is in progress; the island opens as a drop
  target when the pointer comes near. Pasteboard contents are not read until you
  drop.
- **No polling.** Battery uses IOKit run-loop notifications, network uses
  `NWPathMonitor`, music uses distributed notifications, downloads use a kqueue
  directory source plus `Progress` subscriptions, and the timer is an end date
  plus one sleeping task. Views refresh once per second only while they show a
  running countdown or progress. The visualizer bars are Core Animation layers,
  so animation happens on the render server.
- **App Nap** is held off only while a timer runs, so it ends on time.

### Music support

macOS 15.4+ blocks third-party apps from the private MediaRemote framework, so
there is no supported system-wide "Now Playing" API. Stitchy uses supported
mechanisms instead:

1. Apple Music and Spotify broadcast distributed notifications on every track
   or state change (`com.apple.Music.playerInfo`,
   `com.spotify.client.PlaybackStateChanged`). These give title, artist, album,
   duration and state with no permission.
2. Artwork, exact playback position and play/pause/next/previous use Apple
   Events, after you grant Automation access.

Other players (browsers, YouTube, Podcasts, VLC, etc.) are **not supported**,
and the Music tab says so.

## Verified on the machine

Tested on a MacBook Neo (Mac17,5, A18 Pro, macOS 26.5.1, 1408×881 pt display):

- Builds cleanly (Swift 6 language mode, strict concurrency); 8/8 tests pass.
- Panel sits at window level 25, horizontally centred, 3 pt below the top edge.
  Position settings persist across relaunch (gap 12 / offset −100 moved it as expected).
- Driven with synthetic pointer events and checked in the app's log:
  hover expands after ~200 ms and collapses ~270 ms after leaving; clicking the
  compact island pins it; clicking inside a hover-opened island pins it; Esc
  collapses a pinned island; clicking elsewhere collapses it; clicking empty
  header space collapses it.
- Real file drag (NSDraggingSession from another process) onto the island:
  island opened on Shelf, file added, original untouched.
- 1-minute timer started from the UI finished on time (60.08 s), posted a live
  alert and requested notification permission on first use.
- Music pipeline exercised with Spotify-format notifications: play shows the
  track and a live alert, pause keeps it, stop clears it.
- Settings window opens with toolbar tabs.
- Resource use (release build): idle 0.0 % CPU, ~14 MB RSS; expanded ~19 MB, 0.0 % CPU.
- Each island state was rendered to PNG offscreen (`Stitchy --snapshots <dir>`)
  and reviewed.

## Known limitations

- **Music:** only Apple Music and Spotify. Artwork, position and controls need
  Automation access. Live playback with the real Music app hasn't been tested
  yet (only Spotify-format notifications were).
- **Notifications:** Stitchy can't read other apps' notifications. macOS
  doesn't allow it without private databases, which Stitchy doesn't touch. The
  feed shows Stitchy's own events only.
- **Wi‑Fi name (SSID)** isn't shown, because macOS reveals it only to apps with
  Location access. Connection type and signal strength are shown.
- **Downloads:** only `~/Downloads`. Downloads that publish no progress show
  bytes so far instead of a percentage.
- **Clicks within ~60 ms of the pointer arriving** on the compact island can go
  to the menu bar underneath, because WindowServer applies the panel's
  click-through change asynchronously. Normal human clicks aren't affected.
- **Not tested here:** plugging/unplugging a display or changing resolution (it
  repositions on `didChangeScreenParametersNotification`), launch at login with
  an ad-hoc signature, keyboard focus returning to the previous app after
  collapse, full-screen apps (the island stays visible over them).
- **Visual review:** the live on-screen look (animations, blur transitions)
  couldn't be captured from this session because Screen Recording wasn't
  available. Static states were reviewed via offscreen renders.

## Debugging

```bash
log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info
.build/arm64-apple-macosx/release/Stitchy --snapshots /tmp/stitchy-snaps   # render states to PNG
```
