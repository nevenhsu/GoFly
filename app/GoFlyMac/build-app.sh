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
/usr/bin/xcrun swift build --disable-sandbox --package-path "$WORKSPACE_ROOT/app/GoFly" \
  --scratch-path "$BUILD_ROOT/validator-build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --product GoFlyTransferValidator
VALIDATOR_PRODUCTS="$(/usr/bin/xcrun swift build --disable-sandbox --package-path "$WORKSPACE_ROOT/app/GoFly" \
  --scratch-path "$BUILD_ROOT/validator-build" --cache-path "$BUILD_ROOT/cache" \
  --config-path "$BUILD_ROOT/config" --security-path "$BUILD_ROOT/security" --show-bin-path)"
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources/Bridge/Device" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Setup" "$STAGING_BUNDLE/Contents/Resources/Bridge/Reinstall" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Backup" "$STAGING_BUNDLE/Contents/Resources/Bridge/Management"
cp "$PRODUCTS/GoFlyMac" "$STAGING_BUNDLE/Contents/MacOS/GoFlyMac"
cp "$VALIDATOR_PRODUCTS/GoFlyTransferValidator" "$STAGING_BUNDLE/Contents/MacOS/GoFlyTransferValidator"
# SwiftPM resolves the resource bundle alongside the executable in this local development app.
cp -R "$PRODUCTS/GoFlyMac_GoFlyMac.bundle" "$STAGING_BUNDLE/Contents/Resources/"
cp "$APP_SOURCE/Bridge/bridge.py" "$STAGING_BUNDLE/Contents/Resources/Bridge/"
cp "$APP_SOURCE/Bridge/Setup/__init__.py" "$APP_SOURCE"/Bridge/Setup/setup_*.py \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Setup/"
cp "$APP_SOURCE/Bridge/Reinstall/__init__.py" "$APP_SOURCE"/Bridge/Reinstall/reinstall_*.py \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Reinstall/"
cp "$APP_SOURCE/Bridge/Backup/__init__.py" "$APP_SOURCE/Bridge/Backup/bridge.py" \
  "$APP_SOURCE/Bridge/Backup/catalog.py" "$APP_SOURCE/Bridge/Backup/protocol.py" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Backup/"
cp "$APP_SOURCE/Bridge/Management/__init__.py" "$APP_SOURCE"/Bridge/Management/management_*.py \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Management/"
cp "$APP_SOURCE/Bridge/Device/gofly_device.py" "$STAGING_BUNDLE/Contents/Resources/Bridge/Device/"

/usr/bin/python3 - "$WORKSPACE_ROOT" "$STAGING_BUNDLE" "$APP_BUNDLE" "$VALIDATOR_PRODUCTS" <<'PY'
import json
import hashlib
import plistlib
import sys
from pathlib import Path

