#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building TZMenu (release)…"
swift build -c release

APP="$ROOT/TZMenu.app"
BIN="$ROOT/.build/release/TZMenu"
PLIST="$ROOT/packaging/Info.plist"

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/TZMenu"
chmod +x "$APP/Contents/MacOS/TZMenu"
cp "$PLIST" "$APP/Contents/Info.plist"

echo "Built $APP"
echo "Run: open \"$APP\""
