# Stitchy: Audit and Roadmap

Audit date: 2026-11-25. Codebase: ~11,000 lines of Swift 6 (SwiftUI + AppKit),
macOS 14+, no package dependencies. One vendored file: `LockScreenPresenter.swift`
(adapted from SkyLightWindow, MIT, licence in `ThirdParty/`). Build with
`Scripts/build-app.sh`; tests with `Scripts/test.sh` (Swift Testing).

Stitchy is free, open source and macOS-only. There are no paid tiers and no
iPhone or iPad app. Features are optional; disabled features stop their monitors.

## Architecture (as found)

| Layer | Where | Notes |
|---|---|---|
| App entry, menu bar item | `App/` | Agent app (no Dock icon) |
| Services container | `Core/AppServices.swift` | Owns every service; `applyFeatureToggles()` starts/stops monitors from settings |
| Settings | `Core/AppSettings.swift` | One `@Observable` store over UserDefaults; security settings change only through `SensitiveGate` / `PrivateLock` |
| Activities and alerts | `Core/IslandActivity.swift`, `Core/ActivityEvent.swift`, `Features/Notifications/ActivityFeed.swift` | One `post(_:)` path for feed and alerts |
| Island UI | `Island/` | One morphing `NotchShape`: compact, hover, live, alert, HUD, expanded |
| Windows | `Windows/` | Non-activating panel, lock screen presenter, island controller |
| Shared components | `Island/Components.swift` | `PressableStyle`, `PlainHitStyle`, `IconButton`, `PillButton`, `Tile`, glass backgrounds |
| Features | `Features/<Name>/` | Independent modules |

## Feature inventory

Status: **Done** = implemented and working; **Partial** = works but has gaps; **Missing**.

### Island interface (spec section 3)
| Feature | Status | Notes |
|---|---|---|
| Compact / expanded states, smooth morph | Done | Spring animations, blur-replace transitions |
| Contextual live activities | Done | Timers, music, transfers, privacy, focus, weather |
| Notification presentation (alerts) | Done | Transient alerts with feed history |
| Multiple displays | Done | Display choice in Island settings |
| Notch and notchless Macs | Done | Notch style and Dynamic Island pill style |
| Activation behaviour | Done | Hover, click, collapse on exit, hotkey |
| Appearance | Done | Width, height, offset, style |
| Animation behaviour | Done | Animation style setting, Reduce Motion respected |
| Lock screen island | Done | Private SkyLight API, may break on macOS updates |

### File shelf (section 4)
| Feature | Status | Notes |
|---|---|---|
| Drop in, hold, drag out, multiple files | Done | Plus shake-to-open while dragging |
| Previews, file info, copy path, remove one | Done | |
| Zip, PNG/JPEG copies, open, reveal, AirDrop | Done | Never overwrites: `uniqueURL` |
| Screenshots to shelf | Done | Spotlight query, opt-in |
| Reorder files | Done | Phase A: drag onto a tile |
| Resize images | Done | Phase A: resized copy, original untouched |
| PDF merge, image compression | Done | Phase D: "PDF" on the shelf combines PDFs and images in order; compressed JPEG copy |
| Video compression | Done | Phase D: HEVC 1080p copy (hardware encoder) |
| Local sharing | Partial | AirDrop only; LocalSend protocol not planned |
| Finder context menu | Done | Phase D: Services › "Add to Stitchy Shelf" (may need a log-out/in to appear the first time) |

### Clipboard (section 5)
| Feature | Status | Notes |
|---|---|---|
| Text, images, files, links, colours, emails | Done | Smart detection |
| Search, re-copy, pins, limit, clear | Done | |
| Exclude sensitive content | Done | Concealed types and password managers excluded |
| Off by default, no monitoring when off | Done | |
| Code snippet detection | Done | Phase A: icon and monospaced preview |

