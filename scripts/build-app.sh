#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building TZBar (release)…"
swift build -c release

APP="$ROOT/TZBar.app"
BIN="$ROOT/.build/release/TZBar"
PLIST="$ROOT/packaging/Info.plist"

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TZBar"
chmod +x "$APP/Contents/MacOS/TZBar"
cp "$PLIST" "$APP/Contents/Info.plist"

echo "Built $APP"
echo "Run: open \"$APP\""
