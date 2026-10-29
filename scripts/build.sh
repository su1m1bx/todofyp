#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/ImportantTodo"
APP="$PWD/dist/Important Todo.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/ImportantTodo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "$SIGNING_IDENTITY" --options runtime --entitlements Resources/ImportantTodo.entitlements)
if [[ "$SIGNING_IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--timestamp); fi
codesign "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "App: $APP (identity: $SIGNING_IDENTITY; '-' means local ad-hoc, not notarized)"
