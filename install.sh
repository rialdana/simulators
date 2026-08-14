#!/bin/bash
# One-command install: the `sim` CLI + the Simulators.app menu bar app.
set -euo pipefail
cd "$(dirname "$0")"

# --- requirements ------------------------------------------------------------
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  echo "error: Xcode is required (it provides the iOS simulators and the Swift toolchain)." >&2
  echo "       Install it from the App Store, then run: xcode-select --install" >&2
  exit 1
fi

chmod +x sim app/build.sh

# --- sim CLI -----------------------------------------------------------------
BIN="/opt/homebrew/bin"
[ -w "$BIN" ] || BIN="/usr/local/bin"
if [ -w "$BIN" ]; then
  ln -sf "$PWD/sim" "$BIN/sim"
  echo "✓ sim CLI linked at $BIN/sim"
else
  echo "! couldn't write to $BIN — link it yourself:  ln -s \"$PWD/sim\" <somewhere on your PATH>"
fi

# --- Simulators.app ------------------------------------------------------------
app/build.sh

APP="/Applications/Simulators.app"
[ -d "$APP" ] || APP="$HOME/Applications/Simulators.app"
open "$APP"
echo "✓ Simulators.app installed and launched — look for the iPhone icon in your menu bar"