### Music and media (section 6)
| Feature | Status | Notes |
|---|---|---|
| Now Playing: art, title, artist, progress, controls | Done | Apple Music and Spotify (AppleScript) |
| Volume, shuffle, repeat | Done | Where the player supports it |
| Visualiser | Done | Core Animation, near-zero CPU |
| Up Next queue | Done | Apple Music via AppleScript; Spotify via Web API (user's own Client ID) |
| Reorder queue / play next | Partial | Apple Music has no scripting for reorder; Spotify API can add to queue only |
| Synced lyrics, LRCLIB, expanded, compact strip | Done | Enabled by default |
| Floating player | Done | Mini and Player sizes |
| Per-app volume | Done | CoreAudio process taps (macOS 14.2+) |
| Audio output selection | Done | Phase B: picker in the App Volume panel |
| Other players (e.g. browser media) | Not possible | No public "now playing" API for third-party apps |

### Notifications and activities (section 7)
| Feature | Status | Notes |
|---|---|---|
| Downloads, Bluetooth, drives, timers, music | Done | |
| Calls and messages mirroring | Done | Accessibility banner reading, opt-in |
| Activity history, dismiss | Done | Activity tab with unread badge |
| Duplicate prevention | Done | Phase F: central filter in `AppServices.post` |
| Xcode build completion | Done | Phase C: opt-in alert with scheme, time, errors/warnings (reads `LogStoreManifest.plist`) |
| Coding-agent activity | Done | Phase C: opt-in live status (tool + file name only) and finish alerts for Claude Code; Codex from its documented log format, not tested against a real Codex log here |

### System utilities (section 8)
| Feature | Status | Notes |
|---|---|---|
| Volume / mute / output HUD | Done | |
| Brightness, keyboard backlight HUD | Not possible | No public API to read or observe them |
| Battery: percent, charging, low alerts | Done | |
| Connected-device batteries | Partial | Bluetooth list only; battery levels need private IOKit keys for some devices (Phase B investigate) |
| CPU, memory, history graphs | Done | Phase A: 1-minute sparklines on Home, sampled only while visible |
| GPU information | Done | Phase B: utilisation from IOKit `PerformanceStatistics` (hidden if the driver reports none) |
| Network activity | Done | Live up/down rates |
| Keep Awake | Done | Phase A: 15 min to 8 h or until off, time left shown |
| Bluetooth list and connect/disconnect alerts | Done | |
| Drives: mount/eject alerts, one-click eject, failure handling | Done | |
| Mic mute for all apps | Done | |
| Do Not Disturb toggle | Done | Through Shortcuts Stitchy creates (no public Focus API) |
| Dock window previews | Done | Opt-in, Accessibility + Screen Recording |
| Window snapping | Done | Phase B: keyboard shortcuts, halves/quarters/thirds/two-thirds/maximize/center/next display; drag-to-edge not included |
| Pointer edge gestures, smooth mouse scrolling | Skipped | Needs global event taps that rewrite input; fragile and invasive |

### Productivity (section 9)
| Feature | Status | Notes |
|---|---|---|
| Calendar: upcoming events, reminders | Done | |
| Notes: quick notes, autosave, Apple Notes sync | Done | |
| Notes: Markdown, search | Done | Phase D: Markdown preview with headings, lists, quotes, code; search already existed |
| Timers: multiple, stopwatch, Pomodoro, custom, notifications | Done | |
| Weather: current, forecast, location | Done | Open-Meteo (WeatherKit needs a paid membership) |
| Launcher (apps, folders, Shortcuts, actions) | Done | |
| Calculator | Done | Phase B: Tools tab, basic + scientific, history |
| Quick translate | Done | Phase D: Tools › Translate, on-device (macOS 15+) |
| Emoji picker | Missing | Phase D (system Character Viewer can be opened; own picker optional) |
| Break / breathing reminders | Done | Phase D: opt-in, counts active time only, quiet during calls |
| Teleprompter | Missing | Phase E |
| Simple task lists | Done | Phase D: `- [ ]` checklists in notes, tick them in preview |
| Obsidian, Things, Plane | Partial | Phase E: Launcher "todo …" → Things, "obsidian …" → Obsidian (URL schemes). Plane skipped: needs an account token for a niche tool |

### Developer tools (section 10)
| Feature | Status | Notes |
|---|---|---|
| Base64, JSON, hashes, JWT, URL, timestamp, colour, QR, UUID | Done | Phase B: Tools tab › Developer |
| AI usage indicators | Done | Claude Code and Codex from local logs |
| Xcode build monitoring | Done | Phase C; build start isn't detectable from logs, so completion only |
| MCP server | Skipped | Large security surface (other apps driving Stitchy); revisit only on demand |
| Terminal | Skipped | Terminal.app does it better; running commands from the island adds risk for little gain |

### Capture (section 11)
| Feature | Status | Notes |
|---|---|---|
| OCR from screen region, images, PDFs | Done | Phase C: Tools › Capture, Launcher action, shelf right-click |
| Screenshot annotation (arrows, text, blur) | Done | Phase E: arrow, box, text, pixelate; Save Copy never overwrites |
| Camera preview | Done | Phase E: Camera Mirror floating window; camera runs only while open |
| Voice transcription | Done | Phase E: Dictate to clipboard; on-device when the language supports it |
| Background removal | Done | Phase C: transparent PNG copy, original untouched |

### Additional (section 12)
**Phase E decisions.** Built: annotation, Camera Mirror, dictation, "Translate with
Stitchy" text Service, Launcher quick commands (calculator, Things, Obsidian).
Skipped: magnifier (macOS Zoom does it; needs constant screen capture), product-key
vault (Apple Passwords), keyboard sounds and desktop companion (novelty), app cleaner
(destructive), meeting controls (system mic mute already exists), sales and stocks
(third-party accounts or paid feeds).

Keyboard sounds, desktop companion, magnifier, product-key vault, app cleaner,
meeting controls, selected-text actions, sales dashboards, stocks: all **Missing**.
Planned for Phase E only where useful: magnifier, selected-text actions, product-key
vault (Keychain). Cleaner is destructive and needs careful review. Sales dashboards
and stocks need third-party accounts or paid data feeds and are low priority.

## Known bugs and gaps found in this audit
1. ~~Keep Awake offers only 1 hour and shows no remaining time.~~ Fixed in Phase A.
2. Alerts posted while the island is expanded are dropped (by design), so feedback
   from expanded pages must be shown inline.
3. Snapshot renders show the Core Animation visualiser as a placeholder (snapshot
   tool only, not the app).
4. ~~Dock previews assume a bottom Dock for placement.~~ Fixed in Phase F (left/right Docks).
5. ~~No central duplicate-notification filter.~~ Fixed in Phase F (same title + detail within 4 s is dropped).

## Permissions map
| Permission | Used by | When asked |
|---|---|---|
| Automation (Music, Spotify, Notes) | Music controls, Apple Notes | When you turn the feature on |
| Calendars | Calendar | When you turn it on |
| Notifications | Timers, reminders | First timer |
| Accessibility | Calls & Messages, Dock previews, window snapping | When you turn the feature on |
| Screen Recording | Dock previews, screen text capture | When you turn the feature on / first capture |
| Audio capture | Per-app volume | First time you lower an app |
| Touch ID / password | Private sections, sensitive settings | Each use |

## Roadmap

Each phase: inspect files, build one group, run tests, check no regressions,
summarise, list what's left.

- **Phase A (done): quick wins on existing features.** System monitor (CPU and memory
  with history), Keep Awake durations and remaining time, shelf reorder and
  image resize, clipboard code detection.
- **Phase B (done): Tools page.** Calculator with history, developer toolkit, audio output
  picker, window snapping, GPU stats.
- **Phase C (done): capture and dev activity.** OCR text capture, background removal,
  Xcode build monitor, live coding-agent activity.
- **Phase D (done): files and productivity.** PDF merge, image/video compression, Finder
  Services, Markdown notes with search, translate, break reminders, tasks.
- **Phase E (done): investigate, build only if worthwhile.** Annotation, transcription,
  camera preview, magnifier, selected-text actions, key vault, MCP, terminal,
  mouse gestures, integrations (Obsidian, Things, Plane).
- **Phase F (done): hardening.** Central duplicate-notification filter, Dock previews
  for left/right Docks, a complete live permissions overview (Settings › Privacy), and
  Features settings grouped by category.
- **Phase G (done): page redesign.** Group 1 done: design tokens (`DS`,
  `Well`, `SectionLabel` in `Island/Components.swift`), Home, Music, Timers.
  Group 2 done: Weather (rebuilt to fit without scrolling), Shelf, Notes, Calendar,
  plus shared `EmptyState` and `Chip`. Group 3 done: Activity (notifications as one
  list, suggestions instead of promo cards), Launcher, Tools (Calculator, Developer,
  Capture, Translate share wells and section labels).
  Original scope: Redesign each island page in
  Stitchy's own design language (Home, Music, Timers, Weather, Shelf, Notes, Calendar,
  Tools, Launcher, Activity).
