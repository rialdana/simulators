#!/bin/bash
# Builds Simulators.app and installs it to /Applications (or ~/Applications).
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "› generating icon..."
  mkdir -p Resources build/AppIcon.iconset
  swift scripts/make-icon.swift build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d" build/icon-1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "› compiling..."
swift build -c release

echo "› bundling..."
APP="build/Simulators.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Simulators "$APP/Contents/MacOS/Simulators"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" 2>/dev/null

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "› installing to $DEST/Simulators.app..."
if pgrep -xq Simulators; then
  pkill -x Simulators
  sleep 1
fi
rm -rf "$DEST/Simulators.app"
cp -R "$APP" "$DEST/Simulators.app"

echo "✓ done — launch with: open '$DEST/Simulators.app'"

# Old versions of `sim update` run their own (pre-pull) update logic but run
# this script fresh from the pull — the one hook old code gives new code. Use
# it to true up the MCP registration on machines that predate auto-setup.
# Idempotent; --repair respects a registration the user removed on purpose.
../sim mcp --repair >/dev/null 2>&1 || true
