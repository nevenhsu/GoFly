from __future__ import annotations

import json
import sys
import unittest
import uuid
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PACKAGE_ROOT))

from Reinstall.reinstall_protocol import (  # noqa: E402
    CATEGORY_ORDER,
    ReinstallBridgeError,
    ReinstallOptions,
    ReinstallRequest,
    decode_request,
    encode_response,
    error_response,
)


DEVICE = "01234567-89abcdef01234567"
REQUEST_ID = "abcdefab-cdef-4abc-8def-abcdefabcdef"
TRANSFER_ID = "fedcbafe-dcba-4fed-8cba-fedcbafedcba"


def request(action: str = "status", **extra: object) -> dict[str, object]:
    value: dict[str, object] = {
        "protocol": 3,
        "requestID": REQUEST_ID,
        "operation": "reinstall",
        "action": action,
        "transferID": TRANSFER_ID,
        "deviceID": DEVICE,
    }
    value.update(extra)
    return value


def options(categories: list[str] | None = None) -> dict[str, object]:
    return {
        "source": "project",
        "artifactPath": None,
        "teamID": "ABCDEFGHIJ",
        "allowProvisioningUpdates": False,
        "categories": CATEGORY_ORDER if categories is None else categories,
    }


def proof(**updates: bool) -> dict[str, bool]:
    value = {
        "backupValidated": False,
        "sourceSealed": False,
        "removalConfirmed": False,
        "installationConfirmed": False,
        "pairingImported": False,
        "supportObserved": False,
        "restoreCommitted": False,
    }
    value.update(updates)
    return value


def complete_payload() -> dict[str, object]:
    return {
        "stage": "complete",
        "outcome": "confirmed",
        "canResume": False,
        "canAbandon": False,
        "proof": proof(
            backupValidated=True,
            sourceSealed=True,
            removalConfirmed=True,
            installationConfirmed=True,
            pairingImported=True,
            supportObserved=True,
            restoreCommitted=True,
        ),
        "categories": [
            {"category": name, "state": "committed", "receiptSHA256": "a" * 64}
            for name in CATEGORY_ORDER
        ],
        "counts": {
            "favorites": 1,
            "importedRoutes": 2,
            "favoriteRoutes": 3,
            "draftNodes": 4,
            "gpxPoints": 5,
        },
        "app": {
            "bundleID": "com.neven.gofly",
            "build": "19",
            "profileSHA256": "b" * 64,
            "executableSHA256": "c" * 64,
        },
        "teamID": "ABCDEFGHIJ",
        "expiresAt": "2030-01-01T00:00:00Z",
        "receiptSHA256": "d" * 64,
    }


