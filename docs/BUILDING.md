# Building Stitchy

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


## App icon

The logo is a single ribbon folded into a hexagonal "S", in electric blue and ice.
Its geometry lives in `Scripts/make-logo-svg.py`:

```bash
python3 Scripts/make-logo-svg.py   # docs/logo: geometry.json, SVGs, animated SVG, preview.html
```

Outputs in `docs/logo/`: `stitchy-mark.svg` (the ribbon alone), `stitchy-icon.svg`
(on its tile), `stitchy-icon-animated.svg` (a loop: rests, unfolds, folds back, with a
shine while resting; still under Reduce Motion) and `preview.html` to watch it in a browser.
The app icon is drawn from the same `geometry.json`:

```bash
swift Scripts/make-icon.swift                 # writes Stitchy/Resources/AppIcon.icns
swift Scripts/make-icon.swift /tmp/icon.png   # preview only (1024 px and 64 px PNGs)
```

## Debugging


```bash
log stream --predicate 'subsystem == "app.stitchy.Stitchy"' --level info
.build/arm64-apple-macosx/release/Stitchy --snapshots /tmp/stitchy-snaps   # render states to PNG
STITCHY_REAL_USAGE=1 Scripts/test.sh --filter realLogs                    # usage scan on real logs
```

Developer flags:

```bash
open -n build/Stitchy.app --args --preview-lockscreen          # lock screen player on the desktop
open -n build/Stitchy.app --args --preview-lockscreen lyrics   # with the lyrics panel
```
