#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_BUNDLE=".build/ThinkingCaps.app"
DMG_STAGING=".build/dmg-staging"
DMG_PATH=".build/ThinkingCaps.dmg"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "App bundle not found at $APP_BUNDLE. Run build_app.sh first." >&2
    exit 1
fi

rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create -volname "ThinkingCaps" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"

echo "Built $DMG_PATH"
