#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# CI only: selects the newest installed Xcode with the major version Stitchy
# needs (its code uses the macOS 26 SDK). Override with XCODE_MAJOR.
set -euo pipefail
MAJOR="${XCODE_MAJOR:-26}"
[[ "$MAJOR" =~ '^[0-9]+$' ]] || { echo "XCODE_MAJOR must be a number" >&2; exit 2; }
XCODE="$(ls -d /Applications/Xcode_${MAJOR}*.app 2>/dev/null | sort -V | tail -1 || true)"
[[ -n "$XCODE" ]] || { echo "error: no Xcode ${MAJOR}.x on this runner; available:" >&2; ls -d /Applications/Xcode*.app >&2 || true; exit 1; }
sudo xcode-select --switch "$XCODE/Contents/Developer"
xcodebuild -version
swift --version
