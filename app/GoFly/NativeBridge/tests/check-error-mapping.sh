#!/bin/bash
set -euo pipefail
bridge_dir="$(cd "$(dirname "$0")/.." && pwd)"
project_dir="$(cd "$bridge_dir/../../.." && pwd)"
output="$project_dir/work/gofly-ios/native-error-mapping-check"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$output"
# Compile the production core module so the harness follows its current type
# dependencies (including continued-processing grants), without any iOS FFI.
xcrun --sdk macosx swiftc -emit-module -emit-library -parse-as-library \
  -module-cache-path "$output/module-cache" -module-name GoFlyCore -swift-version 6 \
  "$project_dir/app/GoFly/Sources/GoFlyCore/"*.swift \
  -emit-module-path "$output/GoFlyCore.swiftmodule" -o "$output/libGoFlyCore.dylib"
xcrun --sdk macosx swiftc -parse-as-library -module-cache-path "$output/module-cache" \
  -swift-version 6 -I "$output" -L "$output" -lGoFlyCore \
  -Xlinker -rpath -Xlinker "$output" \
  "$project_dir/app/GoFly/Device/NativeErrorMapping.swift" \
  "$bridge_dir/tests/NativeErrorMappingCheck.swift" -o "$output/check"
"$output/check"

# The mapper harness above exercises numeric mapping directly. This offline
# source check additionally proves that the production personalized-image
# branch delegates both code and subcode through that mapper before freeing
# the native error, rather than silently falling back at the call site.
session_source="$project_dir/app/GoFly/Device/NativeDeviceSession.swift"
lookup_block="$(sed -n '/if let error = image_mounter_lookup_image/,/return signature != nil/p' "$session_source")"
if ! printf '%s\n' "$lookup_block" | awk '
    /let code = error\.pointee\.code/ { code = NR }
    /let subcode = error\.pointee\.sub_code/ { subcode = NR }
    /NativeErrorMapping\.isNotMounted\(code: code, subcode: subcode\)/ { absent = NR }
    /NativeErrorMapping\.failure\(code: code, subcode: subcode/ { mapped = NR }
    /idevice_error_free\(error\)/ { freed = NR }
    END { exit !(code > 0 && subcode > code && absent > subcode && mapped > absent && freed > mapped) }
'; then
  echo "FAIL: NativeDeviceSession personalized lookup bypasses ordered native-error delegation" >&2
  exit 1
fi
echo "PASS: production personalized lookup delegates code/subcode mapping before freeing FFI error"

xcrun --sdk macosx clang -c "$bridge_dir/tests/timeout-stub.c" -o "$output/timeout-stub.o"
xcrun --sdk macosx swiftc -parse-as-library -module-cache-path "$output/module-cache" \
  -swift-version 6 -I "$output" -I "$bridge_dir/include" -L "$output" -lGoFlyCore \
  -Xlinker -rpath -Xlinker "$output" \
  "$project_dir/app/GoFly/Device/NativeDeviceService.swift" \
  "$bridge_dir/tests/NativeSessionLifetimeCheck.swift" "$output/timeout-stub.o" -o "$output/lifetime-check"
"$output/lifetime-check"
