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
mkdir -p "$STAGING_BUNDLE/Contents/MacOS" "$STAGING_BUNDLE/Contents/Resources/Bridge/Device" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Setup"
cp "$PRODUCTS/GoFlyMac" "$STAGING_BUNDLE/Contents/MacOS/GoFlyMac"
# SwiftPM resolves the resource bundle alongside the executable in this local development app.
cp -R "$PRODUCTS/GoFlyMac_GoFlyMac.bundle" "$STAGING_BUNDLE/Contents/Resources/"
cp "$APP_SOURCE/Bridge/bridge.py" "$APP_SOURCE/Bridge/wire.py" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/"
cp "$APP_SOURCE/Bridge/Setup/__init__.py" "$APP_SOURCE"/Bridge/Setup/setup_*.py \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Setup/"
cp "$APP_SOURCE/Bridge/Device/__init__.py" "$APP_SOURCE/Bridge/Device/gofly_device.py" \
  "$STAGING_BUNDLE/Contents/Resources/Bridge/Device/"

/usr/bin/python3 - "$WORKSPACE_ROOT" "$STAGING_BUNDLE" "$APP_BUNDLE" <<'PY'
import json
import hashlib
import plistlib
import re
import sys
from pathlib import Path

root, bundle, final_bundle = map(Path, sys.argv[1:])
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
assert sorted(p.name for p in (bundle / "Contents/Resources/Bridge/Device").iterdir()) == ["__init__.py", "gofly_device.py"]

# The manifest is intentionally closed: every Python source copied into the
# bundle and the generated bridge configuration are fixed inputs. Reopen each
# staged copy and compare it to its exact source before replacing a previous
# generated app.
setup_names = [
    "__init__.py", "setup_adapters.py", "setup_config.py",
    "setup_delivery.py", "setup_journal.py", "setup_producer.py",
    "setup_protocol.py", "setup_support.py",
]
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge").glob("*.py")) != ["bridge.py", "wire.py"]:
    raise SystemExit("unexpected Bridge root Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Device").glob("*.py")) != ["__init__.py", "gofly_device.py"]:
    raise SystemExit("unexpected Device bridge Python inventory")
if sorted(p.name for p in (root / "app/GoFlyMac/Bridge/Setup").glob("*.py")) != sorted(setup_names):
    raise SystemExit("unexpected Setup bridge Python inventory")
source_files = {
    "Contents/Resources/Bridge/bridge.py": root / "app/GoFlyMac/Bridge/bridge.py",
    "Contents/Resources/Bridge/wire.py": root / "app/GoFlyMac/Bridge/wire.py",
    "Contents/Resources/Bridge/Device/__init__.py": root / "app/GoFlyMac/Bridge/Device/__init__.py",
    "Contents/Resources/Bridge/Device/gofly_device.py": root / "app/GoFlyMac/Bridge/Device/gofly_device.py",
}
for name in setup_names:
    source_files[f"Contents/Resources/Bridge/Setup/{name}"] = root / "app/GoFlyMac/Bridge/Setup" / name

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

# The Swift verifier only accepts this exact key set.  Parse the closed
# MacBundleResourceEntry allowlist so a newly packaged file cannot silently
# diverge from the app's manifest validation again.
swift_source = (root / "app/GoFlyMac/Sources/GoFlyMacCore/MacBundleResources.swift").read_text()
swift_entries = set(re.findall(r'case\s+\w+\s*=\s*"(Contents/Resources/[^"]+)"', swift_source))
if not swift_entries:
    raise SystemExit("could not parse MacBundleResourceEntry from Swift source")
manifest_entries = set(readback["files"])
missing = sorted(swift_entries - manifest_entries)
extra = sorted(manifest_entries - swift_entries)
if missing or extra:
    details = []
    if missing:
        details.append("missing from manifest: " + ", ".join(missing))
    if extra:
        details.append("not in Swift allowlist: " + ", ".join(extra))
    raise SystemExit("Swift allowlist and bundle manifest differ\n  " + "\n  ".join(details))
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

# Execute the packaged bridge exactly as ProcessBridge does: same Python from
# LocalConfiguration.json, `-I`, the bundled --config, and a JSON request on
# stdin.  Only the read-only `environment` action runs; it never opens a device.
/usr/bin/python3 - "$APP_BUNDLE" <<'PY'
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path

bundle = Path(sys.argv[1])
config_path = bundle / "Contents/Resources/LocalConfiguration.json"
script = bundle / "Contents/Resources/Bridge/bridge.py"


def fail(message):
    print(f"Packaged bridge smoke check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


if script.is_symlink() or not script.is_file():
    fail(f"missing bundled bridge entry {script}")
if config_path.is_symlink() or not config_path.is_file():
    fail(f"missing bundled configuration {config_path}")
try:
    config = json.loads(config_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    fail(f"unreadable LocalConfiguration.json: {error}")

python = config.get("pythonPath")
developer = config.get("developerDirectory")
if not isinstance(python, str) or not os.path.isfile(python) or not os.access(python, os.X_OK):
    fail(f"configured Python is not executable: {python!r}")
if not isinstance(developer, str):
    fail("LocalConfiguration.json has no developerDirectory")

request_id = str(uuid.uuid4())
request = json.dumps({"action": "environment", "requestID": request_id},
                     separators=(",", ":")).encode("utf-8")
environment = {
    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": str(Path.home()),
    "DEVELOPER_DIR": developer,
    "PYTHONDONTWRITEBYTECODE": "1",
}
try:
    completed = subprocess.run(
        [python, "-I", str(script), "--config", str(config_path)],
        input=request, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=environment, cwd="/", timeout=120, check=False,
    )
except subprocess.TimeoutExpired:
    fail("environment action timed out after 120 seconds")

stdout = completed.stdout.decode("utf-8", "replace")
stderr = completed.stderr.decode("utf-8", "replace")
if "Traceback (most recent call last)" in stderr:
    print(stderr[-4096:], file=sys.stderr)
    fail("environment action produced a Python traceback")
if completed.returncode != 0:
    print(stderr[-4096:], file=sys.stderr)
    fail(f"environment action exited with status {completed.returncode}")
try:
    response = json.loads(stdout)
except json.JSONDecodeError:
    print(stdout[-4096:], file=sys.stderr)
    fail("environment action did not return valid JSON")
if (not isinstance(response, dict)
        or response.get("status") != "ok"
        or response.get("action") != "environment"
        or response.get("requestID") != request_id
        or not isinstance(response.get("payload"), dict)
        or not isinstance(response["payload"].get("checks"), list)):
    print(stdout[-4096:], file=sys.stderr)
    fail("environment action returned an unexpected response")

print("Packaged bridge environment smoke check passed.")
PY
