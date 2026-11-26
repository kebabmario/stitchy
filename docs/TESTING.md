# Testing

```bash
Scripts/test.sh                              # all tests (Swift Testing, works with just the Command Line Tools)
Scripts/test.sh --filter Extension           # one area
STITCHY_REAL_USAGE=1 Scripts/test.sh --filter realLogs   # AI usage scan against your real logs
STITCHY_LIVE_NET=1 Scripts/test.sh           # also run checks that use the network
```

## What the tests cover

98 tests in Swift Testing, including:

- **Island:** notch height, settings reset keeping user data, Dock panel placement,
  battery sliver.
- **Timers:** countdowns sorted by urgency, pause/resume, stopwatch, Pomodoro cycles.
- **Clipboard:** pins surviving limit and clear, smart actions, code detection.
- **Notes:** local store persistence and search, Markdown and checklists.
- **Shelf and files:** zip and conversions never overwrite, PDF merge, JPEG and HEVC
  compression, background removal, tracked folders skip partial files, screenshots.
- **Downloads:** real `Progress` publishing, partial-file completion.
- **Music:** LRC lyrics parsing, disk cache, embedded-lyrics fallback, Spotify OAuth
  (PKCE, callback), Up Next parsing, high-resolution artwork, lock screen layout.
- **Weather:** forecast parsing, request contents, sunrise/sunset/UV.
- **Tools:** calculator, developer tools, window snap layouts, OCR, launcher quick
  commands, annotation.
- **Monitors:** AI usage scanning, Codex rate limits, coding-agent logs, Xcode
  builds, CPU load, AirPods battery parsing, duplicate notification filter,
  Calls & Messages banner parsing.
- **Extensions:** tree editing, store persistence and duplication, JSON paths and
  fallbacks, field discovery, fetcher rules (https, localhost, size limits),
  RSS/Atom/XML parsing and HTML stripping, merged/sorted/de-duplicated lists,
  URL path templates that can't change the host, `{@now}` date filters,
  automations (conditions, edge triggering, cooldown), export without secrets,
  import safety, old-format decoding, icon images.

Apple Notes scripting, Calendar, Touch ID, Camera Guard and lock screen behaviour
need a real Mac and consent prompts, so they're checked by hand.

## Verified by hand

The notes below were recorded while developing earlier versions on a MacBook
(macOS 26.5). Test counts in them are from that time.

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


**Extensions, verified live:** a Space Launches extension (The Space Devs +
Open-Meteo) and a Tech Radar extension (Hacker News Firebase and search APIs,
GitHub REST, Ars Technica RSS, The Verge Atom) were exported, imported back and
fetched live: 13 sources in about 5 seconds with no errors, and rendered with live
data and with all sources missing.
