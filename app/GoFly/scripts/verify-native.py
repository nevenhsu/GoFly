#!/usr/bin/env python3
"""Verify the exact audited source/native boundary before a device build."""
import hashlib
import json
import re
import argparse
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-only", action="store_true", help="Check source boundaries without claiming a device archive is verified")
    args = parser.parse_args()
    app = Path(__file__).resolve().parents[1]
    root = app.parents[1]
    manifest = json.loads((app / "NativeSources.json").read_text())
    failures = []
    for relative, expected in manifest["files"].items():
        source = root / relative
        if not source.is_file() or sha256(source) != expected:
            failures.append(relative)
    if failures:
        raise SystemExit("Audited source changed; review and update manifest: " + ", ".join(failures))
    project = (app / "GoFly.xcodeproj/project.pbxproj").read_text()
    for excluded in ("JITEnableContext.swift", "IdeviceFFIBridge.swift", "DeveloperDiskImageService.swift", "LocalGoMapView.swift"):
        if excluded in project:
            raise SystemExit("Forbidden prototype source in formal target: " + excluded)
    # This list is intentional: ticket 01 can validate/clear but cannot set a
    # coordinate, debug a process, pair a new device or download support data.
    allowed = set("""
        adapter_free cryptex1_assets_free cryptex1_assets_load
        cryptexd_free_installed_cryptex cryptexd_install_ddi cryptexd_installed_ddi
        idevice_data_free idevice_error_free idevice_set_global_timeout
        image_mounter_connect_rsd image_mounter_free image_mounter_lookup_image
        image_mounter_mount_personalized_rsd location_simulation_clear
        location_simulation_free location_simulation_new lockdownd_client_free
        lockdownd_connect_rsd lockdownd_get_value plist_free plist_get_node_type
        plist_get_string_ptr plist_get_uint_val remote_server_connect_rsd
        remote_server_free rp_pairing_file_free rp_pairing_file_read
        rsd_handshake_free tunnel_create_rppairing_verify_only
    """.split())
    native = "\n".join(path.read_text() for path in sorted((app / "Device").glob("*.swift")))
    calls = set(re.findall(
        r"\b((?:idevice|rp_pairing|tunnel|adapter|rsd|lockdownd|plist|image_mounter|cryptex|remote_server|location_simulation)[a-z0-9_]*)\s*\(", native
    ))
    if calls - allowed:
        raise SystemExit("Unaudited native operation: " + ", ".join(sorted(calls - allowed)))
    if "URLSession" in native or "downloadMissingFiles" in native:
        raise SystemExit("Phone-side download source is not allowed")
    bridge = app / "NativeBridge"
    header = (bridge / "include/idevice.h").read_text()
    declarations = set(re.findall(r"\b([a-z][a-z0-9_]+)\s*\(", re.sub(r"//[^\n]*", "", header)))
    if declarations != allowed:
        raise SystemExit("Swift shim differs from audited API: " + ", ".join(sorted(declarations ^ allowed)))
    if re.findall(r'^#include\s+(.+)$', header, re.MULTILINE) != [
        "<stdint.h>", "<stddef.h>", "<sys/types.h>", "<sys/socket.h>"
    ]:
        raise SystemExit("Swift shim must not include additional native APIs")
    module = (bridge / "include/module.modulemap").read_text()
    if module != 'module idevice [system] {\n  header "idevice.h"\n  export *\n}\n':
        raise SystemExit("Swift must import only the narrow checked-in header")
    config = (app / "GoFly.xcconfig").read_text()
    for setting in (
        "SWIFT_INCLUDE_PATHS[sdk=iphoneos*] = $(inherited) $(PROJECT_DIR)/NativeBridge/include",
        "LIBRARY_SEARCH_PATHS[sdk=iphoneos*] = $(inherited) $(PROJECT_DIR)/../../work/gofly-ios/native",
    ):
        if setting not in config:
            raise SystemExit("Device native input path differs from the audited configuration")
    if "LocalGo/StikDebug/idevice" in project + config or "idevice-full.h" in project + config:
        raise SystemExit("Prototype archive/full header must not enter the formal target")
    if args.source_only:
        print("PASS: selected setup sources and narrow Swift API match; device archive not checked.")
        return
    output = root / "work/gofly-ios/native"
    if not (output / "manifest.json").is_file():
        raise SystemExit("Build the pinned native library first: bash app/GoFly/NativeBridge/build.sh")
    built = json.loads((output / "manifest.json").read_text())
    pin = json.loads((bridge / "upstream.json").read_text())
    expected_metadata = {
        "upstreamRepository": pin["repository"], "upstreamCommit": pin["commit"],
        "target": pin["target"], "features": pin["features"],
        "deploymentTarget": "26.0", "cargoLocked": True,
        "swiftShimABI": "29 declarations checked against generated C ABI and archive symbols",
    }
    for key, expected in expected_metadata.items():
        if built.get(key) != expected:
            raise SystemExit("Native build metadata mismatch: " + key)
    if not built.get("rustVersion", "").startswith("rustc " + pin["rustVersion"] + " "):
        raise SystemExit("Native build used an unexpected Rust version")
    inputs = {
        "Cargo.lock": output / "Cargo.lock", "verify-only.patch": bridge / "verify-only.patch",
        "upstream.json": bridge / "upstream.json", "idevice-full.h": output / "idevice-full.h",
        "libidevice_ffi.a": output / "libidevice_ffi.a",
        "swiftShimHeader": bridge / "include/idevice.h",
        "swiftModuleMap": bridge / "include/module.modulemap",
        "shim-abi-check.c": output / "shim-abi-check.c",
    }
    for key, path in inputs.items():
        if not path.is_file() or sha256(path) != built.get("sha256", {}).get(key):
            raise SystemExit("Native build input/output changed; rebuild: " + key)
    if built["sha256"]["Cargo.lock"] != pin["cargoLockSHA256"]:
        raise SystemExit("Native dependency lockfile differs from the pin")
    print("PASS: pinned native build, narrow Swift API and selected setup sources match.")


if __name__ == "__main__":
    main()
