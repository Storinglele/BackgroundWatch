#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift build -c release
# Ask SwiftPM for the path instead of hardcoding an architecture triple.
BIN="$(swift build -c release --show-bin-path)/BackgroundWatch"
APP="$ROOT/BackgroundWatch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BackgroundWatch"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/BackgroundWatch"
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"

if [[ "${1:-}" == "--install" ]]; then
  # The build output is invisible to Finder and Launchpad; the app only shows up in the
  # Applications list once it actually lives there.
  DEST="/Applications/BackgroundWatch.app"
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  echo "$DEST"
fi
