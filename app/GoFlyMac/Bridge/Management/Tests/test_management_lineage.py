from __future__ import annotations

import hashlib
import json
import sys
import unittest
import uuid
from pathlib import Path

BRIDGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(BRIDGE_ROOT))

from Management.management_lineage import (  # noqa: E402
    ManagementGeneration,
    generation_ids,
    validate_source_lineage,
)
from Management.management_protocol import ManagementBridgeError  # noqa: E402
from Management.management_source import decode_source_activation  # noqa: E402


DEVICE = "00000000-000000000000abcd"
TEAM = "ABCDEFGHIJ"
ORIGIN_SETUP = "11111111-1111-1111-1111-111111111111"
SOURCE_SETUP = "22222222-2222-2222-2222-222222222222"
MANAGEMENT_ID = "33333333-3333-3333-3333-333333333333"
SOURCE_NONCE = "44444444-4444-4444-4444-444444444444"
TARGET_NONCE = "55555555-5555-5555-5555-555555555555"
TRANSFER_ID = "66666666-6666-6666-6666-666666666666"
DATA_SET_ID = "77777777-7777-7777-7777-777777777777"
TRANSFER_NONCE = "88888888-8888-8888-8888-888888888888"

APP = {
    "bundleID": "com.neven.gofly",
    "build": "19",
    "profileSHA256": "a" * 64,
    "executableSHA256": "b" * 64,
}
ARTIFACT_NAMES = [
    "MountMethod",
    "BuildManifest.plist",
    "Image.dmg",
    "Image.dmg.trustcache",
    "Image.dmg.cryptex_info",
    "Image.dmg.root_hash",
]


def _activation(setup_id: str, nonce: str) -> bytes:
    receipt = {
        "version": 1,
        "setupID": setup_id,
        "nonce": nonce,
        "expectedDeviceUDID": DEVICE,
        "rawManifestSHA256": "d" * 64,
        "pairingTransactionID": "99999999-9999-9999-9999-999999999999",
        "pairingSHA256": "c" * 64,
        "app": APP,
        "teamID": TEAM,
        "signingExpiry": "2030-01-01T00:00:00Z",
        "deviceOS": "27.0",
        "method": "cryptex",
        "generationID": setup_id,
        "artifacts": [
            {
                "id": str(uuid.uuid5(uuid.UUID(setup_id), name)),
                "filename": name,
                "byteCount": 1,
                "sha256": (str(index + 1) * 64)[:64],
            }
            for index, name in enumerate(ARTIFACT_NAMES)
        ],
        "status": "committed",
    }
    return json.dumps(
        {"version": 1, "activeSetupID": setup_id, "receipts": [receipt]},
        sort_keys=True,
        separators=(",", ":"),
    ).encode()


