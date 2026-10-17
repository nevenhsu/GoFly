#!/usr/bin/env python3
"""Verify the exact audited source/native boundary before a device build."""
import hashlib
import json
import re
from pathlib import Path


def main():
    app = Path(__file__).resolve().parents[1]
    root = app.parents[1]
    manifest = json.loads((app / "NativeSources.json").read_text())
    failures = []
    for relative, expected in manifest["files"].items():
        source = root / relative
        if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != expected:
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
        rsd_handshake_free tunnel_create_rppairing
    """.split())
    native = "\n".join(path.read_text() for path in sorted((app / "Device").glob("*.swift")))
    calls = set(re.findall(
        r"\b((?:idevice|rp_pairing|tunnel|adapter|rsd|lockdownd|plist|image_mounter|cryptex|remote_server|location_simulation)[a-z0-9_]*)\s*\(", native
    ))
    if calls - allowed:
        raise SystemExit("Unaudited native operation: " + ", ".join(sorted(calls - allowed)))
    if "URLSession" in native or "downloadMissingFiles" in native:
        raise SystemExit("Phone-side download source is not allowed")
    print("PASS: audited native archive/header and selected setup sources match.")


if __name__ == "__main__":
    main()
