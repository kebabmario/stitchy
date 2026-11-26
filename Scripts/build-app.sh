#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds Stitchy.app from the Swift package without needing the Xcode IDE.
#   Scripts/build-app.sh            -> build/Stitchy.app (release, arm64)
#   Scripts/build-app.sh --install  -> also copies it to ~/Applications
#   Scripts/build-app.sh --debug    -> debug configuration
# Signing: uses $STITCHY_SIGN_IDENTITY if set, otherwise ad-hoc ("-").
# Note: ad-hoc signatures change on every build, so macOS may ask for
# Automation / Downloads permissions again after a rebuild.
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="release"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --debug) CONFIG="debug" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$ROOT"
swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)/Stitchy"

APP="$ROOT/build/Stitchy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Stitchy"
cp "$ROOT/Stitchy/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Stitchy/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Stitchy/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${STITCHY_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  # Ad-hoc signatures default to a designated requirement of the exact
  # cdhash, so macOS treats every rebuild as a new app and forgets
  # Calendar, Automation, Camera and Downloads permissions. Pin the
  # requirement to the bundle identifier instead so grants survive rebuilds.
  # (A real Apple Development certificate is stronger; see README.)
  codesign --force --sign - --timestamp=none \
    --requirements '=designated => identifier "app.stitchy.Stitchy"' "$APP"
else
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (signed with: $IDENTITY)"

if (( INSTALL )); then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Stitchy.app"
  cp -R "$APP" "$HOME/Applications/Stitchy.app"
  echo "Installed to $HOME/Applications/Stitchy.app"
fi