class ReinstallProtocolTests(unittest.TestCase):
    def test_all_category_selections_decode_in_canonical_order(self) -> None:
        for selected in (
            [], ["favorites"], ["routes"], ["settings"], ["favorites", "routes"],
            ["favorites", "settings"], ["routes", "settings"], list(CATEGORY_ORDER),
        ):
            decoded = decode_request(json.dumps(request("apply", options=options(selected))).encode())
            self.assertEqual(decoded.options.categories, tuple(selected))
            self.assertEqual(decoded.as_dict()["options"]["categories"], selected)

    def test_request_rejects_unknown_duplicate_float_exponent_and_closed_options(self) -> None:
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request(extra=True)).encode())
        duplicate = (
            '{"protocol":3,"requestID":"%s","operation":"reinstall",'
            '"action":"status","transferID":"%s","deviceID":"%s",'
            '"deviceID":"%s"}' % (REQUEST_ID, TRANSFER_ID, DEVICE, DEVICE)
        )
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(duplicate.encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "deviceID": 1.0}).encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(('{"protocol":3,"requestID":"%s","operation":"reinstall","action":"status","transferID":"%s","deviceID":"%s","x":1e3}' % (REQUEST_ID, TRANSFER_ID, DEVICE)).encode())
        bad_options = options(["routes", "favorites"])
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request("apply", options=bad_options)).encode())

    def test_unhashable_wire_values_and_deep_json_are_safe_errors(self) -> None:
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request(action=[])).encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request("apply", options={**options(), "source": []})).encode())
        malformed = complete_payload()
        malformed["stage"] = []
        req = decode_request(json.dumps(request("status")).encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=malformed)
        malformed = complete_payload()
        malformed["categories"] = [{"category": "favorites", "state": [], "receiptSHA256": None}]
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=malformed)
        safe = error_response({"action": [], "requestID": REQUEST_ID, "transferID": TRANSFER_ID, "deviceID": DEVICE}, [])
        self.assertEqual(safe["action"], None)
        self.assertEqual(safe["code"], "operation-failed")
        nested: object = {}
        for _ in range(100):
            nested = {"nested": nested}
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "nested": nested}).encode())

    def test_options_are_required_only_for_preflight_and_apply(self) -> None:
        for action in ("preflight", "apply"):
            with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
                decode_request(json.dumps(request(action)).encode())
        for action in ("status", "resume", "abandon"):
            with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
                decode_request(json.dumps(request(action, options=options())).encode())

    def test_protocol_and_identity_are_strict_and_device_is_normalized(self) -> None:
        with self.assertRaisesRegex(ReinstallBridgeError, "protocol-mismatch"):
            decode_request(json.dumps({**request(), "protocol": 2}).encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request(deviceID=DEVICE.upper())).encode())
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "requestID": REQUEST_ID.upper()}).encode())

    def test_complete_response_requires_all_proofs_categories_counts_and_identity(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options())).encode())
        encoded = encode_response(req, status="ok", payload=complete_payload())
        value = json.loads(encoded)
        self.assertEqual(value["protocol"], 3)
        self.assertEqual(value["deviceID"], DEVICE)
        self.assertFalse(value["payload"]["canResume"])
        invalid = complete_payload()
        invalid["proof"] = proof(backupValidated=True)
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=invalid)

    def test_expiry_accepts_bounded_fractional_utc_and_rejects_invalid_dates(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options())).encode())
        payload = complete_payload()
        payload["expiresAt"] = "2030-01-01T00:00:00.123456789Z"
        encode_response(req, status="ok", payload=payload)
        payload["expiresAt"] = "2030-02-30T00:00:00.123Z"
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)

    def test_app_build_rejects_unicode_control_and_format_characters(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options())).encode())
        payload = complete_payload()
        payload["app"] = dict(payload["app"])
        payload["app"]["build"] = "19\u0085"
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)
        invalid = complete_payload()
        invalid["categories"] = [{"category": "favorites", "state": "committed", "receiptSHA256": "a" * 64}]
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=invalid)

    def test_signed_app_path_matches_mac_utf8_bound_and_nul_rules(self) -> None:
        too_long = options()
        too_long["source"] = "signedApp"
        too_long["artifactPath"] = "/" + ("a" * 4092) + ".app"
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request("apply", options=too_long)).encode())

        nul = options()
        nul["source"] = "signedApp"
        nul["artifactPath"] = "/tmp/GoFly\u0000.app"
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request("apply", options=nul)).encode())

        surrogate = options()
        surrogate["source"] = "signedApp"
        surrogate["artifactPath"] = "/tmp/GoFly\ud800.app"
        with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
            decode_request(json.dumps(request("apply", options=surrogate)).encode())

    def test_optional_response_metadata_rejects_explicit_null(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options())).encode())
        for key in ("app", "teamID", "expiresAt", "receiptSHA256"):
            payload = complete_payload()
            payload[key] = None
            with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
                encode_response(req, status="ok", payload=payload)

    def test_surrogate_response_strings_are_safe_operation_errors(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options())).encode())
        build = complete_payload()
        build["app"] = dict(build["app"])
        build["app"]["build"] = "\ud800"
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=build)

        expiry = complete_payload()
        expiry["expiresAt"] = "\ud800"
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=expiry)

    def test_counts_are_lexical_bounded_and_match_selection(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options(["favorites"]))).encode())
        payload = {
            "stage": "backup",
            "outcome": "inProgress",
            "canResume": True,
            "canAbandon": True,
            "proof": proof(backupValidated=True),
            "categories": [{"category": "favorites", "state": "validating", "receiptSHA256": None}],
            "counts": {"favorites": 1, "importedRoutes": 0, "favoriteRoutes": 0, "draftNodes": 0, "gpxPoints": 0},
        }
        self.assertEqual(json.loads(encode_response(req, status="ok", payload=payload))["payload"]["counts"]["favorites"], 1)
        for bad in ("01", "+1", 1.0, -1, 101):
            broken = dict(payload)
            broken["counts"] = dict(payload["counts"])
            broken["counts"]["favorites"] = bad
            with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
                encode_response(req, status="ok", payload=broken)
        broken = dict(payload)
        broken["counts"] = dict(payload["counts"])
        broken["counts"]["importedRoutes"] = 1
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=broken)

    def test_categories_receipts_and_unknown_install_proof_are_closed(self) -> None:
        req = decode_request(json.dumps(request("status")).encode())
        payload = {
            "stage": "install",
            "outcome": "unknown",
            "canResume": True,
            "canAbandon": False,
            "proof": proof(installationConfirmed=True),
            "categories": [],
            "counts": None,
        }
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="error", code="removal-unknown", payload=payload)
        payload["proof"] = proof()
        payload["categories"] = [{"category": "favorites", "state": "committed", "receiptSHA256": None}]
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)

    def test_selection_progress_rejects_foreign_or_omitted_categories(self) -> None:
        req = decode_request(json.dumps(request("apply", options=options(["favorites"]))).encode())
        payload = {
            "stage": "backup",
            "outcome": "inProgress",
            "canResume": True,
            "canAbandon": False,
            "proof": proof(backupValidated=True),
            "categories": [{"category": "routes", "state": "waiting", "receiptSHA256": None}],
            "counts": None,
        }
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)
        payload["categories"] = []
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)

    def test_known_destructive_proof_forbids_abandon_and_errors_cannot_complete(self) -> None:
        req = decode_request(json.dumps(request("status")).encode())
        payload = {
            "stage": "backup",
            "outcome": "inProgress",
            "canResume": False,
            "canAbandon": True,
            "proof": proof(sourceSealed=True),
            "categories": [],
            "counts": None,
        }
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", payload=payload)
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="error", code="backup-invalid", payload=complete_payload())

    def test_error_response_sanitizes_malformed_identity_and_uses_default_payload(self) -> None:
        value = error_response(
            {"requestID": {"raw": "secret"}, "action": "evil", "transferID": "bad", "deviceID": "bad"},
            "not-a-safe-code",
            {"unexpected": "diagnostic"},
        )
        self.assertEqual(value["requestID"], None)
        self.assertEqual(value["action"], None)
        self.assertEqual(value["transferID"], None)
        self.assertEqual(value["deviceID"], None)
        self.assertEqual(value["code"], "operation-failed")
        self.assertEqual(value["payload"]["counts"], None)
        self.assertEqual(set(value["payload"]), {"stage", "outcome", "canResume", "canAbandon", "proof", "categories", "counts"})

    def test_abandon_terminal_and_error_code_are_bounded(self) -> None:
        req = decode_request(json.dumps(request("abandon")).encode())
        payload = {
            "stage": "abandon",
            "outcome": "confirmed",
            "canResume": False,
            "canAbandon": False,
            "proof": proof(),
            "categories": [],
            "counts": None,
        }
        encoded = encode_response(req, status="error", code="operation-abandoned", payload=payload)
        value = json.loads(encoded)
        self.assertEqual(value["code"], "operation-abandoned")
        with self.assertRaisesRegex(ReinstallBridgeError, "operation-failed"):
            encode_response(req, status="ok", code="busy", payload=payload)


if __name__ == "__main__":
    unittest.main()
