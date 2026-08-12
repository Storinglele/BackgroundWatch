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
chmod +x "$APP/Contents/MacOS/BackgroundWatch"
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
