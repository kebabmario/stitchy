#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Runs the unit tests using the Swift Testing framework that ships with the
# Command Line Tools (works without the full Xcode IDE).
set -euo pipefail
cd "${0:A:h:h}"
DEV=/Library/Developer/CommandLineTools/Library/Developer
# With full Xcode selected (CI), Swift Testing is found automatically.
if [[ "$(xcode-select -p 2>/dev/null)" == */CommandLineTools && -d "$DEV/Frameworks/Testing.framework" ]]; then
  swift test -Xswiftc -F$DEV/Frameworks -Xlinker -F$DEV/Frameworks \
    -Xlinker -rpath -Xlinker $DEV/Frameworks -Xlinker -rpath -Xlinker $DEV/usr/lib "$@"
else
  swift test "$@"
fi
