# Stitchy

A native macOS notch and Dynamic Island for Macs without a notch. Stitchy
draws a black notch attached to the top edge of the display. Hover or click it
and it grows downward into one continuous surface with live activities, music,
timers, a file and clipboard shelf, notes, calendar, a launcher and more.

Swift 6, SwiftUI and AppKit (`NSPanel` + `NSHostingView`). No third-party
dependencies, no web views, no private APIs.

## Requirements

- macOS 14 Sonoma or later (developed and tested on macOS 26.5, Apple silicon)
- Swift 6 toolchain: Xcode 16+ or just the Command Line Tools (`xcode-select --install`)

## Build and run

```bash
Scripts/build-app.sh            # release build -> build/Stitchy.app
open build/Stitchy.app
```

```bash
Scripts/build-app.sh --install  # also copies to ~/Applications
Scripts/build-app.sh --debug    # debug configuration
Scripts/test.sh                 # unit + integration tests (Swift Testing)
swift Scripts/make-icon.swift   # regenerate the app icon
```

**Xcode:** open `Package.swift` to browse, edit and debug. Notifications,
camera, calendar and launch-at-login need a real app bundle, so run the `.app`
from `build-app.sh`.

**Signing:** without `STITCHY_SIGN_IDENTITY` the app is ad-hoc signed, and the
signature changes on every build, so macOS asks again for permissions you
already granted (Downloads, Automation…). Signing with a stable identity avoids
that. The first launch of a freshly signed build can also take a few seconds
while macOS verifies it.

```bash
STITCHY_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" Scripts/build-app.sh --install
```

## Using it

| Action | Result |
|---|---|
| Hover the notch | Expands after a short delay; collapses when the pointer leaves |
| Click the notch | Expands and stays open (pinned) |
| Click inside a hover-opened island | Pins it |
| Click empty header space, press Esc, or click elsewhere | Collapses |
| ⌃⌥Space (configurable) | Opens the launcher with search focused; again to close |
| Drag files toward the notch | Opens the Shelf as a drop target |
| Menu bar icon | Open Stitchy, Show/Hide Island, Settings…, Quit |
| Open Stitchy.app again while running | Opens Settings |

## Features

### The island
- **Attached notch.** Flush with the top edge (`NSScreen.frame`), concave
  shoulders where it meets the edge, rounded bottom corners. By default it is as
  tall as the menu bar, like a real MacBook notch. Width, height, expanded width,
  vertical offset and horizontal offset are adjustable.
- **One surface.** Compact, live activity, alert, HUD and expanded are all the same
  `NotchShape`, whose size and radii animate. The top edge never moves.
- **Activity system.** Every feature reports into one `IslandActivity` model with
  priorities: camera/mic → finished timers → countdowns → Focus → transfers →
  stopwatch → music. The compact notch shows the top activity on both sides of
  the notch, with a small glyph for the next one. Home lists all of them.
  Visibility is configurable per category.
- **Hides in full screen** (optional), using window bounds from CGWindowList (no
  Screen Recording permission needed).

### Dynamic Island features
- **Now Playing.** Apple Music and Spotify: title, artist, artwork, progress,
  play/pause/previous/next, track-change alerts, visualizer. See *Music* below.
- **Timers.** Any number of countdowns at once, a stopwatch with laps, pause /
  resume / reset, completion alerts and notifications, persistent compact activity.
- **Charging.** Percentage, charging state, time to full/empty, adapter wattage,
  charger connect/disconnect alerts, low-battery warnings at 20 % and 10 %,
  fully-charged event, Low Power Mode.
- **Transfers.** Download progress from `~/Downloads` (Safari/Chrome publish
  real progress; others show bytes so far). Incoming AirDrop files land in
  Downloads and appear there too. Outgoing AirDrop from the Shelf shows as an
  activity with a sent/failed result (macOS reports start and finish, not bytes).
- **Notifications.** Stitchy's own alerts in the island, a history feed, and
  system notifications for timers, Focus and meetings.

### Stitchy features
- **Clipboard history** (opt-in). Text, file references and images, kept in
  memory only. Click to copy again, delete individual items, clear, set the
  history size, exclude apps (password managers excluded by default). Items marked
  concealed or transient are never recorded.
- **File Shelf.** Drop multiple files, QuickLook thumbnails, names and types,
  Reveal in Finder, Open, AirDrop, remove, drag back out. References only:
  nothing on disk is ever moved or deleted.
- **System HUD.** Volume, mute and audio output changes via CoreAudio listeners.
- **Focus (Pomodoro).** Focus / short break / long break with configurable
  lengths, cycle progress dots, today's count, and persisted session history.
- **Quick Notes.** Create, edit, search and delete. Saved to
  `~/Library/Application Support/Stitchy/notes.json`.
- **Calendar.** Upcoming events today and tomorrow, a live countdown to the next
  one, and a reminder N minutes before (EventKit, requested on Connect).
