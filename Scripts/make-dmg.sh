#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Packages a built Stitchy.app into a compressed DMG with an Applications
# shortcut, verifies it mounts and contains the app, and writes a SHA-256 file.
#
#   Scripts/make-dmg.sh [--app build/Stitchy.app] [--version 1.3.0] [--out build/dist]
#
# Version defaults to the app's StitchyBuildVersion, else CFBundleShortVersionString.
# Output: <out>/Stitchy-<version>-arm64.dmg and <out>/Stitchy-<version>-arm64.dmg.sha256
# ("+" in a version becomes "-" in file names).
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Stitchy.app"
OUT="$ROOT/build/dist"
VERSION=""
while (( $# )); do
  case "$1" in
    --app) APP="${2:?--app needs a path}"; shift 2 ;;
    --out) OUT="${2:?--out needs a path}"; shift 2 ;;
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

# The input must be a real, intact Stitchy bundle.
[[ -d "$APP" && "${APP:t}" == "Stitchy.app" ]] || die "no Stitchy.app at $APP (run Scripts/build-app.sh first)"
[[ -x "$APP/Contents/MacOS/Stitchy" && -f "$APP/Contents/Info.plist" ]] || die "$APP is not a complete app bundle"
codesign --verify --strict "$APP" || die "$APP has an invalid signature"

PLIST="$APP/Contents/Info.plist"
if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :StitchyBuildVersion' "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
fi
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$' ]] || die "unexpected version: $VERSION"
FILE_VERSION="${VERSION//+/-}"
NAME="Stitchy-$FILE_VERSION-arm64"

mkdir -p "$OUT"
OUT="${OUT:A}"
DMG="$OUT/$NAME.dmg"
STAGE="$(mktemp -d -t stitchy-dmg)"
MOUNT="$(mktemp -d -t stitchy-mnt)"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGE" "$MOUNT"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

# Layout: the app, a shortcut to /Applications, and a short note for unsigned builds.
ditto "$APP" "$STAGE/Stitchy.app"
ln -s /Applications "$STAGE/Applications"
if ! codesign -dv "$APP" 2>&1 | grep -q '^Authority=Developer ID Application'; then
  cat > "$STAGE/If Stitchy won't open.txt" <<'TXT'
This build of Stitchy isn't signed with an Apple Developer ID or notarized.

1. Drag Stitchy into Applications.
2. Open Stitchy. If macOS says it can't be opened, go to
   System Settings > Privacy & Security and click "Open Anyway".
   Or run in Terminal:  xattr -dr com.apple.quarantine /Applications/Stitchy.app

Stitchy is open source: https://github.com/kebabmario/stitchy
TXT
fi

rm -f "$DMG" "$DMG.sha256"
hdiutil create -quiet -volname "Stitchy $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

# Verify: it mounts, and the app inside is complete and still validly signed.
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
[[ -x "$MOUNT/Stitchy.app/Contents/MacOS/Stitchy" ]] || die "Stitchy.app missing from the mounted DMG"
[[ -L "$MOUNT/Applications" ]] || die "Applications shortcut missing from the mounted DMG"
codesign --verify --strict "$MOUNT/Stitchy.app" || die "the app inside the DMG fails signature verification"
hdiutil detach "$MOUNT" -quiet

(cd "$OUT" && shasum -a 256 "$NAME.dmg" > "$NAME.dmg.sha256")
echo "Wrote $DMG"
echo "SHA-256: $(cut -d' ' -f1 < "$DMG.sha256")"
