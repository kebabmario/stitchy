# Contributing to Stitchy

Thanks for helping. Stitchy is licensed under GPL-3.0-or-later; by contributing you
agree that your contributions are licensed the same way.

## Getting started

```bash
Scripts/build-app.sh      # build/Stitchy.app
Scripts/test.sh           # run the tests
```

See [Building](docs/BUILDING.md) and [Architecture](docs/ARCHITECTURE.md).

## Guidelines

- **No third-party dependencies.** Use Apple frameworks.
- **Swift 6 strict concurrency.** UI and services are `@MainActor`; keep blocking
  work off the main thread.
- **Privacy first.** Ask for a permission only when the user turns the feature on,
  explain why, and never upload user data. Add any new network service or
  permission to [Privacy](docs/PRIVACY.md).
- **Battery and CPU.** Prefer notifications and listeners over polling. Use Core
  Animation for continuous motion, and `Date.timelineAnchor` for `TimelineView`s.
- **Design.** Use the design tokens and components in `Island/Components.swift`
  (`DS`, `Well`, `SectionLabel`, `EmptyState`, `Chip`, `PressableStyle`).
- **Lock screen.** Lock screen windows must never become key and must never
  capture keystrokes.
- **Extensions stay data.** Never add a way for an extension to run code, read
  files, or send data.
- **Tests.** Add a test for new logic (parsers, rules, state machines). Run
  `Scripts/test.sh` before sending changes.
- **Files.** New source files start with `// SPDX-License-Identifier: GPL-3.0-or-later`.
- **Docs.** Update the relevant page in `docs/` and the changelog.
- **CI.** Every pull request runs the tests and builds the app on GitHub Actions
  (`.github/workflows/ci.yml`); it must pass before merging. See
  [docs/RELEASING.md](docs/RELEASING.md).

## Reporting bugs

Open an issue with your macOS version, Mac model, what you did, what you expected
and what happened. Logs help:

```bash
log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info
```

For security problems, see [SECURITY.md](SECURITY.md) instead.
