# Features

Everything Stitchy does, grouped the way the island is. Features that need a
permission ask for it only when you turn them on; see [Privacy](PRIVACY.md).

- [The island](#the-island)
- [Live activities](#dynamic-island-features)
- [Pages and tools](#stitchy-features)
- [Music, lyrics and weather](#music-lyrics-and-weather)
- [Apple Notes](#apple-notes)
- [Calls & Messages](#calls--messages)
- [Lock screen](#lock-screen-island-private-api-opt-out)
- [Tools page](#tools-page)
- [Extensions](#extensions)
- [Known limitations](#known-limitations)

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

- **Side bubbles.** When more than one activity is running, the extra ones sit in
  small bubbles beside the island.
- **Touch ID card.** When Stitchy asks for Touch ID, the island opens into a
  Face ID-style card with a fingerprint animation, then a check or a cross.

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
- **Keep Awake** (15 minutes to 8 hours or until off, from Home or the launcher) and **Mic Mute** for all apps
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

- **System monitor.** CPU, memory and GPU with 1-minute history on Home, sampled
  only while Home is visible.
- **Coding agents and Xcode** (opt-in). Live status of Claude Code sessions (the
  tool and file name only) shown with the app's own icon, finish alerts, and Xcode
  build results with scheme, time and error/warning counts.
- **Per-app volume** and audio output picker (CoreAudio process taps, macOS 14.2+).
- **Floating player** in mini and full sizes.
- **Break reminders** (opt-in) that count active time only and stay quiet during calls.

## Music, lyrics and weather

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
- **Focus and Do Not Disturb.** Home toggle and a Focus activity. Reading uses
  `INFocusStatusCenter` (only *whether* a Focus is on; macOS doesn't reveal which).
  The moon button turns Do Not Disturb on and off with one click: macOS has no public
  API for that, so after you agree Stitchy assigns the system's own Do Not Disturb
  keyboard shortcut (⌃⌥⌘D) and presses it (needs Accessibility).
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


### Weather tab
Apple's Weather app has no scripting interface, and WeatherKit needs a paid Apple
Developer membership plus an entitlement this ad-hoc-signed build can't carry,
so data comes from Open-Meteo. The tab is modelled on Weather.app: a sky
gradient by condition and time of day, city, huge thin temperature, condition
and H/L; an hourly card with a one-line summary ("Rain likely around 10 PM.");
a 10-day forecast with temperature-range bars and today's current-temperature
dot; and Feels Like, Humidity, Wind, UV Index and Sunrise/Sunset tiles.


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
- **Lock screen music.** With music playing, the lock screen shows the album art
  full-bleed (high-resolution art where available, fitted to its shape), a player
  with progress, controls and volume, and a frosted **lyrics panel** on the right
  with animated line changes. Esc or the hide button tucks the player away.
- **Safety rules:** lock screen windows never become key, so keystrokes always go
  to the macOS password field; Stitchy never types or reads your password and never
  unlocks the Mac.
- Settings › Island › "Show on the Lock Screen" (on by default). Turning it off
  applies after restarting Stitchy.
- Verified on macOS 26.5 while locked and unlocked.


## Tools page

- **Calculator** (basic and scientific, with history).
- **Developer:** Base64, JSON format/validate, hashes, JWT decode, URL encode,
  timestamps, colours, QR codes, UUIDs.
- **Capture:** text from a screen region, images or PDFs (on-device OCR);
  background removal to a transparent PNG; screenshot annotation (arrow, box, text,
  pixelate); Camera Mirror; dictation to the clipboard.
- **Translate:** on-device translation (macOS 15+), also as a text Service.
- **Window snapping** with keyboard shortcuts: halves, quarters, thirds,
  two-thirds, maximise, centre, next display.
- **Shelf extras:** reorder, resize images, compress images and video (HEVC),
  merge PDFs and images into one PDF, Finder Services › "Add to Stitchy Shelf".

## Extensions

Build your own island tabs without code: connect a JSON API or RSS/Atom feed,
drag components onto a canvas, bind them to fields, style them, add alerts, and
share the result as a `.stitchyext` file. Enabled extensions appear in the
island's **Extensions** tab. Full guide: [Extensions](EXTENSIONS.md).

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

- **Do Not Disturb** works by pressing the system shortcut, so it needs
  Accessibility and the shortcut must stay assigned in System Settings › Keyboard.
- **Extensions** read data with GET requests only; they can't post data or run code.
