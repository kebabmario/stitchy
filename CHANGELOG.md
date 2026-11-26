# Changelog

All notable changes to Stitchy. Dates are in UTC.

## Unreleased

### Added
- **Extensions:** a visual, no-code creator for your own island tabs.
  - Data from JSON APIs and RSS/Atom/XML feeds, up to 12 extra APIs per extension
    that can use values from earlier responses (`$name` bindings, `{path}` in query
    values and URL path segments, `{@now|date-7}` dates).
  - 15 components, drag-and-drop editor with layers, live preview and inspector.
  - Merged lists (several sources, newest first, duplicates removed, `@source`
    labels), clickable components, fallback paths (`a ?? b`), relative dates,
    line limits, missing fields hide themselves.
  - Automations: WHEN data refreshes / IF conditions / THEN island alert or
    notification, edge-triggered with cooldowns.
  - Import and export as `.stitchyext`, never including tokens or secrets;
    imports arrive disabled.
  - Custom icons: about 100 symbols, a drawn rocket, or your own image.
- One-click **Do Not Disturb** using the system shortcut (⌃⌥⌘D) after you agree.
- New app icon.
- Documentation set and the GPL-3.0-or-later license.

## 2026-11-25

- Full-screen **lock screen music**: full-bleed high-resolution album art fitted to
  its shape, larger player, frosted lyrics panel on the right with animated line
  changes, Esc to hide the player.
- Face ID-style Touch ID card in the island.
- Activity side bubbles, a nicer coding-agent activity with app icons and a
  loading ring, richer live activities, battery colours.
- Phases A–G: system monitor, Keep Awake durations, shelf reorder/resize, Tools page
  (calculator, developer tools, window snapping, GPU stats), OCR and background
  removal, Xcode and coding-agent monitors, PDF merge and media compression, Finder
  Services, Markdown notes and checklists, translate, break reminders, annotation,
  Camera Mirror, dictation, notification de-duplication, permissions overview,
  and a redesign of every island page.
- Removed Face Unlock.

## 2026-11-23

- Island attached to the top edge, activity system with priorities, lock screen
  island, Calls & Messages, Weather tab, Up Next, music player redesign with
  lyrics, clipboard pins and smart actions.
- First version: a native Dynamic Island for notchless Macs.