- **AI Usage.** Claude Code tokens today and in the current 5-hour block,
  messages and active sessions, read from Claude Code's local logs. Codex
  rate-limit usage when Codex's session logs are present. Cursor is listed as
  unsupported. Opt-in.
- **Launcher.** Searchable commands: your apps/folders/approved Shortcuts,
  Stitchy actions (start timer, Focus, stopwatch, new note, clipboard, Face ID
  glance, settings) and installed apps. Arrow keys + Return.
- **Camera Guard.** Indicator and alert when the camera or microphone turns on,
  with elapsed time.
- **Private sections.** Optionally lock Notes and Clipboard behind Touch ID /
  password (LocalAuthentication); unlocking lasts 5 minutes.

### Stitchy Face ID
A guided, opt-in, on-device **presence and similarity** feature:

1. Enable it in Settings › Face ID (the camera stays off).
2. Read what it is and isn't, then allow camera access.
3. Enroll: the camera runs for a few seconds; Vision finds one face and computes
   6 feature prints of it. Only these numeric descriptors are stored, in the
   login Keychain. Frames are processed in memory and discarded.
4. Use **Check Now** in Settings, the **Face ID Glance** row on Home, or the
   launcher action. The camera runs ~2 seconds and the result is "looks like you"
   / "doesn't match" / "no face".
5. **Delete Face Data** removes the Keychain item.

The camera only runs during enrollment or a check that you start. The green
camera light shows, and Camera Guard shows it too. It stops when Settings closes.

**Security: this is not Face ID.** A regular RGB webcam has no depth or infrared
sensing, and Vision's image feature prints are not a face-identity model. A
photo, video or look-alike can match. Stitchy Face ID never authenticates
anything: it doesn't unlock the Mac, touch the login window, type passwords or
bypass anything. Protected Stitchy sections use LocalAuthentication.

## Permissions

Requested only when you first use the feature that needs it:

| Feature | Permission | When |
|---|---|---|
| Timer / Focus / meeting notifications | Notifications | First timer start |
| Music artwork, progress, controls | Automation (Music / Spotify) | "Enable Controls" in the Music tab |
| Download progress | Files & Folders → Downloads | Turning Downloads on |
| Calendar | Calendars (full access) | "Connect Calendar" |
| Stitchy Face ID | Camera | "Allow Camera…" in Face ID settings |
| Clipboard history | Paste from other apps (macOS may ask) | Turning clipboard history on |
| Private sections | Touch ID / password (per unlock) | Unlocking |
| Launch at login | Login Items approval (sometimes) | Enabling it |

**Never requested:** Accessibility, Input Monitoring, Screen Recording, Location,
Full Disk Access. The global shortcut uses Carbon `RegisterEventHotKey`, which
needs none of these. Camera Guard reads the public "device is running somewhere"
properties, which need no camera or microphone permission.

## Architecture

```
Stitchy/
  App/            main.swift, AppDelegate, StatusBarController (menu bar)
  Core/           AppSettings (UserDefaults; "data." keys survive reset), AppServices
                  (owns + wires every service), IslandActivity (activity model +
                  priorities), ActivityEvent, Support, SnapshotRenderer (dev aid)
  Windows/        IslandPanel (borderless non-activating NSPanel),
                  IslandWindowController (top-edge positioning, pointer/drag/keyboard,
                  full-screen hiding)
  Island/         IslandModel (state + IslandGeometry), NotchShape, IslandView,
                  CompactIslandView (activities, alert, HUD), ExpandedIslandView
                  (header, tabs, private gate, drop target), Components
  Features/
    Dashboard/  Music/  Timer/ (TimerService, TimerStore, Stopwatch, Pomodoro)
    Notifications/  FileDrop/  Activities/ (downloads)  Battery/
    Clipboard/  HUD/ (CoreAudio)  Privacy/ (Camera Guard)  Notes/  Calendar/
    AIUsage/  Launcher/ (+ GlobalHotkey)  FaceID/ (FaceIDService, Keychain, PrivateLock)
  Settings/       Toolbar-tab preferences: General, Island, Features, Clipboard,
                  Launcher, Face ID, Privacy
Tests/StitchyTests  18 tests: timers, stopwatch, Pomodoro, store, clipboard, notes,
                    downloads (real Progress publishing), usage scanner, geometry, reset
```

### Key decisions
- **Fixed transparent panel, selective hit-testing.** A 680×380 pt transparent
  panel at status-bar level, pinned to the top of `NSScreen.frame`. It ignores
  the mouse everywhere except the island's current target shape, so menu bar
  items outside the notch keep working. Global/local `NSEvent` monitors (no
  permission, event-driven) track the pointer. The hit rect comes from the same
  `IslandGeometry` the view draws with, never from mid-animation layout.
- **Focus.** Non-activating: clicking never brings Stitchy forward. It becomes
  key only while pinned (so Esc, search and notes typing work) and hands focus
  back on collapse.
