#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_output="$task_root/work/gofly-ios"
export CLANG_MODULE_CACHE_PATH="$task_output/module-cache"
test_bundle_id="com.neven.gofly.0000000000"
mkdir -p "$task_output"

device=0
case "${1:-}" in
  "") ;;
  --device) device=1 ;;
  *) echo "usage: $0 [--device]" >&2; exit 2 ;;
esac

swift test --disable-sandbox --package-path "$task_root/app/GoFly" \
  --scratch-path "$task_output/core-build" --cache-path "$task_output/cache" \
  --config-path "$task_output/config" --security-path "$task_output/security"

build() {
  local task_sdk="$1"
  local log="$task_output/$task_sdk-build.log"
  xcodebuild -project "$task_root/app/GoFly/GoFly.xcodeproj" -scheme GoFly \
    -sdk "$task_sdk" -configuration Debug \
    -derivedDataPath "$task_output/$task_sdk" \
    -clonedSourcePackagesDirPath "$task_output/packages" \
    GOFLY_NATIVE_DIR="$task_root/work/gofly-ios/native" \
    GOFLY_BUNDLE_ID="$test_bundle_id" \
    PRODUCT_BUNDLE_IDENTIFIER="$test_bundle_id" \
    CODE_SIGNING_ALLOWED=NO build > "$log" 2>&1 || {
      tail -80 "$log"
      exit 1
    }
  tail -3 "$log"
}

bash "$task_root/app/GoFly/scripts/test-native-service.sh"

build iphonesimulator
simulator_app="$task_output/iphonesimulator/Build/Products/Debug-iphonesimulator/GoFly.app"
background_task_id="$(/usr/libexec/PlistBuddy -c 'Print :BGTaskSchedulerPermittedIdentifiers:0' "$simulator_app/Info.plist")"
if [[ "$background_task_id" != "$test_bundle_id.movement" ]]; then
  echo "Background task identifier does not match the Team-scoped bundle ID." >&2
  exit 1
fi
if ((device)); then
  bash "$task_root/app/GoFly/NativeBridge/build.sh"
  python3 "$task_root/app/GoFly/scripts/verify-native.py"
  build iphoneos
fi
