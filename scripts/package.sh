#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
STAGING="$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "dist/Important Todo.app" "$STAGING/Important Todo.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Important Todo" -srcfolder "$STAGING" -ov -format UDZO "dist/ImportantTodo-local.dmg"
echo "DMG: $PWD/dist/ImportantTodo-local.dmg (not notarized by this script)"
