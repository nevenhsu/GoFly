#!/bin/bash
set -euo pipefail

APP_SOURCE="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$APP_SOURCE/../.." && pwd)"
BUILD_ROOT="$WORKSPACE_ROOT/work/gofly-mac"
APP_BUNDLE="$BUILD_ROOT/GoFly.app"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/module-cache"

mkdir -p "$BUILD_ROOT"
STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/GoFly-stage.XXXXXX")"
STAGING_BUNDLE="$STAGING_ROOT/GoFly.app"
trap 'rm -rf "$STAGING_ROOT"' EXIT
/usr/bin/xcrun swift build --disable-sandbox --package-path "$APP_SOURCE" \
  --scratch-path "$BUILD_ROOT/build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security"

PRODUCTS="$(/usr/bin/xcrun swift build --disable-sandbox --package-path "$APP_SOURCE" \
  --scratch-path "$BUILD_ROOT/build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --show-bin-path)"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources/Bridge/Legacy"
cp "$PRODUCTS/GoFlyMac" "$STAGING_BUNDLE/Contents/MacOS/GoFlyMac"
# SwiftPM resolves the resource bundle alongside the executable in this local development app.
cp -R "$PRODUCTS/GoFlyMac_GoFlyMac.bundle" "$STAGING_BUNDLE/Contents/Resources/"
cp "$APP_SOURCE/Bridge/bridge.py" "$STAGING_BUNDLE/Contents/Resources/Bridge/"
cp "$WORKSPACE_ROOT/app/LocalGo/MacSetup/localgo_device.py" "$STAGING_BUNDLE/Contents/Resources/Bridge/Legacy/"
cp "$WORKSPACE_ROOT/app/LocalGo/LICENSE" "$STAGING_BUNDLE/Contents/Resources/LocalGo-LICENSE.txt"

/usr/bin/python3 - "$WORKSPACE_ROOT" "$STAGING_BUNDLE" <<'PY'
import json
import plistlib
import sys
from pathlib import Path

root, bundle = map(Path, sys.argv[1:])
config = {
    "workspaceRoot": str(root),
    "pythonPath": str(root / "work/mac-setup-env/bin/python"),
    "developerDirectory": "/Applications/Xcode.app/Contents/Developer",
    "projectPath": str(root / "app/LocalGo/StikDebug.xcodeproj"),
    "targetBundleID": "com.neven.localgo",
    "targetName": "LocalGo 開發版",
}
(bundle / "Contents/Resources/LocalConfiguration.json").write_text(json.dumps(config, indent=2) + "\n")
info = {
    "CFBundleIdentifier": "com.neven.gofly.mac.preview",
    "CFBundleName": "GoFly",
    "CFBundleDisplayName": "GoFly",
    "CFBundleExecutable": "GoFlyMac",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "15.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
}
(bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
assert sorted(p.name for p in (bundle / "Contents/Resources/Bridge/Legacy").iterdir()) == ["localgo_device.py"]
PY

# Replace only this script's generated development artifact, after staging is complete.
if [ -e "$APP_BUNDLE" ]; then
  mv "$APP_BUNDLE" "$STAGING_ROOT/Previous.app"
fi
if ! mv "$STAGING_BUNDLE" "$APP_BUNDLE"; then
  if [ -d "$STAGING_ROOT/Previous.app" ]; then mv "$STAGING_ROOT/Previous.app" "$APP_BUNDLE"; fi
  exit 1
fi
printf 'Built local development app: %s\n' "$APP_BUNDLE"
