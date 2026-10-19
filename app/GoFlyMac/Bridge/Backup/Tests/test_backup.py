from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(PACKAGE_ROOT))

from Backup.catalog import (  # noqa: E402
    BackupCatalog,
    _Source,
    _delete_payload,
    _remove_empty_recovery,
)
from Backup.protocol import BackupBridgeError, decode_request  # noqa: E402


TRANSFER = "11111111-1111-4111-8111-111111111111"
DATA_SET = "22222222-2222-4222-8222-222222222222"
NONCE = "33333333-3333-4333-8333-333333333333"
SETUP = "44444444-4444-4444-8444-444444444444"
ARTIFACT = "55555555-5555-4555-8555-555555555555"
DEVICE = "00008110-001234567890abcd"


def _manifest() -> dict:
    return {
        "version": 1,
        "transferID": TRANSFER,
        "dataSetID": DATA_SET,
        "nonce": NONCE,
        "sourceDeviceUDID": DEVICE,
        "destinationDeviceUDID": DEVICE,
        "sourceApp": {"bundleID": "com.neven.gofly", "build": "1", "profileSHA256": "a" * 64, "executableSHA256": "b" * 64},
        "targetApp": {"bundleID": "com.neven.gofly", "build": "2", "profileSHA256": "c" * 64, "executableSHA256": "d" * 64},
        "setupID": SETUP,
        "categories": ["favorites"],
        "schemas": {"favorites": 1},
        "artifacts": [{"id": ARTIFACT, "path": "favorites/archive.json", "byteCount": 1, "sha256": hashlib.sha256(b"x").hexdigest()}],
    }


def _source(raw_manifest: bytes) -> _Source:
    journal = {
        "transferID": TRANSFER,
        "deviceID": DEVICE,
        "dataSetID": DATA_SET,
        "nonce": NONCE,
        "setupID": SETUP,
        "rawManifestSHA256": hashlib.sha256(raw_manifest).hexdigest(),
        "backup": {"inventory": {"categories": ["favorites"]}},
    }
    return _Source(TRANSFER, journal, raw_manifest, "f" * 64, Path("reinstall-journal.json"), False)


def _make_package(root: Path, *, manifest: bytes | None) -> Path:
    package = root / "reinstall-transactions" / TRANSFER / "backup"
    (package / "favorites").mkdir(parents=True, mode=0o700)
    for directory in (root, root / "reinstall-transactions", root / "reinstall-transactions" / TRANSFER, package, package / "favorites"):
        directory.chmod(0o700)
    if manifest is not None:
        (package / "manifest.json").write_bytes(manifest)
        (package / "manifest.json").chmod(0o600)
    (package / "favorites" / "archive.json").write_bytes(b"x")
    (package / "favorites" / "archive.json").chmod(0o600)
    return package


class BackupTests(unittest.TestCase):
    def test_protocol_rejects_unconfirmed_delete_and_accepts_list(self) -> None:
        request = decode_request(b'{"protocol":4,"requestID":"11111111-1111-4111-8111-111111111111","action":"list"}')
        self.assertEqual(request.action, "list")
        with self.assertRaisesRegex(BackupBridgeError, "invalid-request"):
            decode_request(b'{"protocol":4,"requestID":"11111111-1111-4111-8111-111111111111","action":"delete","transferID":"11111111-1111-4111-8111-111111111111","confirmed":false}')

    def test_catalog_round_trip_retention_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            root.mkdir(mode=0o700, exist_ok=True)
            catalog = BackupCatalog(root)
            catalog.write({"version": 1, "entries": [], "deletion": None})
            self.assertEqual(catalog.read()["entries"], [])
            self.assertEqual((root / "backup-catalog.json").stat().st_mode & 0o777, 0o600)

    def test_descriptor_deletion_removes_payload_before_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = json.dumps(_manifest(), separators=(",", ":")).encode()
            package = _make_package(root, manifest=raw)
            _delete_payload(root, _source(raw), raw, _manifest())
            self.assertFalse(package.exists())

            package = _make_package(root, manifest=raw)
            (package / "favorites" / "archive.json").write_bytes(b"y")
            with self.assertRaisesRegex(BackupBridgeError, "backup-changed"):
                _delete_payload(root, _source(raw), raw, _manifest())
            self.assertTrue((package / "favorites" / "archive.json").exists())

    def test_manifestless_recovery_only_removes_empty_closed_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = _make_package(root, manifest=None)
            (package / "favorites" / "archive.json").unlink()
            _remove_empty_recovery(root, TRANSFER, ["favorites"])
            self.assertFalse(package.exists())


if __name__ == "__main__":
    unittest.main()
