#!/usr/bin/env bash
# Builds NotchIsland.app into ./build and (optionally) launches it.
#   ./build.sh          release build
#   ./build.sh debug    debug build
#   ./build.sh release --run
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
RUN="${2:-}"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/NotchIsland.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS will remember permissions (Calendar, Automation).
codesign --force --sign - "$APP"

echo "✅ Built $APP"

if [[ "$RUN" == "--run" ]]; then
  pkill -x NotchIsland 2>/dev/null || true
  open "$APP"
fi
