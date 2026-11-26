# Architecture


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
    Extensions/ (model, store, data + feeds, renderer, editor, automations, sharing)
    Focus/ (+ DNDHotkey)  Weather/  Capture/  Tools/  Devices/  DevActivity/  ...
  Settings/       Toolbar-tab preferences: General, Island, Features, Clipboard,
                  Launcher, Privacy, Extensions
Tests/StitchyTests  Swift Testing suites for timers, clipboard, notes, downloads,
                    usage scanning, geometry, settings reset, lyrics, extensions
                    (model, data, feeds, templates, automations, sharing) and more
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


### Extensions
Extensions are pure data (`ExtensionModel.swift`): a data source, extra sources, a
component tree and automations, saved as a versioned JSON envelope in
`~/Library/Application Support/Stitchy/extensions.json`. Nothing in an extension
can run code. `ExtensionDataService` polls only enabled extensions, caches each
response in `~/Library/Caches/Stitchy/extensions/`, and backs off on errors and
HTTP 429. `ExtensionRenderer` draws the tree recursively in SwiftUI; the editor
reuses the same renderer with selection and drop hooks through the environment.
See [Extensions](EXTENSIONS.md) for the format.

### Lock screen
`LockScreenPresenter` moves windows into a private SkyLight space at the lock
screen level. `LockScreenArtController` shows the full-screen art (click-through)
and the player (clickable). Neither window can become key, so typing always
reaches the macOS password field.