root, bundle, final_bundle, validator_products = map(Path, sys.argv[1:])
config = {
    "workspaceRoot": str(root),
    "pythonPath": str(root / "work/mac-setup-env/bin/python"),
    "developerDirectory": "/Applications/Xcode.app/Contents/Developer",
    "projectPath": str(root / "app/GoFly/GoFly.xcodeproj"),
    "targetBundleID": "com.neven.gofly",
    "targetName": "GoFly",
}
(bundle / "Contents/Resources/LocalConfiguration.json").write_text(json.dumps(config, indent=2) + "\n")
setup_config = dict(config, stateRoot=str(Path.home() / "Library/Application Support/GoFlySetup"))
(bundle / "Contents/Resources/SetupConfiguration.json").write_text(json.dumps(setup_config, indent=2) + "\n")
reinstall_config = dict(setup_config, validatorPath=str(final_bundle / "Contents/MacOS/GoFlyTransferValidator"))
(bundle / "Contents/Resources/ReinstallConfiguration.json").write_text(json.dumps(reinstall_config, indent=2) + "\n")
info = {
    "CFBundleIdentifier": "com.neven.gofly.mac.development",
    "CFBundleName": "GoFly",
    "CFBundleDisplayName": "GoFly",
    "CFBundleExecutable": "GoFlyMac",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "0.3.0",
    "CFBundleVersion": "3",
    "LSMinimumSystemVersion": "15.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
}
(bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
assert sorted(p.name for p in (bundle / "Contents/Resources/Bridge/Device").iterdir()) == ["gofly_device.py"]

# The manifest is intentionally closed: every Python source copied into the
# bundle, all three generated bridge configurations, and the validator are
# fixed inputs.  Reopen each staged copy and compare it to
# its exact source before replacing a previous generated app.
setup_names = [
    "__init__.py", "setup_adapters.py", "setup_bridge.py", "setup_config.py",
    "setup_delivery.py", "setup_journal.py", "setup_producer.py",
    "setup_protocol.py", "setup_support.py",
]
reinstall_names = [
    "__init__.py", "reinstall_adapters.py", "reinstall_bridge.py",
    "reinstall_config.py", "reinstall_journal.py", "reinstall_producer.py",
    "reinstall_protocol.py",
]
backup_names = ["__init__.py", "bridge.py", "catalog.py", "protocol.py"]
management_names = [
    "__init__.py", "management_adapters.py", "management_bridge.py",
    "management_journal.py", "management_lineage.py", "management_preparation.py",
    "management_producer.py", "management_protocol.py", "management_source.py", "management_target.py",
]
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Device").glob("*.py")) != ["gofly_device.py"]:
    raise SystemExit("unexpected Device bridge Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Setup").glob("*.py")) != sorted(setup_names):
    raise SystemExit("unexpected Setup bridge Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Reinstall").glob("*.py")) != sorted(reinstall_names):
    raise SystemExit("unexpected Reinstall bridge Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Backup").glob("*.py")) != sorted(backup_names):
    raise SystemExit("unexpected Backup bridge Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Management").glob("*.py")) != sorted(management_names):
    raise SystemExit("unexpected Management bridge Python inventory")
source_files = {
    "Contents/Resources/Bridge/bridge.py": root / "app/GoFlyMac/Bridge/bridge.py",
    "Contents/Resources/Bridge/Device/gofly_device.py": root / "app/GoFlyMac/Bridge/Device/gofly_device.py",
    "Contents/MacOS/GoFlyTransferValidator": validator_products / "GoFlyTransferValidator",
}
for name in setup_names:
    source_files[f"Contents/Resources/Bridge/Setup/{name}"] = root / "app/GoFlyMac/Bridge/Setup" / name
for name in reinstall_names:
    source_files[f"Contents/Resources/Bridge/Reinstall/{name}"] = root / "app/GoFlyMac/Bridge/Reinstall" / name
for name in backup_names:
    source_files[f"Contents/Resources/Bridge/Backup/{name}"] = root / "app/GoFlyMac/Bridge/Backup" / name
for name in management_names:
    source_files[f"Contents/Resources/Bridge/Management/{name}"] = root / "app/GoFlyMac/Bridge/Management" / name

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(64 * 1024):
            digest.update(chunk)
    return digest.hexdigest()

files = {}
for relative, source in sorted(source_files.items()):
    target = bundle / relative
    if source.is_symlink() or not source.is_file():
        raise SystemExit(f"source is not a regular non-symlink file: {source}")
    if target.is_symlink() or not target.is_file():
        raise SystemExit(f"staged file is not a regular non-symlink file: {target}")
    if source.read_bytes() != target.read_bytes():
        raise SystemExit(f"staged copy differs from source: {relative}")
    files[relative] = sha256(target)

for relative in [
    "Contents/Resources/LocalConfiguration.json",
    "Contents/Resources/SetupConfiguration.json",
    "Contents/Resources/ReinstallConfiguration.json",
]:
    target = bundle / relative
    if target.is_symlink() or not target.is_file():
        raise SystemExit(f"generated config is not a regular non-symlink file: {target}")
    files[relative] = sha256(target)

manifest = {"version": 1, "files": dict(sorted(files.items()))}
manifest_path = bundle / "Contents/Resources/GoFlyBundleManifest.json"
manifest_path.write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
manifest_path.chmod(0o644)
readback = json.loads(manifest_path.read_text())
if readback != manifest or any(sha256(bundle / relative) != digest for relative, digest in files.items()):
    raise SystemExit("staged bundle resource manifest readback mismatch")
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
