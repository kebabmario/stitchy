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

**Signing and permissions:** macOS ties privacy permissions (Calendar,
Automation for Notes/Music, Camera, Downloads, Bluetooth) to the app's
*designated requirement*. An ad-hoc signature's default requirement is the exact
binary hash, so every rebuild looked like a new app and every permission was
forgotten. `build-app.sh` now signs ad-hoc builds with
`designated => identifier "app.stitchy.Stitchy"`, so permissions survive
rebuilds. You re-approve once after this change. Trade-off: macOS then trusts
any app claiming that identifier; for real protection sign with an Apple
Development certificate via `STITCHY_SIGN_IDENTITY`. The first launch of a
freshly signed build can take a few seconds while macOS verifies it.

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
- **Style:** Settings › Island › Style switches between **Notch** (attached to the
  top edge) and **Dynamic Island** (a floating pill 6 pt below the edge, fully
  rounded, iPhone-style).
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
- **Bluetooth devices.** AirPods, keyboards, mice etc. show a connect/disconnect
  alert with the device name and icon (IOBluetooth notifications), and connected
  devices are listed on Home. Battery levels aren't shown: macOS exposes no public
  API for AirPods battery.
- **Drives.** USB/SD drives appear on connect with one-tap **Eject** and a
  "Safe to disconnect" confirmation.
- **Keep Awake** (1 hour, from Home or the launcher) and **Mic Mute** for all apps
  (CoreAudio input mute, where the device supports it), as Control Center-style
  toggles on Home and as live activities.
