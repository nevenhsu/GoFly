# GoFly native bridge

GoFly uses a small, verification-only extension to MIT-licensed idevice by
Jackson Coxson. The Swift module exposes only the functions used by the
production device boundary and audited pairing store. It does not expose
pair-setup, pairing-file generation/write, process-control or JIT APIs.

The upstream `tunnel_create_rppairing` may fall back to pair-setup after failed
verification. The added `tunnel_create_rppairing_verify_only` instead calls
`attempt_pair_verify`, then `validate_pairing`, then the existing TLS/RSD tunnel
completion. A rejected credential is terminal. There is no PIN callback and no
credential update. Output handles are nulled before fallible work and published
only after complete success. Swift still verifies the expected UDID on this
same adapter/handshake before DDI or location operations.

## Build

On Apple Silicon with Xcode at `/Applications/Xcode.app`, run from the project:

```sh
app/GoFly/NativeBridge/build.sh
```

The script exports the pinned commit in `upstream.json` from the local research
checkout `work/mac-bootstrap-idevice`. To use another existing clone, set
`GOFLY_IDEVICE_REPOSITORY` to its absolute path; its working tree is never edited.
The pin must exist locally. A fresh clone can be placed under ignored `work/`
from `https://github.com/jkcoxson/idevice.git` before running the script.

Only a fresh archive of that commit is patched. The build-script patch asks
cbindgen to parse the local FFI source tree directly, avoiding its implicit
unlocked `cargo metadata --all-features` dependency fetch. Cargo uses its unchanged lockfile
with `--locked`, disabled default features, and the feature list in the pin.
`dvt` and `location_simulation` are both required: the current remote location
FFI module is gated by both features. Upstream also compiles its legacy location
API under that feature; the Swift shim exposes only the current remote API. No `full`, debug-proxy or JIT
feature is selected. Transitive tunnel/DDI support is included as required.

Rust 1.94.0 standalone components are downloaded from official Rust distribution
URLs and SHA-256 verified against the official release manifest values recorded
in `upstream.json` before their installer scripts run. Toolchain, Cargo home,
Rustup home, dependencies, source export, tests and artifacts stay under ignored
`work/gofly-ios`. No shell profile, system installation or home toolchain changes.
The first build requires public network access for these pinned components and
Cargo's locked dependencies.

## Verification and outputs

A host Swift harness compiles the production error mapper with the actual
service-failure enum. It checks that pair-verify rejection (103/5) requires Mac
pairing repair, timeouts stay timeouts, and other failures preserve their
operation-specific fallback. The real iOS branch imports the shim unconditionally;
a missing module fails the device build.

Host Rust regression tests exercise the actual remote-pairing client and
cryptography against a scripted in-memory peer for successful verification and
rejection. They compare serialized credentials before/after both paths. A
loopback TCP test calls the C export and proves rejection emits only verification
messages, preserves credentials and leaves both output handles null. Rejection codes are asserted as 103/5. Invalid
pointer arguments and malformed address/hostname data also return errors with valid outputs cleared. These tests do
not claim device or end-to-end tunnel acceptance.

The build also compiles C type-compatibility assertions for all 29 shim
declarations, the sizes/alignment/field offsets of both concrete C structs,
and every plist enum value against the newly generated full header. It checks that every
permitted symbol exists in the device archive. This C-only verification never
adds the full header to the production Swift import path.

The device archive is built for `aarch64-apple-ios` with deployment target 26.0.
Generated `work/gofly-ios/native/manifest.json` records the upstream commit,
lockfile, patch, toolchain, Xcode/SDK, feature selection and archive/header hashes.
`idevice-full.h` is retained there as provenance only. Production Swift imports
only the checked-in `include/idevice.h` shim and `include/module.modulemap`.
Generated artifacts and credentials must never be committed.

This build does not connect to an iOS device, pair, mount DDI, set/clear a device
location, download developer images, or install the application.
