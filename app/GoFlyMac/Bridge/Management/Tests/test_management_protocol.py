from __future__ import annotations

import copy
import dataclasses
import hashlib
import json
import sys
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(PACKAGE_ROOT))

from Management.management_protocol import (  # noqa: E402
    ManagementBridgeError,
    decode_request,
    encode_request,
    encode_response,
    error_response,
)


REQUEST_ID = "11111111-1111-4111-8111-111111111111"
MANAGEMENT_ID = "22222222-2222-4222-8222-222222222222"
SELECTION_ID = "33333333-3333-4333-8333-333333333333"
RESUME_SELECTION_ID = "44444444-4444-4444-8444-444444444444"
DEVICE = "00008110-001234567890abcd"


def _request(action: str = "apply", *, kind: str = "renew") -> dict[str, object]:
    value: dict[str, object] = {
        "protocol": 5,
        "operation": "management",
        "requestID": REQUEST_ID,
        "managementID": MANAGEMENT_ID,
        "deviceID": DEVICE,
        "selectionID": SELECTION_ID,
        "kind": kind,
        "transport": "USB",
        "connectionRevision": 0,
        "action": action,
    }
    if action in {"preflight", "apply"}:
        value["options"] = None if kind == "repair" else {
            "source": "project",
            "artifactPath": None,
            "teamID": "ABCDEFGHIJ",
            "allowProvisioningUpdates": False,
        }
    elif action == "resume":
        value["resumeSelection"] = {"selectionID": RESUME_SELECTION_ID, "transport": "Network"}
    return value


def _app(build: str, profile: str, executable: str) -> dict[str, str]:
    return {
        "bundleID": "com.neven.gofly",
        "build": build,
        "profileSHA256": profile * 64,
        "executableSHA256": executable * 64,
    }


def _complete_payload(request: object) -> dict[str, object]:
    source_app = _app("1", "a", "b")
    target_app = _app("2", "c", "d")
    receipt: dict[str, object] = {
        "version": 1,
        "managementID": MANAGEMENT_ID,
        "nonce": "55555555-5555-4555-8555-555555555555",
        "requestSHA256": "e" * 64,
        "sourceSetupID": "66666666-6666-4666-8666-666666666666",
        "targetSetupID": "77777777-7777-4777-8777-777777777777",
        "sourceApp": source_app,
        "targetApp": target_app,
        "expectedDeviceUDID": DEVICE,
        "teamID": "ABCDEFGHIJ",
        "sourceActivationSHA256": "8" * 64,
        "sourceRestoreRootSHA256": None,
        "targetActivationSHA256": "9" * 64,
    }
    receipt["receiptSHA256"] = hashlib.sha256(
        json.dumps(receipt, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        "stage": "complete",
        "outcome": "confirmed",
        "canResume": False,
        "canRelease": False,
        "sourceAdmission": "live",
        "connectionRevision": 0,
        "currentTransport": "USB",
        "proof": {
            "sourceBound": True,
            "sourceQuiescent": True,
            "mutationSealed": True,
            "updateConfirmed": True,
            "pairingImported": True,
            "supportObserved": True,
            "adoptionCommitted": True,
        },
        "app": target_app,
        "teamID": "ABCDEFGHIJ",
        "expiresAt": "2030-01-01T00:00:00Z",
        "adoptionReceipt": receipt,
    }


class ManagementProtocolTests(unittest.TestCase):
    def test_request_round_trip_and_closed_input_shape(self) -> None:
        for raw in (_request("apply"), _request("preflight", kind="repair"), _request("resume")):
            decoded = decode_request(json.dumps(raw).encode())
            self.assertEqual(decode_request(encode_request(decoded)).as_dict(), decoded.as_dict())

        self.assertEqual(decode_request(json.dumps({**_request(), "deviceID": DEVICE.upper()}).encode()).device_id, DEVICE)

        invalid_values = [
            {**_request(), "metadata": {"unexpected": True}},
            {**_request(), "connectionRevision": True},
            {**_request(), "options": {**_request()["options"], "artifactPath": "/tmp/../candidate.app"}},  # type: ignore[index]
            {**_request(), "options": {**_request()["options"], "artifactPath": "/tmp/candidate\x01.app"}},  # type: ignore[index]
        ]
        invalid_values.append({**_request(), "options": {
            **_request()["options"], "source": "signedApp", "artifactPath": "/tmp/candidate\u0085.app"}})  # type: ignore[dict-item]
        for value in invalid_values:
            with self.assertRaisesRegex(ManagementBridgeError, "invalid-request"):
                decode_request(json.dumps(value).encode())
        duplicate = json.dumps(_request())
        duplicate = duplicate[:-1] + ',"\\u0072equestID":"44444444-4444-4444-8444-444444444444"}'
        with self.assertRaisesRegex(ManagementBridgeError, "invalid-request"):
            decode_request(duplicate.encode())

    def test_complete_payload_requires_actual_receipt_binding_and_proofs(self) -> None:
        request = decode_request(json.dumps(_request()).encode())
        payload = _complete_payload(request)
        encoded = encode_response(request, payload)
        self.assertEqual(json.loads(encoded)["payload"]["adoptionReceipt"]["receiptSHA256"], payload["adoptionReceipt"]["receiptSHA256"])  # type: ignore[index]
        moved = copy.deepcopy(payload)
        moved["connectionRevision"] = 1
        moved["currentTransport"] = "Network"
        self.assertEqual(json.loads(encode_response(request, moved))["payload"]["currentTransport"], "Network")
        moved["connectionRevision"] = 0
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(request, moved)

        changed_hash = copy.deepcopy(payload)
        changed_hash["adoptionReceipt"]["receiptSHA256"] = "0" * 64  # type: ignore[index]
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(request, changed_hash)

        changed_binding = copy.deepcopy(payload)
        changed_binding["adoptionReceipt"]["managementID"] = SELECTION_ID  # type: ignore[index]
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(request, changed_binding)

        cold_claim = copy.deepcopy(payload)
        cold_claim["sourceAdmission"] = "cold"
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(request, cold_claim)
        preflight = decode_request(json.dumps(_request("preflight")).encode())
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(preflight, payload)
        waiting = {**payload, "stage": "source", "outcome": "unknown", "canResume": True, "canRelease": True,
                   "app": None, "teamID": None, "expiresAt": None, "adoptionReceipt": None,
                   "proof": {key: key == "sourceBound" for key in payload["proof"]}}
        self.assertTrue(json.loads(encode_response(request, waiting))["payload"]["canRelease"])
        waiting["proof"]["mutationSealed"] = True
        with self.assertRaisesRegex(ManagementBridgeError, "operation-failed"):
            encode_response(request, waiting)

    def test_errors_are_closed_and_do_not_echo_payload(self) -> None:
        request = decode_request(json.dumps(_request("query")).encode())
        response = error_response(request, "adoption-unknown")
        self.assertEqual(response["status"], "error")
        self.assertEqual(response["code"], "adoption-unknown")
        self.assertNotIn("payload", response)
        malformed = error_response({"requestID": "not-a-uuid", "metadata": "secret"}, "not-safe")
        self.assertIsNone(malformed["requestID"])
        self.assertEqual(malformed["code"], "operation-failed")
        self.assertNotIn("metadata", malformed)
        unvalidated = dataclasses.replace(request, request_id="private/path")
        self.assertIsNone(error_response(unvalidated, "operation-failed")["requestID"])


if __name__ == "__main__":
    unittest.main()