- **Shelf quick actions.** Zip (Apple's `ditto`), save a PNG/JPEG copy of an image,
  copy path. They always create new files next to the original; nothing is
  overwritten. **Shake to open:** shake a file while dragging it and the shelf opens.
- **Synced lyrics** (opt-in): current and next line under the player, from LRCLIB
  (lrclib.net). Sends only title, artist, album and length.
- **Focus (Pomodoro).** Focus / short break / long break with configurable
  lengths, cycle progress dots, today's count, and persisted session history.
- **Notes.** Your Apple Notes in the island (see *Apple Notes* below).
- **Calendar.** Upcoming events today and tomorrow, a live countdown to the next
  one, and a reminder N minutes before (EventKit, requested on Connect).
- **AI Usage.** Shown with the real Claude and Cursor app icons, read from the
  installed apps; nothing is bundled. Claude's icon gently pulses while a Claude
  Code session is active. Codex isn't installed here, so it falls back to a
  symbol. Claude Code tokens today and in the current 5-hour block,
  messages and active sessions, read from Claude Code's local logs. Codex
  rate-limit usage when Codex's session logs are present. Cursor is listed as
  unsupported. Opt-in.
- **Launcher.** Searchable commands: your apps/folders/approved Shortcuts,
  Stitchy actions (start timer, Focus, stopwatch, new note, clipboard,
  settings) and installed apps. Arrow keys + Return.
- **Camera Guard.** Indicator and alert when the camera or microphone turns on,
  with elapsed time.
- **Private sections.** Optionally lock Notes and Clipboard. They unlock with
  Touch ID or your password (LocalAuthentication). Unlocking lasts 5 minutes.
- **Touch ID animation.** Whenever Stitchy asks macOS for Touch ID, the island
  shows an animated fingerprint (ripples and a sweep) until the prompt ends, then
  a check or a cross. macOS reports no sensor events to apps, so the animation
  spans the whole system prompt. Macs without Touch ID show a lock and "Password".


### Apple Notes
Stitchy's Notes page is a lightweight window onto **Apple Notes**, not a separate
database.

- **How:** Apple Notes has no public sync framework. Its supported automation
  interface is AppleScript (the Notes scripting dictionary), which needs
  Automation consent ("Stitchy wants to control Notes"). Stitchy uses it to list
  accounts (iCloud, On My Mac, others), folders and notes; read a note's plain text
  and HTML; create notes; replace a note's text; and show a note in Notes.
  Requests run off the main thread.
- **In the island:** search, folder/account menu, list with title, folder and
  date, preview, **edit**, **New Note → Save to Apple Notes** (in the selected
  folder, or Notes' default folder), **Open in Notes**, Refresh, and
  loading/saved/error states.
- **Editing safety:** edits save to Apple Notes after a short pause. Before
  writing, Stitchy checks the note's modification date; if it changed in Notes
  meanwhile, Stitchy stops and offers **Reload** instead of overwriting.
  **Locked notes**, notes with **attachments**, and notes with formatting that plain
  text can't round-trip (lists, bold, tables…) are read-only in Stitchy, with an
  explanation and **Open in Notes**.
- **Sync:** there's no change notification, so Stitchy re-reads when you open the
  tab (at most every 20 s), on Refresh, and after its own edits.
- **Existing Stitchy notes** from 1.0 aren't touched. They appear under
  **On This Mac** with **Move to Apple Notes** (confirmed). Each note is created
  in Apple Notes first, and the local copy is removed only after Notes confirms.
- **Errors handled:** Automation denied (link to Privacy settings), Notes
  unavailable, deleted notes, folder missing on create.
- **Limitations:** no attachments or drawing; no rich-text editing; no sharing or
  locking; the "Recently Deleted" folder is hidden (matched by its English name);
  folders nested more than one level aren't listed separately; very large
  libraries list the 150 most recent matches; the first request may launch Notes
  in the background.

## What's new in 1.3

- **Music player redesign.** Large artwork that crossfades between tracks, a
  draggable scrubber with elapsed/remaining time, shuffle, previous/play/next,
  repeat (Music: off/all/one; Spotify: on/off), and a player-volume popover.
  Hover and press states throughout. Needs Automation (as before) for controls,
  artwork and seeking.
- **Lyrics, on by default.** The current line sits under the player and in the
  compact island (a strip under the notch); click it for **enlarged lyrics**:
  the current line highlighted, upcoming lines below, smooth auto-scroll, tap a
  line to jump there, chevron to collapse. Sources: LRCLIB (synced) → lyrics
  stored with Apple Music tracks (plain). Spotify shares no lyrics with other apps
  and Stitchy doesn't scrape private endpoints. Each song is looked up once and
  cached in `~/Library/Caches/Stitchy/lyrics`; "not found" is remembered for a day.
- **Weather** (Open-Meteo, free, no key): temperature, condition, feels-like,
  humidity, wind, 24 h hourly with rain chance, 7-day high/low, optional
  rain-soon alert, optional temperature in the idle island. Location only when
  you choose "Use My Location" (one fix, rounded to ~1 km), or pick a city.
  Refreshes every 30 minutes while on.
- **Focus.** Home toggle and a Focus activity. Reading uses `INFocusStatusCenter`
  (only *whether* a Focus is on; macOS doesn't reveal which). Switching uses two
  Shortcuts you pick, built with Shortcuts' "Set Focus" action, because macOS has
  no public API for apps to change Focus.
- **Calls & Messages** (opt-in, Accessibility). See below.
- **Interaction polish.** One shared spring: hover lift, press-down, brightness;
  opacity-only with Reduce Motion. Applied to every Stitchy button, rows and cards.
- **Network speed** (↓/↑) on Home, sampled once a second only while Home is visible.
- **Clipboard:** search, **pin** items (kept past the limit and through Clear),
  smart actions for links (open), emails (compose) and hex colours (swatch).
- **Reliability:** Apple Events now have a timeout and one queue per app, with a
  30 s back-off, so an unresponsive Spotify can't freeze Notes or Music (seen
  during testing). The visualizer is back on Core Animation (0.06 % CPU together
  with the lyric strip; a 30 fps SwiftUI Canvas cost 6–13 %).

### Calls & Messages
macOS has no public API for other apps' calls or messages. When you turn this on
(Settings › Features), Stitchy explains why it needs **Accessibility**, then uses
it only to observe the Notification Center process and read the text of new
banners from Messages, FaceTime and Phone (other apps only if you allow).
- Messages: sender and preview (or sender only with "Hide previews"), arrival
  alert, recent item on Home.
- Calls: caller in the island; **Accept / Decline** only when the banner itself
  has those buttons (Stitchy presses the banner's real button); call timer
  while active; End clears it.
- Nothing is saved or uploaded; the last 10 items stay in memory. Replying isn't
  supported.
- Banner layouts can change between macOS versions; parsing is heuristic.

### Lock screen island (private API, opt-out)
At your request, Stitchy now shows the island on the lock screen using the
approach from [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow)
(MIT, Lakr Aream; licence in `ThirdParty/SkyLightWindow-LICENSE`). I reviewed
its source (370 lines, no network or obfuscated code) and vendored only the
part that moves a window, in `Windows/LockScreenPresenter.swift`:
- `dlopen`s the **private** SkyLight framework and calls `SLSMainConnectionID`,
  `SLSSpaceCreate`, `SLSSpaceSetAbsoluteLevel` (level 400, the one Notification
  Center uses on the lock screen), `SLSShowSpaces` and
  `SLSSpaceAddWindowsAndRemoveFromSpaces`, plus the public
  `NSWindow.canBecomeVisibleWithoutLogin`.
- Unlike the original, every symbol is checked: if a future macOS removes one,
  the feature turns itself off instead of crashing.
- It doesn't touch the login window or authentication.
- **While locked** (from the public `com.apple.screenIsLocked` notification) the
  island shows only Now Playing (with lyrics and controls) or the time. Tabs,
  notes, clipboard, shelf, file drops, launcher, hotkey and settings are disabled
  until you unlock.
- Settings › Island › "Show on the Lock Screen" (on by default). Turning it off
  applies after restarting Stitchy.
- Verified here: all calls returned 0 on macOS 26.5 and the island works
  normally while unlocked. **Not yet verified while locked**: that needs you to
  lock the Mac.

### Weather tab
Apple's Weather app has no scripting interface, and WeatherKit needs a paid Apple
Developer membership plus an entitlement this ad-hoc-signed build can't carry,
so data comes from Open-Meteo. The tab is modelled on Weather.app: a sky
gradient by condition and time of day, city, huge thin temperature, condition
and H/L; an hourly card with a one-line summary ("Rain likely around 10 PM.");
a 10-day forecast with temperature-range bars and today's current-temperature
dot; and Feels Like, Humidity, Wind, UV Index and Sunrise/Sunset tiles.

### Up Next
A list button in the player opens the queue.
- **Apple Music:** the next tracks of the current playlist via Music's scripting
  dictionary. Music doesn't expose its shuffled order or its own Up Next list,
  and the view says so when shuffle is on.
- **Spotify:** the app exposes no queue, so Stitchy uses Spotify's Web API
  (`GET /v1/me/player/queue`). One-time setup in Settings › Features › Music:
  create a free app in the Spotify Developer Dashboard, add the redirect URI
  `http://127.0.0.1:43117/callback`, paste its Client ID, and click Connect.
  Sign-in uses OAuth with PKCE (no secret) and a one-time local callback. The
  scope is read-only playback state, and the refresh token is kept in the
  Keychain (`app.stitchy.spotify`).

## Permissions

Requested only when you first use the feature that needs it:

| Feature | Permission | When |
|---|---|---|
| Timer / Focus / meeting notifications | Notifications | First timer start |
| Music artwork, progress, controls | Automation (Music / Spotify) | "Enable Controls" in the Music tab |
| Download progress | Files & Folders → Downloads | Turning Downloads on |
| Calendar | Calendars (full access) | "Connect Calendar" |
| Private sections, sensitive actions | Touch ID / password (LocalAuthentication, per use) | When you unlock or change a protected setting |
| Apple Notes | Automation (Notes) | "Connect Apple Notes" in the Notes tab |
| Weather by location (optional) | Location (once) | "Use My Location" in the Weather tab |
| Focus status | Focus | "Allow…" in Settings › Features › Focus |
| Focus switching | Runs Shortcuts you pick | Settings › Features › Focus |
| Calls & Messages | Accessibility | Turning the feature on (after an explanation) |
| Bluetooth devices | Bluetooth | First launch with the feature on |
| Spotify Up Next | Spotify sign-in (your own Client ID) | "Connect Spotify…" in Settings |
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
    AIUsage/  Launcher/ (+ GlobalHotkey)  Auth/ (SystemAuth, SensitiveGate, PrivateLock)
  Settings/       Toolbar-tab preferences: General, Island, Features, Clipboard,
                  Launcher, Privacy
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
- Build clean in Swift 6 mode; **64/64 tests pass** (opt-in live checks: `STITCHY_REAL_USAGE=1`, `STITCHY_LIVE_NET=1`).
- 1.3 verified: live Spotify sync and synced lyrics from LRCLIB for real songs
  (56- and 32-line lyrics, cached); live Open-Meteo forecast; Apple Events
  timeout recovering from an unresponsive Spotify; 0.05 % CPU / 15 MB with music
  playing; permissions kept across rebuilds.
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

**Notes (1.1), verified here:**
- Notes scripts compiled against the real Notes dictionary with `osacompile`.
  Notes list parsing (accounts, folders, lock state, dates, Recently Deleted
  skipped), HTML conversion/escaping, AppleScript string escaping and
  editability detection are unit-tested.
- 33/33 tests pass; app builds and launches; idle CPU 0 % with Settings open
  after fixing a Settings sizing loop (was ~5 %).

**Needs manual testing on your Mac** (needs a consent prompt or Touch ID):
- Touch ID animation: unlocking private sections, a protected setting, cancelling the prompt.
- Require Authentication for Sensitive Actions: each protected change asks once.
- Touch ID availability vs password fallback (MacBook Neo keyboard dependent).
- Apple Notes: Connect (Automation prompt), list/search/folders across iCloud and
  On My Mac, create a note, edit a plain note, conflict after editing the same
  note in Notes, Open in Notes, Automation denied state.
- Calendar; Camera Guard with a real app; private-section unlock.
- Music controls/artwork with Apple Music; real downloads; outgoing AirDrop.
- Full-screen hiding, display changes, launch at login, animation feel.

## Known limitations

- **Lock screen island** uses private SkyLight APIs (see above); Apple can break
  it in any update. Stitchy never touches the login window or types your
  password.

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
- **Touch ID animation** can't see the finger on the sensor (no public API); it
  runs for as long as the macOS prompt is open.
- **Apple Notes** has no public sync API; Stitchy uses the Notes AppleScript
  interface, so rich content, attachments and locked notes must be edited in Notes.
- Clicks within ~60 ms of the pointer arriving can reach the menu bar under
  the notch before WindowServer applies the panel's click-through change.

## Debugging

```bash
log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info
.build/arm64-apple-macosx/release/Stitchy --snapshots /tmp/stitchy-snaps   # render states to PNG
STITCHY_REAL_USAGE=1 Scripts/test.sh --filter realLogs                    # usage scan on real logs
```