- **No polling** except where macOS offers no event: clipboard history reads the
  pasteboard change counter twice a second while enabled, and indeterminate
  downloads re-stat every 2 s while one exists. Everything else is notifications
  or listeners (IOKit, CoreAudio, CoreMediaIO, NWPathMonitor, distributed
  notifications, kqueue, Progress, EventKit) or a single sleeping task (timers,
  meeting reminders).
- **TimelineViews use a fixed anchor date.** `TimelineView(.periodic(from: .now…))`
  re-anchors on every render and ticks every frame. That took the island from
  0.06 % to 7–16 % CPU during testing; every periodic timeline now uses
  `Date.timelineAnchor`.

### Music
macOS 15.4+ blocks third-party apps from the private MediaRemote framework, so
there is no supported system-wide Now Playing API. Stitchy uses Apple Music's
and Spotify's distributed notifications (track, artist, album, state, no
permission) plus Apple Events for artwork, position and controls (Automation,
opt-in). Browsers and other players are **not supported**.

## Testing

**Verified on the machine** (MacBook Neo, Mac17,5, macOS 26.5.1, 1408×881 pt):
- Build clean in Swift 6 mode; **18/18 tests pass** (one is an opt-in check against real logs).
- **Attached island:** panel at window level 25, `y = 0` (flush with the top), centred.
  Resting notch 206×30 pt (190 + shoulders × menu-bar height); offscreen renders reviewed for
  compact, hover, alert, HUD, live activity and every expanded tab.
- **Pointer (synthetic events, checked in the app log):** hover expands / leaving
  collapses; click pins; leaving a pinned island keeps it; Esc collapses.
- **Hotkey + launcher:** ⌃⌥Space opens the launcher pinned; typing "stop" ↩ ran
  Start Stopwatch, "timer" ↩ started a 5-minute timer, giving **two simultaneous activities**.
- **Clipboard:** turned on from the island UI; two `pbcopy`s recorded; an item
  marked `org.nspasteboard.ConcealedType` was skipped; no privacy prompt appeared.
- **File drop:** real cross-process file drag onto the notch → Shelf opened, file
  added, original untouched.
- **System HUD:** volume down/up, mute/unmute via AppleScript → four HUD updates
  ("MacBook Neo Speakers", level 0.88/0.94/0). Volume restored afterwards.
- **Music:** Spotify-format notifications: play → track alert, pause keeps it,
  stop clears it. Real Spotify playback was picked up at launch.
- **AI usage:** scanner totals for today's real Claude Code logs matched an
  independent Python count exactly (3,504,614 tokens, 537 messages).
- **Settings persistence:** a toggle changed in the island UI was written to
  UserDefaults; reset restores defaults and keeps user data (tested).
- **Permissions at launch:** only silent status checks (camera, microphone,
  input monitoring preflight). No unexpected prompts.
- **CPU / memory (release):** 0.03 % CPU averaged over 30 s with music playing
  and your normal features on; 30–45 MB RSS.

**Needs manual testing** (requires your input or hardware state):
- **Stitchy Face ID:** camera permission prompt, enrollment, Check Now, delete.
  The code builds and the camera stays off unless started, but enrollment needs
  your face and your approval of the camera prompt.
- **Calendar:** needs your approval of the calendar prompt.
- **Camera Guard live:** turning the camera/mic on in another app.
- **Private sections:** Touch ID / password unlock.
- **Music controls and artwork** with real Apple Music; Spotify artwork.
- **Downloads** with a real browser download; outgoing AirDrop.
- **Full-screen hiding**, display changes, launch at login.
- **Live animation feel:** Screen Recording wasn't available to this session, so
  motion was reviewed through code and static renders only.

## Known limitations

- **Incoming calls are not shown.** macOS has no public API for observing
  FaceTime/phone calls; CallKit is only for apps that provide their own calls.
  Camera Guard's microphone indicator with elapsed time is the closest honest signal.
- **Brightness** isn't in the HUD: no public API.
- **Notifications:** Stitchy can't read other apps' notifications.
- **Camera Guard** can't tell which app uses the camera or mic.
- **Music:** Apple Music and Spotify only.
- **AI usage:** Claude's plan limits aren't stored locally, so no remaining quota
  is shown; the 5-hour block follows the open-source ccusage method. Cursor has no
  documented local usage data.
- **Wi‑Fi name** isn't shown (macOS requires Location access for the SSID).
- **Clipboard history** needs a short poll of the change counter (no system
  notification exists) and is cleared on quit.
- **Stitchy Face ID** is a convenience/presence feature, not biometric security.
- Clicks within ~60 ms of the pointer arriving can reach the menu bar under
  the notch before WindowServer applies the panel's click-through change.

## Debugging

```bash
log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info
.build/arm64-apple-macosx/release/Stitchy --snapshots /tmp/stitchy-snaps   # render states to PNG
STITCHY_REAL_USAGE=1 Scripts/test.sh --filter realLogs                    # usage scan on real logs
```
