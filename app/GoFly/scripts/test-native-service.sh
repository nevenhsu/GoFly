#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="$root/work/gofly-ios/native-service-tests"
export SWIFT_BACKTRACE=disable
mkdir -p "$out"
export CLANG_MODULE_CACHE_PATH="$out/module-cache"
core_args=(--package-path "$root/app/GoFly" --scratch-path "$root/work/gofly-ios/core-build" --cache-path "$root/work/gofly-ios/cache" --config-path "$root/work/gofly-ios/config" --security-path "$root/work/gofly-ios/security")
swift build --disable-sandbox "${core_args[@]}" > "$out/build.log" 2>&1
products="$(swift build "${core_args[@]}" --show-bin-path)"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$root/app/GoFly/Setup/LocalGoSetupProtocol.swift" \
  "$root/app/GoFly/Setup/LocalGoSetupHandoff.swift" \
  "$root/app/GoFly/scripts/LocalGoSetupHandoffHostTests.swift" \
  -o "$out/local-go-setup-handoff-tests"
"$out/local-go-setup-handoff-tests"
printf '%s\n' 'public func idevice_set_global_timeout(_ timeout: UInt64) {}' > "$out/idevice.swift"
xcrun swiftc -swift-version 6 -emit-module -emit-object -parse-as-library -module-name idevice "$out/idevice.swift" -emit-module-path "$out/idevice.swiftmodule" -o "$out/idevice.o"
xcrun swiftc -swift-version 6 -parse-as-library -I "$out" -I "$products" \
  "$root/app/GoFly/Device/NativeDeviceService.swift" \
  "$root/app/GoFly/scripts/NativeServiceBoundaryTests.swift" \
  "$out/idevice.o" -L "$products" -lGoFlyCore \
  -o "$out/native-service-tests"
for scenario in missing-pairing preparation-failure clear-failure reset-failure success \
  single-attempt-failure known-nontransient explicit-gate-invalidated \
  authority-gates deadline-exhaustion; do
  "$out/native-service-tests" "$scenario"
done
