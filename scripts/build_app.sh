#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Simple Spotlight.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$MACOS"
cp ".build/$CONFIG/SimpleSpotlight" "$MACOS/SimpleSpotlight"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "$APP"
