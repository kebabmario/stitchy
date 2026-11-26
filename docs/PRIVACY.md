# Privacy & permissions

Stitchy runs on your Mac. It has no account, no analytics and no server of its
own. Permissions are requested only when you turn on the feature that needs them,
and **Settings › Privacy** shows the live status of each one.

## Permissions

| Feature | Permission | Asked when |
|---|---|---|
| Timer, Focus and meeting notifications; automation alerts | Notifications | First timer start |
| Music artwork, progress, controls | Automation (Music / Spotify) | "Enable Controls" in the Music tab |
| Apple Notes | Automation (Notes) | "Connect Apple Notes" |
| Download progress | Files & Folders › Downloads | Turning Downloads on |
| Calendar | Calendars (full access) | "Connect Calendar" |
| Weather by location (optional) | Location, once, rounded to ~1 km | "Use My Location" (or pick a city instead) |
| Focus status | Focus | "Allow…" in Settings › Features › Focus |
| One-click Do Not Disturb | Accessibility; assigns the system ⌃⌥⌘D shortcut after you agree | First click on the moon |
| Calls & Messages | Accessibility | Turning the feature on, after an explanation |
| Dock previews, window snapping | Accessibility (+ Screen Recording for previews) | Turning the feature on |
| Screen text capture | Screen Recording | First capture |
| Per-app volume | Audio capture (sound is passed straight through, nothing recorded) | First time you change an app's volume |
| Camera Mirror | Camera, only while its window is open | Opening Camera Mirror |
| Dictation | Microphone + Speech Recognition | First dictation |
| Bluetooth devices | Bluetooth | First launch with the feature on |
| Clipboard history | Paste from other apps (macOS may ask) | Turning clipboard history on |
| Private sections, sensitive settings | Touch ID or password, per use | Unlocking or changing a protected setting |
| Launch at login | Login Items approval (sometimes) | Enabling it |

Camera Guard reads the public "device is running somewhere" properties, which need
no camera or microphone permission. The global shortcut uses Carbon
`RegisterEventHotKey`, which needs no Input Monitoring.

## Network

Stitchy only connects to these services, and only for the features you use:

| Service | Used for | What's sent |
|---|---|---|
| Open-Meteo (`api.open-meteo.com`, `geocoding-api.open-meteo.com`) | Weather, city search | Rounded coordinates or the city you typed |
| LRCLIB (`lrclib.net`) | Synced lyrics | Title, artist, album, length |
| iTunes Search (`itunes.apple.com`) | High-resolution cover art for Apple Music tracks | Title, artist, album |
| Spotify (`accounts.spotify.com`, `api.spotify.com`) | Up Next, only if you connect your own Spotify app | OAuth with PKCE; read-only playback scope |
| Spotify's image CDN | Higher-resolution Spotify cover art | The artwork URL Spotify provided |
| Your extensions' APIs | Extensions you enabled | Exactly the requests you configured |

## What's stored where

| Data | Location |
|---|---|
| Settings | UserDefaults (`app.stitchy.Stitchy`) |
| Local notes, extensions | `~/Library/Application Support/Stitchy/` |
| Lyrics and extension response caches | `~/Library/Caches/Stitchy/` |
| Spotify refresh token | Keychain, service `app.stitchy.spotify` |
| Extension tokens | Keychain, service `app.stitchy.extensions` |
| Clipboard history | Memory only, cleared on quit |
| Calls & Messages items | Memory only, last 10 |

## Lock screen

The lock screen island and player use private SkyLight APIs to appear above the
lock screen. Stitchy's lock screen windows never become key, so keystrokes always
reach the macOS password field. Stitchy never reads, types or stores your password
and never unlocks the Mac. You can turn the lock screen island off in
Settings › Island.

## Sensitive content

- Clipboard history skips items marked concealed or transient and ignores password
  managers by default.
- Notes and Clipboard can be locked behind Touch ID.
- Coding-agent activity shows the tool name and file name only, never file
  contents or prompts.
