#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
task_output="$task_root/work/gofly-ios"
export CLANG_MODULE_CACHE_PATH="$task_output/module-cache"
mkdir -p "$task_output"
python3 "$task_root/app/GoFly/scripts/verify-native.py" --source-only
swift test --disable-sandbox --package-path "$task_root/app/GoFly" \
  --scratch-path "$task_output/core-build" --cache-path "$task_output/cache" \
  --config-path "$task_output/config" --security-path "$task_output/security"
bash "$task_root/app/GoFly/NativeBridge/build.sh"
python3 "$task_root/app/GoFly/scripts/verify-native.py"
for task_sdk in iphonesimulator iphoneos; do
  xcodebuild -project "$task_root/app/GoFly/GoFly.xcodeproj" -scheme GoFly \
    -sdk "$task_sdk" -configuration Debug \
    -derivedDataPath "$task_output/$task_sdk" \
    -clonedSourcePackagesDirPath "$task_output/packages" \
    CODE_SIGNING_ALLOWED=NO build > "$task_output/$task_sdk-build.log" 2>&1 || {
      tail -80 "$task_output/$task_sdk-build.log"
      exit 1
    }
  tail -3 "$task_output/$task_sdk-build.log"
done