def _restore_fixture() -> tuple[bytes, bytes, dict[str, object]]:
    intent = {
        "version": 1,
        "transferID": TRANSFER_ID,
        "dataSetID": DATA_SET_ID,
        "nonce": TRANSFER_NONCE,
        "rawManifestSHA256": "e" * 64,
        "sourceDeviceUDID": DEVICE,
        "destinationDeviceUDID": DEVICE,
        "sourceApp": APP,
        "targetApp": APP,
        "setupID": ORIGIN_SETUP,
        "categories": ["settings"],
    }
    status = {
        "transferID": TRANSFER_ID,
        "dataSetID": DATA_SET_ID,
        "rawManifestSHA256": "e" * 64,
        "phase": "committed",
        "receiptSHA256": None,
        "sessionSeedSHA256": "f" * 64,
        "intent": intent,
        "categories": [{"category": "settings", "state": "committed", "receiptSHA256": "1" * 64}],
        "counts": {"favorites": 0, "importedRoutes": 0, "favoriteRoutes": 0, "draftNodes": 0, "gpxPoints": 0},
    }
    final_receipt = {
        "version": 1,
        "intent": intent,
        "categoryReceipts": [{"category": "settings", "receiptSHA256": "1" * 64}],
        "sessionSeedSHA256": "f" * 64,
        "counts": status["counts"],
    }
    status["receiptSHA256"] = hashlib.sha256(
        json.dumps(final_receipt, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    root = {"version": 1, "active": status, "pending": None, "history": []}
    raw_root = json.dumps(root, sort_keys=True, separators=(",", ":")).encode()
    raw_intent = json.dumps(intent, sort_keys=True, separators=(",", ":")).encode()
    return raw_intent, raw_root, intent


def _management_fixture(raw_root: bytes, old_activation: bytes) -> tuple[bytes, bytes, dict[str, object]]:
    root_sha = hashlib.sha256(raw_root).hexdigest()
    request = {
        "version": 1,
        "managementID": MANAGEMENT_ID,
        "nonce": SOURCE_NONCE,
        "kind": "renew",
        "expectedDeviceUDID": DEVICE,
        "sourceSetupID": ORIGIN_SETUP,
        "sourceApp": APP,
        "sourceActivationSHA256": hashlib.sha256(old_activation).hexdigest(),
        "sourceRestoreRootSHA256": root_sha,
        "teamID": TEAM,
        "targetSetupID": SOURCE_SETUP,
        "targetApp": APP,
    }
    raw_request = json.dumps(request, sort_keys=True, separators=(",", ":")).encode()
    request_sha = hashlib.sha256(raw_request).hexdigest()
    adoption = {
        "version": 1,
        "managementID": MANAGEMENT_ID,
        "nonce": SOURCE_NONCE,
        "requestSHA256": request_sha,
        "sourceSetupID": ORIGIN_SETUP,
        "targetSetupID": SOURCE_SETUP,
        "sourceApp": APP,
        "targetApp": APP,
        "expectedDeviceUDID": DEVICE,
        "teamID": TEAM,
        "sourceActivationSHA256": request["sourceActivationSHA256"],
        "sourceRestoreRootSHA256": root_sha,
        "targetActivationSHA256": "0" * 64,
        "receiptSHA256": None,
    }
    adoption["receiptSHA256"] = hashlib.sha256(
        json.dumps({key: value for key, value in adoption.items() if key != "receiptSHA256"},
                   sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    record = {
        "managementID": MANAGEMENT_ID,
        "nonce": SOURCE_NONCE,
        "requestSHA256": request_sha,
        "phase": "adopted",
        "sourceAdmission": "cold",
        "currentApp": APP,
        "pid": 0,
        "sourceSetupID": ORIGIN_SETUP,
        "targetSetupID": SOURCE_SETUP,
        "sourceApp": APP,
        "targetApp": APP,
        "expectedDeviceUDID": DEVICE,
        "teamID": TEAM,
        "sourceActivationSHA256": request["sourceActivationSHA256"],
        "sourceRestoreRootSHA256": root_sha,
        "adoptionReceipt": adoption,
    }
    management_root = json.dumps(
        {"version": 1, "current": record, "history": []},
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return management_root, raw_request, record


class ManagementLineageTests(unittest.TestCase):
    def test_repeated_management_lineage_and_generation_ids(self) -> None:
        old_activation = _activation(ORIGIN_SETUP, SOURCE_NONCE)
        current_activation = _activation(SOURCE_SETUP, TARGET_NONCE)
        restore_intent, restore_root, _ = _restore_fixture()
        management_root, raw_request, _ = _management_fixture(restore_root, old_activation)
        source = decode_source_activation(
            current_activation,
            device_id=DEVICE,
            installed_build=APP["build"],
            installed_team=TEAM,
        )

        self.assertEqual(generation_ids(management_root), (MANAGEMENT_ID,))
        summary = validate_source_lineage(
            source,
            DEVICE,
            restore_intent,
            restore_root,
            management_root,
            {
                MANAGEMENT_ID: ManagementGeneration(raw_request, old_activation, restore_root),
            },
        )
        self.assertEqual(summary.origin_setup_id, ORIGIN_SETUP)
        self.assertEqual(summary.origin_app, source.identity)
        self.assertEqual(summary.current_root_sha256, hashlib.sha256(restore_root).hexdigest())
        self.assertEqual(summary.adopted_management_ids, (MANAGEMENT_ID,))

    def test_pending_root_or_missing_generation_is_rejected(self) -> None:
        old_activation = _activation(ORIGIN_SETUP, SOURCE_NONCE)
        current_activation = _activation(SOURCE_SETUP, TARGET_NONCE)
        restore_intent, restore_root, intent = _restore_fixture()
        management_root, raw_request, _ = _management_fixture(restore_root, old_activation)
        source = decode_source_activation(
            current_activation,
            device_id=DEVICE,
            installed_build=APP["build"],
            installed_team=TEAM,
        )
        pending_status = {
            "transferID": TRANSFER_ID,
            "dataSetID": DATA_SET_ID,
            "rawManifestSHA256": "e" * 64,
            "phase": "validating",
            "receiptSHA256": None,
            "sessionSeedSHA256": None,
            "intent": intent,
            "categories": [{"category": "settings", "state": "waiting", "receiptSHA256": None}],
            "counts": None,
        }
        pending_root = json.dumps(
            {
                "version": 1,
                "active": None,
                "pending": {
                    "intent": intent,
                    "status": pending_status,
                    "pointers": [{"category": "settings", "state": "waiting", "pointer": {"transferID": TRANSFER_ID, "category": "settings"}, "receiptSHA256": None}],
                    "seed": {"state": "waiting", "sessionSeedSHA256": None},
                },
                "history": [],
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
        with self.assertRaises(ManagementBridgeError):
            validate_source_lineage(
                source, DEVICE, restore_intent, pending_root, management_root,
                {MANAGEMENT_ID: ManagementGeneration(raw_request, old_activation, restore_root)},
            )
        with self.assertRaises(ManagementBridgeError):
            validate_source_lineage(source, DEVICE, restore_intent, restore_root, management_root, {})


if __name__ == "__main__":
    unittest.main()
