#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
root="$(cd .. && pwd)"
build="$root/work/localgo-lock-recovery/native-tests"
mkdir -p "$build"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export CLANG_MODULE_CACHE_PATH="$build/module-cache"
# Compile the production identity and engine code with a fake native boundary.
# This catches stale-handle control flow; it does not validate an iPhone/VPN.
touch "$build/empty.swift"
xcrun swiftc -emit-module -module-name idevice "$build/empty.swift" -emit-module-path "$build/idevice.swiftmodule"
xcrun swiftc -I "$build" \
    LocalGo/StikDebug/LocalGo/LocalGoPairingIdentity.swift \
    LocalGo/StikDebug/LocalGo/LiveLocationEngine.swift \
    LocalGo/StikDebug/LocalGo/DevicePreparationPolicy.swift \
    LocalGo/Tests/NativeRecovery/Stubs.swift \
    LocalGo/Tests/NativeRecovery/main.swift \
    -o "$build/recovery-tests"
# Each case starts a process so the production static identity cache starts
# empty, without adding test-only cache-reset APIs to the app.
while IFS= read -r scenario; do
    "$build/recovery-tests" "$scenario"
done < <("$build/recovery-tests" --list)
