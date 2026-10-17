#!/bin/bash
set -euo pipefail
bridge_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$(cd "$bridge_dir/../../.." && pwd)"
output="$project_dir/work/gofly-ios/native-error-mapping-check"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$output"
# Compile the real enum and exact mapper source without any iOS FFI module.
xcrun --sdk macosx swiftc -emit-module -emit-library -parse-as-library \
  -module-cache-path "$output/module-cache" -module-name GoFlyCore -swift-version 6 \
  "$project_dir/app/GoFly/Sources/GoFlyCore/DeviceService.swift" \
  "$project_dir/app/GoFly/Sources/GoFlyCore/GeoCoordinate.swift" \
  "$project_dir/app/GoFly/Sources/GoFlyCore/TeleportModels.swift" \
  "$project_dir/app/GoFly/Sources/GoFlyCore/PointDispatchGate.swift" \
  "$project_dir/app/GoFly/Sources/GoFlyCore/VerifiedDeviceSession.swift" \
  -emit-module-path "$output/GoFlyCore.swiftmodule" -o "$output/libGoFlyCore.dylib"
xcrun --sdk macosx swiftc -parse-as-library -module-cache-path "$output/module-cache" \
  -swift-version 6 -I "$output" -L "$output" -lGoFlyCore \
  -Xlinker -rpath -Xlinker "$output" \
  "$project_dir/app/GoFly/Device/NativeErrorMapping.swift" \
  "$bridge_dir/tests/NativeErrorMappingCheck.swift" -o "$output/check"
"$output/check"

xcrun --sdk macosx clang -c "$bridge_dir/tests/timeout-stub.c" -o "$output/timeout-stub.o"
xcrun --sdk macosx swiftc -parse-as-library -module-cache-path "$output/module-cache" \
  -swift-version 6 -I "$output" -I "$bridge_dir/include" -L "$output" -lGoFlyCore \
  -Xlinker -rpath -Xlinker "$output" \
  "$project_dir/app/GoFly/Device/NativeDeviceService.swift" \
  "$bridge_dir/tests/NativeSessionLifetimeCheck.swift" "$output/timeout-stub.o" -o "$output/lifetime-check"
"$output/lifetime-check"
