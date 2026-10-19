from __future__ import annotations

import contextlib
import asyncio
import io
import json
import os
import plistlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
import datetime as dt
from unittest import mock
from pathlib import Path

import sys

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(PACKAGE_ROOT))

from setup_bridge import (  # noqa: E402
    SetupBridgeError,
    decode_request,
    encode_response,
    _error_payload,
    run_stdio,
)
from setup_journal import JournalStore  # noqa: E402
from setup_adapters import (  # noqa: E402
    ArtifactIdentity,
    ActivationReceiptObservation,
    DeviceObservation,
    InstalledAppObservation,
    PairingObservation,
    PinnedPymobiledeviceAdapter,
    ReadbackObservation,
    SupportObservation,
    FormalArtifactValidator,
    snapshot_artifact,
    _run,
    close_async_runtime,
)
from setup_config import SetupConfiguration  # noqa: E402
from setup_producer import SetupProducer  # noqa: E402
from setup_producer import support_method  # noqa: E402
from setup_delivery import deliver_v1_once  # noqa: E402
from setup_support import validate_generation  # noqa: E402


DEVICE = "0123456789abcdef0123456789abcdef01234567"
SETUP_ID = str(uuid.uuid4())
REQUEST_ID = str(uuid.uuid4())


def request(action: str = "status", **extra: object) -> dict[str, object]:
    value: dict[str, object] = {
        "protocol": 2,
        "requestID": REQUEST_ID,
        "operation": "setup",
        "action": action,
        "setupID": SETUP_ID,
        "deviceID": DEVICE,
        "mode": "install",
    }
    value.update(extra)
    return value


class ProtocolB1Tests(unittest.TestCase):
    def test_json_constants_nan_and_infinity_are_safe_invalid_request(self) -> None:
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "deviceID": float("nan")}).encode())
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps({**request(), "deviceID": float("inf")}).encode())

    def test_support_method_boundary_is_exact(self) -> None:
        self.assertEqual(support_method("26"), "personalized")
        self.assertEqual(support_method("26.3.9"), "personalized")
        self.assertEqual(support_method("26.4.0"), "cryptex")
        self.assertEqual(support_method("27"), "cryptex")
        with self.assertRaisesRegex(SetupBridgeError, "unsupported-os"):
            support_method("25.9")

    def test_request_rejects_unknown_and_duplicate_keys(self) -> None:
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(json.dumps(request(extraKey=True)).encode())
        duplicate = (
            '{"protocol":2,"requestID":"%s","operation":"setup",'
            '"action":"status","setupID":"%s","deviceID":"%s",'
            '"deviceID":"%s"}'
            % (REQUEST_ID, SETUP_ID, DEVICE, DEVICE)
        )
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(duplicate.encode())

    def test_apply_requires_exact_options_and_project_shape(self) -> None:
        valid = request(
            "apply",
            options={
                "source": "project",
                "artifactPath": None,
                "teamID": "ABCDEFGHIJ",
                "allowProvisioningUpdates": False,
            },
        )
        decoded = decode_request(json.dumps(valid).encode())
        self.assertEqual(decoded.options.source, "project")
        with self.assertRaisesRegex(SetupBridgeError, "invalid-request"):
            decode_request(
                json.dumps(
                    request(
                        "apply",
                        options={
                            "source": "project",
                            "artifactPath": "/tmp/GoFly.app",
                            "teamID": "ABCDEFGHIJ",
                            "allowProvisioningUpdates": False,
                        },
                    )
                ).encode()
            )

    def test_response_requires_all_proof_fields_and_is_bounded(self) -> None:
        payload = {
            "stage": "preflight",
            "outcome": "ready",
            "canResume": False,
            "proof": {
                "installationConfirmed": False,
                "pairingImported": False,
                "supportObserved": False,
            },
        }
        encoded = encode_response(
            request("preflight"),
            status="ok",
            payload=payload,
        )
        self.assertLessEqual(len(encoded), 256 * 1024)
        self.assertEqual(json.loads(encoded)["payload"]["proof"], payload["proof"])

    def test_complete_response_requires_bound_identity_and_can_resume_false(self) -> None:
        payload = {
            "stage": "complete",
            "outcome": "confirmed",
            "app": {
                "bundleID": "com.neven.gofly",
                "build": "19",
                "profileSHA256": "a" * 64,
                "executableSHA256": "b" * 64,
            },
            "teamID": "ABCDEFGHIJ",
            "expiresAt": "2030-01-01T00:00:00+00:00",
            "receiptSHA256": "c" * 64,
            "canResume": False,
            "proof": {
                "installationConfirmed": True,
                "pairingImported": True,
                "supportObserved": True,
            },
        }
        encoded = encode_response(request("apply"), status="ok", payload=payload)
        self.assertFalse(json.loads(encoded)["payload"]["canResume"])
        payload.pop("canResume")
        with self.assertRaisesRegex(SetupBridgeError, "operation-failed"):
            encode_response(request("apply"), status="ok", payload=payload)

    def test_formal_profile_validator_uses_gofly_identity_and_expiry(self) -> None:
        now = dt.datetime(2026, 10, 18, tzinfo=dt.timezone.utc)
        profile = {
            "Entitlements": {
                "application-identifier": "ABCDEFGHIJ.com.neven.gofly",
                "com.apple.developer.team-identifier": "ABCDEFGHIJ",
                "get-task-allow": True,
            },
            "TeamIdentifier": ["ABCDEFGHIJ"],
            "ProvisionedDevices": [DEVICE],
            "Platform": ["iOS"],
            "ExpirationDate": now + dt.timedelta(days=1),
        }
        signed = {
            "application-identifier": "ABCDEFGHIJ.com.neven.gofly",
            "com.apple.developer.team-identifier": "ABCDEFGHIJ",
            "get-task-allow": True,
        }
        info = {"CFBundleIdentifier": "com.neven.gofly", "CFBundleExecutable": "GoFly"}
        self.assertEqual(
            FormalArtifactValidator.validate_profile(
                info, signed, profile, device_id=DEVICE, team_id="ABCDEFGHIJ", now=now
            ),
            profile["ExpirationDate"],
        )
        with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
            FormalArtifactValidator.validate_profile(
                {**info, "CFBundleExecutable": "StikDebug"},
                signed,
                profile,
                device_id=DEVICE,
                team_id="ABCDEFGHIJ",
                now=now,
            )
        with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
            FormalArtifactValidator.validate_profile(
                info,
                signed,
                {**profile, "ExpirationDate": now},
                device_id=DEVICE,
                team_id="ABCDEFGHIJ",
                now=now,
            )

    def test_snapshot_artifact_rejects_missing_source(self) -> None:
        artifact = ArtifactIdentity(
            "/private/tmp/missing-gofly-source.app", "com.neven.gofly", "GoFly", "ABCDEFGHIJ",
            "a" * 64, "b" * 64, "c" * 64, "2030-01-01T00:00:00Z", {}, "19",
        )
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(SetupBridgeError, "artifact-mismatch"):
                snapshot_artifact(
                    artifact,
                    Path(directory) / "GoFly.app",
                    FakeArtifactValidator(),
                    device_id=DEVICE,
                    team_id="ABCDEFGHIJ",
                )

    def test_support_generation_requires_exact_method_and_closed_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "MountMethod").write_bytes(b"cryptex")
            os.chmod(root / "MountMethod", 0o600)
            manifest = {
                "BuildIdentities": [{
                    "Info": {"Variant": "Developer Disk Image Cryptex"},
                    "Cryptex1,Version": "1",
                    "Manifest": {
                        key: {"Info": {"Path": filename}}
                        for key, filename in (
                            ("Cryptex1,GenericDmg", "Image.dmg"),
                            ("Cryptex1,GenericTrustCache", "Image.dmg.trustcache"),
                            ("Cryptex1,CryptexInfoPlist", "Image.dmg.cryptex_info"),
                            ("Cryptex1,GenericVolume", "Image.dmg.root_hash"),
                        )
                    },
                }]
            }
            for filename in (
                "BuildManifest.plist",
                "Image.dmg",
                "Image.dmg.trustcache",
                "Image.dmg.cryptex_info",
                "Image.dmg.root_hash",
            ):
                (root / filename).write_bytes(
                    plistlib.dumps(manifest) if filename == "BuildManifest.plist" else b"asset"
                )
                os.chmod(root / filename, 0o600)
            generation = validate_generation("cryptex", root)
            self.assertEqual(generation.method, "cryptex")
            (root / "unexpected").write_bytes(b"extra")
            with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                validate_generation("cryptex", root)

    def test_readback_decoder_requires_exact_nonce_identity_and_pairing(self) -> None:
        value = {
            "version": 1,
            "setupID": SETUP_ID,
            "nonce": REQUEST_ID,
            "expectedDeviceUDID": DEVICE,
            "app": {
                "bundleID": "com.neven.gofly",
                "build": "19",
                "profileSHA256": "a" * 64,
                "executableSHA256": "b" * 64,
            },
            "pairing": {
                "kind": "verified",
                "expectedDeviceUDID": DEVICE,
                "sha256": "c" * 64,
            },
        }
        decoded = PinnedPymobiledeviceAdapter._decode_readback(
            json.dumps(value).encode(), device_id=DEVICE, setup_id=SETUP_ID, nonce=REQUEST_ID
        )
        self.assertEqual(decoded.pairing_sha256, "c" * 64)
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._decode_readback(
                json.dumps({**value, "nonce": str(uuid.uuid4())}).encode(),
                device_id=DEVICE,
                setup_id=SETUP_ID,
                nonce=REQUEST_ID,
            )

    def test_shared_setup_fixtures_match_production_manifest_and_readback_decoders(self) -> None:
        fixture_root = PACKAGE_ROOT.parents[3] / "app" / "GoFly" / "Tests" / "Fixtures" / "Setup"
        expected = {
            "personalized-manifest.json": (1320, "f64099af175bc9626fed5713e9923dbde64efed1f1b6d1b3b48d09ae105a51db"),
            "cryptex-manifest.json": (1657, "45b9e523c338e73ce7e97780c592ebf11f47b2347884afe92b2e1cd6e9abc24d"),
        }
        for name, (size, digest) in expected.items():
            raw = (fixture_root / name).read_bytes()
            self.assertEqual((len(raw), __import__("hashlib").sha256(raw).hexdigest()), (size, digest))
            value = json.loads(raw)
            self.assertEqual(value["method"], "personalized" if name.startswith("personalized") else "cryptex")
            decoded = PinnedPymobiledeviceAdapter._decode_formal_manifest(
                raw,
                device_id=value["expectedDeviceUDID"],
                setup_id=value["setupID"],
                nonce=value["nonce"],
            )
            self.assertEqual(decoded["artifacts"], value["artifacts"])

        receipt_raw = (fixture_root / "readback-receipt.json").read_bytes()
        self.assertEqual(__import__("hashlib").sha256(receipt_raw).hexdigest(), "7e924fab6f04105a66891e7836ef37a2c2a6cf4563e9d5bb8e37e9febf783e04")
        receipt_value = json.loads(receipt_raw)
        verified = PinnedPymobiledeviceAdapter._decode_readback(
            receipt_raw,
            device_id=receipt_value["expectedDeviceUDID"],
            setup_id=receipt_value["setupID"],
            nonce=receipt_value["nonce"],
        )
        self.assertEqual(verified.pairing_sha256, receipt_value["pairing"]["sha256"])
        for kind in ("absent", "invalid"):
            absent = dict(receipt_value)
            absent["pairing"] = {"kind": kind}
            decoded = PinnedPymobiledeviceAdapter._decode_readback(
                json.dumps(absent).encode(),
                device_id=receipt_value["expectedDeviceUDID"],
                setup_id=receipt_value["setupID"],
                nonce=receipt_value["nonce"],
            )
            self.assertEqual(decoded.pairing_sha256, "")
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._decode_readback(
                (fixture_root / "readback-request.json").read_bytes(),
                device_id=receipt_value["expectedDeviceUDID"],
                setup_id=receipt_value["setupID"],
                nonce=receipt_value["nonce"],
            )

    def test_activation_decoder_requires_committed_exact_receipt_inventory(self) -> None:
        names = [
            "MountMethod",
            "BuildManifest.plist",
            "Image.dmg",
            "Image.dmg.trustcache",
            "Image.dmg.cryptex_info",
            "Image.dmg.root_hash",
        ]
        receipt = {
            "version": 1,
            "setupID": SETUP_ID,
            "nonce": REQUEST_ID,
            "expectedDeviceUDID": DEVICE,
            "rawManifestSHA256": "d" * 64,
            "pairingTransactionID": str(uuid.uuid4()),
            "pairingSHA256": "c" * 64,
            "app": {
                "bundleID": "com.neven.gofly",
                "build": "19",
                "profileSHA256": "a" * 64,
                "executableSHA256": "b" * 64,
            },
            "teamID": "ABCDEFGHIJ",
            "signingExpiry": "2030-01-01T00:00:00Z",
            "deviceOS": "27.0",
            "method": "cryptex",
            "generationID": SETUP_ID,
            "artifacts": [
                {
                    "id": str(uuid.uuid5(uuid.UUID(SETUP_ID), name)),
                    "filename": name,
                    "byteCount": 1,
                    "sha256": (str(index + 1) * 64)[:64],
                }
                for index, name in enumerate(names)
            ],
            "status": "committed",
        }
        record = {"version": 1, "activeSetupID": SETUP_ID, "receipts": [receipt]}
        decoded = PinnedPymobiledeviceAdapter._decode_activation_receipt(
            json.dumps(record).encode(), device_id=DEVICE, setup_id=SETUP_ID, nonce=REQUEST_ID
        )
        self.assertEqual(decoded.raw_manifest_sha256, "d" * 64)
        self.assertEqual(decoded.generation_id, SETUP_ID)
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._decode_activation_receipt(
                json.dumps({**record, "receipts": [{**receipt, "status": "pending"}]}).encode(),
                device_id=DEVICE,
                setup_id=SETUP_ID,
                nonce=REQUEST_ID,
            )

        foreign_setup = str(uuid.uuid4())
        foreign = dict(receipt)
        foreign["setupID"] = foreign_setup
        foreign["generationID"] = foreign_setup
        foreign["artifacts"] = [
            {**artifact, "id": str(uuid.uuid5(uuid.UUID(foreign_setup), artifact["filename"]))}
            for artifact in receipt["artifacts"]
        ]
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._decode_activation_receipt(
                json.dumps({"version": 1, "activeSetupID": SETUP_ID, "receipts": [receipt, foreign]}).encode(),
                device_id=DEVICE,
                setup_id=SETUP_ID,
                nonce=REQUEST_ID,
            )

    def test_async_adapter_calls_retain_one_loop_and_background_callback(self) -> None:
        async def loop_with_callback() -> int:
            event = asyncio.Event()
            loop = asyncio.get_running_loop()
            loop.call_soon(event.set)
            await event.wait()
            return id(loop)

        try:
            first = _run(loop_with_callback())
            second = _run(loop_with_callback())
            self.assertEqual(first, second)
        finally:
            close_async_runtime()

    def test_remote_missing_is_distinguished_from_transport_error(self) -> None:
        class AfcFileNotFoundError(OSError):
            pass

        class Missing:
            def stat(self, _path: str) -> None:
                raise AfcFileNotFoundError()

        class Broken:
            def stat(self, _path: str) -> None:
                raise RuntimeError("transport failed")

        self.assertFalse(PinnedPymobiledeviceAdapter._remote_exists(Missing(), "missing"))
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._remote_exists(Broken(), "broken")

    def test_remote_bounded_read_uses_handle_and_rejects_growth(self) -> None:
        class Grown:
            def __init__(self) -> None:
                self.opened = 0
                self.closed = 0
                self.reads = 0

            def stat(self, _path: str) -> dict[str, object]:
                return {"st_ifmt": "S_IFREG", "st_size": 3}

            def get_file_contents(self, _path: str) -> bytes:
                return b"abc"

            async def fopen(self, _path: str, _mode: str) -> object:
                self.opened += 1
                return object()

            async def fread(self, _handle: object, _size: int) -> bytes:
                self.reads += 1
                return b"abc" if self.reads == 1 else b"X"

            async def fclose(self, _handle: object) -> None:
                self.closed += 1

        service = Grown()
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            PinnedPymobiledeviceAdapter._read_remote_bounded(service, "grown", max_bytes=16)
        self.assertEqual(service.opened, 1)
        self.assertEqual(service.closed, 1)

    def test_remote_pairing_service_is_candidate_bound_and_reports_verify(self) -> None:
        class Base:
            SERVICE_NAME = "com.apple.dt.remotepairingdeviced.lockdown"

            def __init__(self, _service: object, remote_identifier: str) -> None:
                self.remote_identifier = remote_identifier

            async def _attempt_pair_verify(self) -> None:
                return None

            async def _validate_pairing(self) -> bool:
                return True

        class Tunnel:
            RemotePairingLockdownService = Base

        class Client:
            async def start_lockdown_service(self, _name: str) -> object:
                return object()

        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "pairing.candidate"
            adapter = PinnedPymobiledeviceAdapter()
            service_cls = adapter._candidate_pairing_service_class(Tunnel, candidate, DEVICE)
            try:
                service = _run(service_cls.create(Client(), candidate, remote_identifier=DEVICE))
                self.assertEqual(service.pair_record_path, candidate)
                self.assertTrue(_run(service.connect(autopair=False)))
            finally:
                close_async_runtime()

    def test_pairing_candidate_wrong_mode_is_rejected_before_reconnect(self) -> None:
        record = {
            "public_key": b"p" * 32,
            "private_key": b"s" * 32,
            "remote_unlock_host_key": b"h" * 32,
            "identifier": str(uuid.uuid4()),
            "host_identifier": "same",
        }
        record["host_identifier"] = record["identifier"]
        with tempfile.TemporaryDirectory() as directory:
            candidate = Path(directory) / "pairing.candidate"
            candidate.write_bytes(plistlib.dumps(record))
            os.chmod(candidate, 0o644)
            adapter = PinnedPymobiledeviceAdapter()
            opened: list[str] = []

            def should_not_open(*_args: object, **_kwargs: object) -> object:
                opened.append("open")
                raise RuntimeError("hardware call")

            adapter._open = should_not_open  # type: ignore[method-assign]
            with self.assertRaisesRegex(SetupBridgeError, "pairing-unknown"):
                adapter.verify_pairing(DEVICE, candidate)
            self.assertEqual(opened, [])

    def test_handoff_requires_activation_receipt_after_readback_and_staging(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root / "state")
            config = SetupConfiguration(
                root,
                root / "python",
                root / "Developer",
                root / "GoFly.xcodeproj",
                "com.neven.gofly",
                "GoFly",
                root / "state",
            )
            artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
            journal = store.create(
                SETUP_ID,
                DEVICE,
                {
                    "source": "signedApp",
                    "artifactPath": "/tmp/GoFly.app",
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                    "targetBundleID": "com.neven.gofly",
                    "targetName": "GoFly",
                    "artifact": SetupProducer._artifact_dict(artifact),
                    "deviceObservation": {
                        "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                        "developerMode": True, "trust": True,
                    },
                },
            )
            journal["intent"]["artifact"] = SetupProducer._artifact_dict(artifact)
            journal["pairing"] = {"sha256": "c" * 64}
            journal["support"] = {
                "method": "cryptex",
                "osVersion": "27.0",
                "generationID": SETUP_ID,
                "identifier": "com.apple.MobileAsset.DDI",
                "version": "1",
                "inputFiles": {
                    "MountMethod": [8, "1" * 64], "manifest": [8, "2" * 64],
                    "image": [8, "3" * 64], "trustcache": [8, "4" * 64],
                    "cryptex_info": [8, "5" * 64], "root_hash": [8, "6" * 64],
                },
                "inputManifestSHA256": "2" * 64,
            }
            journal["delivery"] = {"state": "delivered"}
            for stage in ("artifact", "pairing", "install", "support"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": True,
                "supportObserved": True,
            }
            store.update(journal)

            class ReadbackOnlyDevice:
                def __init__(self) -> None:
                    self.calls: list[str] = []

                def observe(self, _device: str) -> DeviceObservation:
                    self.calls.append("observe")
                    return DeviceObservation(DEVICE, "27.0", "USB", True, True)

                def query_support(self, _device: str, method: str) -> SupportObservation:
                    self.calls.append("query_support")
                    return SupportObservation(True, method, "27.0", SETUP_ID, "com.apple.MobileAsset.DDI", "1")

                def prepare_readback(self, *_args: object) -> None:
                    self.calls.append("prepare_readback")

                def launch(self, _device: str) -> int:
                    self.calls.append("launch")
                    return 100

                def readback(self, *_args: object) -> ReadbackObservation:
                    self.calls.append("readback")
                    return ReadbackObservation(
                        REQUEST_ID,
                        SETUP_ID,
                        DEVICE,
                        "",
                        artifact.executable_sha256,
                        artifact.profile_sha256,
                        "c" * 64,
                        build=artifact.build,
                    )

                def stop(self, _device: str, _expected_pid: int | None = None) -> None:
                    self.calls.append("stop")

            device = ReadbackOnlyDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
                producer._handoff(
                    store.read(),
                    decode_request(json.dumps(request("status")).encode()),
                    artifact,
                )
            self.assertEqual(device.calls, ["observe", "prepare_readback", "observe", "launch", "readback"])

    def test_activation_receipt_artifacts_match_frozen_formal_inventory(self) -> None:
        artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
        pairing_tx = str(uuid.uuid4())
        nonce = str(uuid.uuid4())
        filename = "MountMethod"
        expected_id = str(uuid.uuid5(uuid.UUID(SETUP_ID), filename))
        journal = {
            "setupID": SETUP_ID,
            "deviceID": DEVICE,
            "intent": {"pairingTransactionID": pairing_tx},
            "pairing": {"sha256": "c" * 64},
            "support": {"method": "cryptex", "osVersion": "27.0", "generationID": SETUP_ID},
            "handoff": {
                "nonce": nonce,
                "formalArtifacts": [{"id": expected_id, "filename": filename, "byteCount": 1, "sha256": "d" * 64}],
            },
        }
        receipt = ActivationReceiptObservation(
            SETUP_ID, nonce, DEVICE, "e" * 64, pairing_tx, "c" * 64,
            artifact.bundle_id, artifact.build, artifact.profile_sha256, artifact.executable_sha256,
            artifact.team_id, artifact.expires_at, "27.0", "cryptex", SETUP_ID,
            ((filename, 1, "d" * 64),),
            ((expected_id, filename, 1, "a" * 64),),
        )
        with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
            SetupProducer._validate_activation_receipt(
                receipt,
                request=decode_request(json.dumps(request("status", setupID=SETUP_ID)).encode()),
                artifact=artifact,
                journal=journal,
                manifest_sha256="e" * 64,
            )

    def test_resume_handoff_requires_frozen_formal_plan(self) -> None:
        artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
        journal = {
            "setupID": SETUP_ID,
            "deviceID": DEVICE,
            "intent": {"pairingTransactionID": str(uuid.uuid4())},
            "pairing": {"sha256": "c" * 64},
            "support": {
                "method": "cryptex", "osVersion": "27.0", "generationID": SETUP_ID,
                "inputFiles": {
                    "MountMethod": [8, "1" * 64], "manifest": [8, "2" * 64],
                    "image": [8, "3" * 64], "trustcache": [8, "4" * 64],
                    "cryptex_info": [8, "5" * 64], "root_hash": [8, "6" * 64],
                },
                "inputManifestSHA256": "2" * 64,
            },
            "handoff": {"nonce": str(uuid.uuid4()), "setupID": SETUP_ID},
            "delivery": {"state": "delivered"},
        }
        with self.assertRaisesRegex(SetupBridgeError, "transaction-unknown"):
            SetupProducer._frozen_plan_from_handoff(
                object.__new__(SetupProducer), journal, request=decode_request(json.dumps(request("resume")).encode()), artifact=artifact
            )

    def test_handoff_orders_readback_stop_manifest_then_committed_activation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root / "state")
            config = SetupConfiguration(
                root,
                root / "python",
                root / "Developer",
                root / "GoFly.xcodeproj",
                "com.neven.gofly",
                "GoFly",
                root / "state",
            )
            artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
            journal = store.create(
                SETUP_ID,
                DEVICE,
                {
                    "source": "signedApp",
                    "artifactPath": "/tmp/GoFly.app",
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                    "targetBundleID": "com.neven.gofly",
                    "targetName": "GoFly",
                    "artifact": SetupProducer._artifact_dict(artifact),
                    "deviceObservation": {
                        "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                        "developerMode": True, "trust": True,
                    },
                },
            )
            journal["intent"]["artifact"] = SetupProducer._artifact_dict(artifact)
            journal["pairing"] = {"sha256": "c" * 64}
            journal["support"] = {
                "method": "cryptex",
                "osVersion": "27.0",
                "generationID": SETUP_ID,
                "identifier": "com.apple.MobileAsset.DDI",
                "version": "1",
                "inputFiles": {
                    "MountMethod": [8, "1" * 64], "manifest": [8, "2" * 64],
                    "image": [8, "3" * 64], "trustcache": [8, "4" * 64],
                    "cryptex_info": [8, "5" * 64], "root_hash": [8, "6" * 64],
                },
                "inputManifestSHA256": "2" * 64,
            }
            journal["delivery"] = {"state": "delivered"}
            for stage in ("artifact", "pairing", "install", "support"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": True,
                "supportObserved": True,
            }
            store.update(journal)
            pairing_transaction = journal["intent"]["pairingTransactionID"]

            class FullHandoffDevice:
                def __init__(self) -> None:
                    self.calls: list[str] = []
                    self.pid = 100
                    self.plan_visible = False

                def observe(self, _device: str) -> DeviceObservation:
                    self.calls.append("observe")
                    return DeviceObservation(DEVICE, "27.0", "USB", True, True)

                def query_support(self, _device: str, method: str) -> SupportObservation:
                    self.calls.append("query_support")
                    return SupportObservation(True, method, "27.0", SETUP_ID, "com.apple.MobileAsset.DDI", "1")

                def prepare_readback(self, *_args: object) -> None:
                    self.calls.append("prepare_readback")
                    durable = store.read()
                    self.plan_visible = bool(
                        durable
                        and durable.get("stages", {}).get("handoff", {}).get("state") == "inflight"
                        and durable.get("handoff", {}).get("rawManifest")
                        and durable.get("handoff", {}).get("manifestSHA256")
                        and durable.get("handoff", {}).get("formalArtifacts")
                    )

                def launch(self, _device: str) -> int:
                    self.calls.append("launch")
                    self.pid += 1
                    return self.pid

                def readback(self, _device: str, setup: str, nonce: str) -> ReadbackObservation:
                    self.calls.append("readback")
                    return ReadbackObservation(
                        nonce,
                        setup,
                        DEVICE,
                        "",
                        artifact.executable_sha256,
                        artifact.profile_sha256,
                        "c" * 64,
                        build=artifact.build,
                    )

                def prepare_setup_input(self, *_args: object, plan: object) -> str:
                    self.calls.append("prepare_input")
                    self.plan = plan
                    return plan.sha256

                def read_activation_receipt(self, _device: str, setup: str, nonce: str) -> ActivationReceiptObservation:
                    self.calls.append("activation")
                    return ActivationReceiptObservation(
                        setup,
                        nonce,
                        DEVICE,
                        self.plan.sha256,
                        pairing_transaction,
                        "c" * 64,
                        artifact.bundle_id,
                        artifact.build,
                        artifact.profile_sha256,
                        artifact.executable_sha256,
                        artifact.team_id,
                        artifact.expires_at,
                        "27.0",
                        "cryptex",
                        SETUP_ID,
                        self.plan.artifacts,
                        self.plan.artifacts,
                    )

                def stop(self, _device: str, _expected_pid: int | None = None) -> None:
                    self.calls.append("stop")

            device = FullHandoffDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            generation = type(
                "Generation",
                (),
                {
                    "files": {
                        "MountMethod": (8, "1" * 64),
                        "manifest": (8, "2" * 64),
                        "image": (8, "3" * 64),
                        "trustcache": (8, "4" * 64),
                        "cryptex_info": (8, "5" * 64),
                        "root_hash": (8, "6" * 64),
                    },
                    "manifest_sha256": "2" * 64,
                },
            )()
            with mock.patch("setup_support.validate_generation", return_value=generation):
                result = producer._handoff(
                    store.read(),
                    decode_request(json.dumps(request("status")).encode()),
                    artifact,
                )
            self.assertEqual(result["stages"]["handoff"]["state"], "confirmed")
            self.assertTrue(device.plan_visible)
            self.assertEqual(
                device.calls,
                [
                    "observe", "prepare_readback", "observe", "launch", "readback", "observe", "stop",
                    "observe", "prepare_input", "observe", "launch", "activation", "observe", "stop",
                    "observe", "query_support",
                ],
            )

    def test_public_resume_reconciles_first_pid_before_v1_and_formal_marker(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root / "state")
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "signedApp", "artifactPath": "/tmp/GoFly.app",
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                "artifact": SetupProducer._artifact_dict(artifact),
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            journal["intent"]["artifact"] = SetupProducer._artifact_dict(artifact)
            journal["pairing"] = {"sha256": "c" * 64}
            journal["support"] = {
                "method": "cryptex", "osVersion": "27.0", "generationID": SETUP_ID,
                "identifier": "com.apple.MobileAsset.DDI", "version": "1",
                "inputFiles": {
                    "MountMethod": [8, "1" * 64], "manifest": [8, "2" * 64],
                    "image": [8, "3" * 64], "trustcache": [8, "4" * 64],
                    "cryptex_info": [8, "5" * 64], "root_hash": [8, "6" * 64],
                },
                "inputManifestSHA256": "2" * 64,
            }
            journal["stages"]["artifact"] = {"state": "confirmed"}
            journal["stages"]["pairing"] = {"state": "confirmed"}
            journal["stages"]["install"] = {"state": "confirmed"}
            journal["stages"]["support"] = {"state": "confirmed"}
            journal["stages"]["handoff"] = {"state": "pending"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": False,
                "supportObserved": True,
            }
            store.update(journal)

            class FirstPidBeforeV1Device:
                def __init__(self) -> None:
                    self.stop_calls = 0
                    self.launch_calls = 0
                    self.delivery_calls = 0
                    self.receipt_calls = 0
                    self.boundary_calls = 0
                    self.changed_boundary: int | None = None
                    self.changed_observation: DeviceObservation | None = None
                    self.return_no_activation = False
                    self.activation_marker_values: list[object] = []
                    self.plan: object | None = None

                def observe(self, _device: str) -> DeviceObservation:
                    self.boundary_calls += 1
                    if self.changed_boundary == self.boundary_calls and self.changed_observation is not None:
                        return self.changed_observation
                    return DeviceObservation(DEVICE, "27.0", "USB", True, True)

                def query_support(self, _device: str, method: str) -> SupportObservation:
                    return SupportObservation(True, method, "27.0", SETUP_ID, "com.apple.MobileAsset.DDI", "1")

                def prepare_readback(self, *_args: object) -> None:
                    return None

                def launch(self, _device: str) -> int:
                    self.launch_calls += 1
                    return 100 + self.launch_calls

                def readback(self, _device: str, setup: str, nonce: str) -> ReadbackObservation:
                    return ReadbackObservation(
                        nonce, setup, DEVICE, "", artifact.executable_sha256,
                        artifact.profile_sha256, "c" * 64, build=artifact.build,
                    )

                def stop(self, _device: str, _expected_pid: int | None = None) -> None:
                    self.stop_calls += 1
                    if self.stop_calls == 1:
                        raise RuntimeError("controlled crash before first stop")

                def deliver_pairing(self, _device: str, _setup: str) -> None:
                    self.delivery_calls += 1

                def prepare_setup_input(self, *_args: object, plan: object) -> str:
                    self.plan = plan
                    return plan.sha256

                def formal_inventory(self, _setup: str, _nonce: str) -> tuple[tuple[str, str, int, str], ...]:
                    return self.plan.artifacts

                def read_activation_receipt(self, _device: str, setup: str, nonce: str) -> ActivationReceiptObservation | None:
                    self.receipt_calls += 1
                    if self.return_no_activation:
                        return None
                    durable = store.read()
                    marker = durable.get("handoff", {}).get("formalPublished") if durable else None
                    self.activation_marker_values.append(marker)
                    self.assert_marker(marker)
                    return ActivationReceiptObservation(
                        setup, nonce, DEVICE, self.plan.sha256,
                        journal["intent"]["pairingTransactionID"], "c" * 64,
                        artifact.bundle_id, artifact.build, artifact.profile_sha256,
                        artifact.executable_sha256, artifact.team_id, artifact.expires_at,
                        "27.0", "cryptex", SETUP_ID,
                        self.plan.artifacts, self.plan.artifacts,
                    )

                @staticmethod
                def assert_marker(value: object) -> None:
                    if value is not True:
                        raise AssertionError("activation polled before formalPublished")

            device = FirstPidBeforeV1Device()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            generation = type(
                "Generation",
                (),
                {
                    "files": {
                        "MountMethod": (8, "1" * 64), "manifest": (8, "2" * 64),
                        "image": (8, "3" * 64), "trustcache": (8, "4" * 64),
                        "cryptex_info": (8, "5" * 64), "root_hash": (8, "6" * 64),
                    },
                    "manifest_sha256": "2" * 64,
                },
            )()
            resume_request = decode_request(json.dumps(request("resume")).encode())
            with mock.patch("setup_support.validate_generation", return_value=generation):
                with self.assertRaisesRegex(RuntimeError, "controlled crash"):
                    producer.handle(resume_request)
                crashed = store.read()
                self.assertEqual(crashed["handoff"]["formalPublished"], False)
                self.assertEqual(crashed["handoff"]["launchedPID"], 101)
                self.assertEqual(crashed["delivery"]["state"], "notStarted")
                result = producer.handle(resume_request)
            self.assertEqual(result.stage, "complete")
            self.assertEqual(result.outcome, "confirmed")
            self.assertEqual(device.delivery_calls, 1)
            self.assertEqual(device.activation_marker_values, [True])

            # A durable formal marker does not waive the fresh device binding
            # before activation receipt read.  This is exercised through the
            # public handle(resume) seam: a changed OS must stop before the
            # receipt adapter is touched.
            durable = store.read()
            durable["stages"]["handoff"] = {"state": "unknown"}
            durable["stages"]["complete"] = {"state": "pending"}
            durable.pop("receiptSHA256", None)
            store.update(durable)
            receipt_calls = device.receipt_calls
            launch_calls = device.launch_calls
            device.changed_boundary = device.boundary_calls + 1
            device.changed_observation = DeviceObservation(DEVICE, "26.0", "USB", True, True)
            with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
                producer.handle(resume_request)
            self.assertEqual(device.receipt_calls, receipt_calls)
            self.assertEqual(device.launch_calls, launch_calls)

            # The same pre-receipt boundary rejects developer mode changes;
            # this keeps the test on the public resume seam for each part of
            # the frozen device binding.
            durable = store.read()
            durable["stages"]["handoff"] = {"state": "unknown"}
            durable["stages"]["complete"] = {"state": "pending"}
            durable.pop("receiptSHA256", None)
            store.update(durable)
            receipt_calls = device.receipt_calls
            device.changed_boundary = device.boundary_calls + 1
            device.changed_observation = DeviceObservation(DEVICE, "27.0", "USB", False, True)
            with self.assertRaisesRegex(SetupBridgeError, "developer-mode-required"):
                producer.handle(resume_request)
            self.assertEqual(device.receipt_calls, receipt_calls)

            # The first boundary before the receipt read may pass, while the
            # second boundary before the recovery launch must still reject a
            # changed trust binding.  No second launch is permitted.
            durable = store.read()
            durable["stages"]["handoff"] = {"state": "unknown"}
            durable["stages"]["complete"] = {"state": "pending"}
            durable.pop("receiptSHA256", None)
            store.update(durable)
            device.return_no_activation = True
            device.changed_boundary = device.boundary_calls + 2
            device.changed_observation = DeviceObservation(DEVICE, "27.0", "USB", True, False)
            launch_calls = device.launch_calls
            with self.assertRaisesRegex(SetupBridgeError, "trust-required"):
                producer.handle(resume_request)
            self.assertEqual(device.launch_calls, launch_calls)
            device.return_no_activation = False
            device.changed_boundary = None
            device.changed_observation = None

            durable = store.read()
            durable["stages"]["handoff"] = {"state": "unknown"}
            durable["stages"]["complete"] = {"state": "pending"}
            durable.pop("receiptSHA256", None)
            store.update(durable)
            mutated_generation = type(
                "Generation",
                (),
                {
                    "files": {
                        "MountMethod": (8, "9" * 64), "manifest": (8, "9" * 64),
                        "image": (8, "9" * 64), "trustcache": (8, "9" * 64),
                        "cryptex_info": (8, "9" * 64), "root_hash": (8, "9" * 64),
                    },
                    "manifest_sha256": "9" * 64,
                },
            )()
            with mock.patch("setup_support.validate_generation", return_value=mutated_generation):
                with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                    producer.handle(resume_request)
            self.assertEqual(store.read()["stages"]["support"]["state"], "unknown")


class JournalB1Tests(unittest.TestCase):
    def test_delivery_unknown_status_is_query_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            config = SetupConfiguration(root, root / "python", root / "Developer", project,
                                        "com.neven.gofly", "GoFly", state)
            store = JournalStore(state)
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            journal["delivery"] = {"state": "unknown"}
            store.update(journal)
            producer = SetupProducer(config, store=store, device=ResumePairDevice())
            payload = producer.status(decode_request(json.dumps(request("status")).encode()))
            self.assertFalse(payload.can_resume)
            error_payload = _error_payload(decode_request(json.dumps(request("status")).encode()), config)
            self.assertFalse(error_payload["canResume"])

    def test_status_rejects_wrong_private_root_mode_without_chmod(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "state"
            root.mkdir(mode=0o700)
            os.chmod(root, 0o755)
            with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                JournalStore(root).read()
            self.assertEqual(os.stat(root).st_mode & 0o777, 0o755)

    def test_status_rejects_hardlinked_journal_and_reads_nonblocking(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root)
            store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            os.link(root / "journal.json", root / "journal-copy.json")
            with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                store.read()
            (root / "journal-copy.json").unlink()
            with mock.patch("setup_journal.os.open", wraps=os.open) as opened:
                self.assertIsNotNone(store.read())
                self.assertTrue(any(
                    len(call.args) >= 2 and call.args[0] == root / "journal.json"
                    and call.args[1] & getattr(os, "O_NONBLOCK", 0)
                    for call in opened.call_args_list
                ))

    def test_journal_read_rejects_growth_after_initial_bound(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root)
            store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            path = root / "journal.json"
            path.write_bytes(path.read_bytes() + b"\n")
            real_fstat = os.fstat
            calls = 0

            def grown_after_bound(fd: int) -> os.stat_result:
                nonlocal calls
                calls += 1
                info = real_fstat(fd)
                if calls == 3:
                    values = list(info)
                    values[6] -= 1
                    return os.stat_result(values)
                return info

            with mock.patch("setup_journal.os.fstat", side_effect=grown_after_bound):
                with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                    store.read()

    def test_boundary_reobserve_rejects_changed_frozen_device_before_write(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            store = JournalStore(root / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            device = ChangingBoundaryDevice()
            producer = SetupProducer(config, store=store, device=device)
            with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
                producer._boundary_observe(journal, DEVICE)
            self.assertEqual(device.boundary_calls, 1)

    def test_support_input_inventory_is_durable_before_installer_boundary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            store = JournalStore(root / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })

            class Support:
                def __init__(self) -> None:
                    self.installer_saw_input = False

                def query(self, _device: str, method: str) -> SupportObservation:
                    return SupportObservation(False, method, "27.0")

                def prepare_generation(self, _method: str, _restore: Path) -> object:
                    return object()

                def install(self, _device: str, method: str, _restore: Path) -> SupportObservation:
                    current = store.read()
                    self.installer_saw_input = (
                        current["stages"]["support"]["state"] == "inflight"
                        and current["support"]["inputFiles"]["manifest"] == [4, "a" * 64]
                    )
                    return SupportObservation(True, method, "27.0", SETUP_ID, "com.apple.MobileAsset.DDI", "1")

            support = Support()
            generation = type("Generation", (), {"files": {"manifest": (4, "a" * 64)}, "manifest_sha256": "a" * 64})()
            with mock.patch("setup_support.validate_generation", return_value=generation):
                producer = SetupProducer(config, store=store, device=ResumePairDevice(), support=support)
                result = producer._support(
                    journal,
                    decode_request(json.dumps(request("status")).encode()),
                    DeviceObservation(DEVICE, "27.0", "USB", True, True),
                )
            self.assertTrue(support.installer_saw_input)
            self.assertEqual(result["stages"]["support"]["state"], "confirmed")

    def test_public_resume_rejects_mutated_confirmed_support_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            store = JournalStore(root / "state")
            artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "signedApp", "artifactPath": "/tmp/GoFly.app",
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                "artifact": SetupProducer._artifact_dict(artifact),
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            journal["intent"]["artifact"] = SetupProducer._artifact_dict(artifact)
            journal["pairing"] = {"sha256": "c" * 64}
            journal["support"] = {
                "method": "cryptex", "osVersion": "27.0", "generationID": SETUP_ID,
                "identifier": "com.apple.MobileAsset.DDI", "version": "1",
                "inputFiles": {"manifest": [4, "a" * 64]},
                "inputManifestSHA256": "a" * 64,
            }
            for stage in ("artifact", "pairing", "install", "handoff"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["stages"]["support"] = {"state": "unknown"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": False,
                "supportObserved": False,
            }
            store.update(journal)

            class MutatedSupportDevice:
                def __init__(self) -> None:
                    self.install_calls = 0

                def observe(self, _device: str) -> DeviceObservation:
                    return DeviceObservation(DEVICE, "27.0", "USB", True, True)

                def query_support(self, _device: str, method: str) -> SupportObservation:
                    return SupportObservation(True, method, "27.0", SETUP_ID, "com.apple.MobileAsset.DDI", "1")

                def install_support(self, *_args: object) -> SupportObservation:
                    self.install_calls += 1
                    raise AssertionError("mutated local input must fail before installer")

            generation = type(
                "Generation",
                (),
                {"files": {"manifest": (4, "b" * 64)}, "manifest_sha256": "b" * 64},
            )()
            device = MutatedSupportDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            with mock.patch("setup_support.validate_generation", return_value=generation):
                with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                    producer.handle(decode_request(json.dumps(request("resume")).encode()))
            self.assertEqual(store.read()["stages"]["support"]["state"], "unknown")
            self.assertEqual(device.install_calls, 0)

    def test_public_resume_rejects_observed_support_missing_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            store = JournalStore(root / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                "deviceObservation": {
                    "deviceID": DEVICE, "osVersion": "27.0", "transport": "USB",
                    "developerMode": True, "trust": True,
                },
            })
            for stage in ("artifact", "pairing", "install", "handoff"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["stages"]["support"] = {"state": "unknown"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": False,
                "supportObserved": False,
            }
            store.update(journal)

            class MissingIdentitySupportDevice:
                def __init__(self) -> None:
                    self.query_calls = 0
                    self.prepare_calls = 0
                    self.install_calls = 0

                def observe(self, _device: str) -> DeviceObservation:
                    return DeviceObservation(DEVICE, "27.0", "USB", True, True)

                def query_support(self, _device: str, method: str) -> SupportObservation:
                    self.query_calls += 1
                    return SupportObservation(True, method, "27.0", None, None, None)

                def prepare_generation(self, _method: str, _restore: Path) -> None:
                    self.prepare_calls += 1

                def install_support(self, *_args: object) -> SupportObservation:
                    self.install_calls += 1
                    raise AssertionError("missing identity must not reinstall")

            generation = type(
                "Generation",
                (),
                {"files": {"manifest": (4, "a" * 64)}, "manifest_sha256": "a" * 64},
            )()
            device = MissingIdentitySupportDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            with mock.patch("setup_support.validate_generation", return_value=generation):
                with self.assertRaisesRegex(SetupBridgeError, "support-unavailable"):
                    producer.handle(decode_request(json.dumps(request("resume")).encode()))
            self.assertEqual(store.read()["stages"]["support"]["state"], "unknown")
            self.assertEqual(device.query_calls, 1)
            self.assertEqual(device.install_calls, 0)

    def test_completed_journal_cannot_be_replaced_on_same_device(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            store = JournalStore(state)
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            for stage in ("artifact", "pairing", "install", "support", "handoff", "complete"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["proof"] = {
                "installationConfirmed": True,
                "pairingImported": True,
                "supportObserved": True,
            }
            journal_without_receipt = dict(journal)
            journal_without_receipt.pop("receiptSHA256", None)
            journal["receiptSHA256"] = __import__("hashlib").sha256(
                json.dumps(journal_without_receipt, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            store.update(journal)

            class ExistingDevice:
                def observe(self, device_id: str) -> DeviceObservation:
                    return DeviceObservation(device_id, "27.0", "USB", True, True)

                def installed(self, _device_id: str) -> InstalledAppObservation:
                    return InstalledAppObservation(False)

            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", state,
            )
            producer = SetupProducer(config, store=store, device=ExistingDevice())
            replacement = request(
                "apply",
                setupID=str(uuid.uuid4()),
                options={
                    "source": "project",
                    "artifactPath": None,
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                },
            )
            with self.assertRaisesRegex(SetupBridgeError, "transaction-conflict"):
                producer.handle(decode_request(json.dumps(replacement).encode()))
            self.assertEqual(store.read()["setupID"], SETUP_ID)

    def test_completed_journal_archives_only_after_receipt_and_global_lock(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            store = JournalStore(root)
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            with self.assertRaisesRegex(SetupBridgeError, "transaction-unknown"):
                store.archive_completed(SETUP_ID, DEVICE)
            transaction = store.transaction_root(SETUP_ID)
            artifact_path = transaction / "artifact" / "GoFly.app"
            artifact_path.mkdir(parents=True, mode=0o700)
            (artifact_path / "GoFly").write_bytes(b"signed")
            os.chmod(artifact_path / "GoFly", 0o755)
            candidate = transaction / "pairing.candidate"
            candidate.write_bytes(b"pairing")
            os.chmod(candidate, 0o600)
            artifact = {
                "path": str(artifact_path), "bundleID": "com.neven.gofly", "executable": "GoFly",
                "teamID": "ABCDEFGHIJ", "artifactSHA256": "a" * 64,
                "executableSHA256": "b" * 64, "profileSHA256": "c" * 64,
                "expiresAt": "2030-01-01T00:00:00Z", "build": "19",
            }
            journal["intent"]["artifact"] = artifact
            journal["pairing"] = {"candidate": f"transactions/{SETUP_ID}/pairing.candidate", "sha256": __import__("hashlib").sha256(b"pairing").hexdigest()}
            journal["support"] = {
                "method": "cryptex", "osVersion": "27.0", "generationID": SETUP_ID,
                "identifier": "com.apple.MobileAsset.DDI", "version": "1",
                "inputFiles": {"manifest": [1, "d" * 64]}, "inputManifestSHA256": "d" * 64,
            }
            nonce = str(uuid.uuid4())
            filename = "MountMethod"
            formal = [{"id": str(uuid.uuid5(uuid.UUID(SETUP_ID), filename)), "filename": filename, "byteCount": 1, "sha256": "e" * 64}]
            raw_manifest = "frozen-formal-input"
            manifest_sha = __import__("hashlib").sha256(raw_manifest.encode()).hexdigest()
            journal["handoff"] = {
                "nonce": nonce, "setupID": SETUP_ID, "rawManifest": raw_manifest,
                "manifestSHA256": manifest_sha, "formalArtifacts": formal,
            }
            journal["delivery"] = {"state": "delivered"}
            journal["activationReceipt"] = {
                "setupID": SETUP_ID, "nonce": nonce, "deviceID": DEVICE, "rawManifestSHA256": manifest_sha,
                "pairingTransactionID": journal["intent"]["pairingTransactionID"],
                "pairingSHA256": journal["pairing"]["sha256"], "bundleID": "com.neven.gofly", "build": "19",
                "profileSHA256": "c" * 64, "executableSHA256": "b" * 64, "teamID": "ABCDEFGHIJ",
                "signingExpiry": "2030-01-01T00:00:00Z", "deviceOS": "27.0", "method": "cryptex",
                "generationID": SETUP_ID, "artifacts": formal,
            }
            for stage in ("artifact", "pairing", "install", "support", "handoff", "complete"):
                journal["stages"][stage] = {"state": "confirmed"}
            journal["proof"] = {"installationConfirmed": True, "pairingImported": True, "supportObserved": True}
            journal["installOwnership"] = {
                "transactionID": SETUP_ID, "bundleID": "com.neven.gofly", "build": "19",
                "artifactSHA256": "a" * 64, "executableSHA256": "b" * 64, "profileSHA256": "c" * 64,
            }
            journal["receiptSHA256"] = "0" * 64
            without_receipt = dict(journal)
            without_receipt.pop("receiptSHA256")
            journal["receiptSHA256"] = __import__("hashlib").sha256(
                json.dumps(without_receipt, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()
            store.update(journal)
            archive = store.archive_completed(SETUP_ID, DEVICE)
            self.assertTrue(archive.is_file())
            self.assertIsNone(store.read())
            self.assertEqual(json.loads(archive.read_text())["operation"], "setup")

    def test_reopen_maps_inflight_stage_and_delivery_to_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory))
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            journal["stages"]["install"] = {"state": "inflight"}
            journal["delivery"] = {"state": "inflight"}
            store.update(journal)
            snapshot = store.reopen_snapshot()
            self.assertEqual(snapshot["stages"]["install"]["state"], "unknown")
            self.assertEqual(snapshot["delivery"]["state"], "unknown")
            self.assertEqual(store.read()["stages"]["install"]["state"], "inflight")

    def test_authoritative_header_is_written_with_fsyncable_journal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory))
            intent = {
                "source": "project",
                "artifactPath": None,
                "teamID": "ABCDEFGHIJ",
                "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly",
            }
            store.create(SETUP_ID, DEVICE, intent)
            raw = json.loads((Path(directory) / "journal.json").read_text())
            self.assertEqual(
                {raw[key] for key in ("version", "operation", "setupID", "deviceID")},
                {1, "setup", SETUP_ID, DEVICE},
            )
            self.assertTrue((Path(directory) / "operation.lock").is_file())

    def test_symlink_journal_is_rejected_and_lock_is_nonblocking(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "elsewhere.json"
            target.write_text("{}")
            (root / "journal.json").symlink_to(target)
            with self.assertRaisesRegex(SetupBridgeError, "storage-unavailable"):
                JournalStore(root).read()
            (root / "journal.json").unlink()
            first = JournalStore(root).lock()
            second = JournalStore(root).lock()
            with first:
                with self.assertRaisesRegex(SetupBridgeError, "busy"):
                    with second:
                        pass

    def test_install_unknown_never_resubmits_or_adopts_matching_observation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            (root / "Developer").mkdir()
            config = SetupConfiguration(root, root / "python", root / "Developer", project,
                                        "com.neven.gofly", "GoFly", root / "state")
            # The production snapshot boundary requires a real source tree;
            # the validator remains the controlled seam for this test.
            (root / "GoFly.app").mkdir()
            device = UnknownInstallDevice()
            producer = SetupProducer(
                config,
                device=device,
                artifact_validator=FakeArtifactValidator(),
            )
            apply_request = request(
                "apply",
                options={
                    "source": "signedApp",
                    "artifactPath": str(root / "GoFly.app"),
                    "teamID": "ABCDEFGHIJ",
                    "allowProvisioningUpdates": False,
                },
            )
            # The validator is controlled, so no filesystem artifact or Apple
            # tool is reached by this test.
            with self.assertRaisesRegex(Exception, "runtime-api-mismatch"):
                producer.handle(decode_request(json.dumps(apply_request).encode()))
            journal = JournalStore(root / "state").read()
            self.assertEqual(journal["stages"]["pairing"]["state"], "unknown")

            resumed = producer.handle(
                decode_request(json.dumps(request("resume")).encode())
            )
            self.assertEqual(resumed.outcome, "unknown")
            self.assertEqual(device.install_calls, 1)
            self.assertEqual(device.launch_calls, 0)
            self.assertEqual(device.delivery_calls, 0)

    def test_resume_pairing_unknown_verifies_retained_candidate_without_repair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            (root / "Developer").mkdir()
            config = SetupConfiguration(root, root / "python", root / "Developer", project,
                                        "com.neven.gofly", "GoFly", root / "state")
            store = JournalStore(root / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "signedApp", "artifactPath": str(root / "GoFly.app"),
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            artifact = FakeArtifactValidator().inspect("/tmp/GoFly.app", device_id=DEVICE, team_id="ABCDEFGHIJ")
            journal["intent"]["artifact"] = SetupProducer._artifact_dict(artifact)
            journal["stages"]["artifact"] = {"state": "confirmed"}
            journal["stages"]["pairing"] = {"state": "unknown"}
            (store.transaction_root(SETUP_ID) / "pairing.candidate").write_bytes(b"retained")
            journal["pairing"] = {"candidate": f"transactions/{SETUP_ID}/pairing.candidate", "sha256": "d" * 64}
            store.update(journal)
            device = ResumePairDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            result = producer.handle(decode_request(json.dumps(request("resume")).encode()))
            self.assertEqual(result.stage, "install")
            self.assertEqual(result.outcome, "inProgress")
            self.assertEqual(device.verify_calls, 1)
            self.assertEqual(device.pair_calls, 0)

    def test_resume_pending_artifact_rebuilds_before_pair_or_install(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = SetupConfiguration(
                root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                "com.neven.gofly", "GoFly", root / "state",
            )
            store = JournalStore(root / "state")
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "signedApp", "artifactPath": str(root / "GoFly.app"),
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            journal["stages"]["artifact"] = {"state": "pending"}
            journal["stages"]["pairing"] = {"state": "unknown"}
            journal["stages"]["install"] = {"state": "unknown"}
            (store.transaction_root(SETUP_ID) / "pairing.candidate").write_bytes(b"retained")
            journal["pairing"] = {
                "candidate": f"transactions/{SETUP_ID}/pairing.candidate",
                "sha256": "d" * 64,
            }
            store.update(journal)
            device = ResumePairDevice()
            producer = SetupProducer(config, store=store, device=device, artifact_validator=FakeArtifactValidator())
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                result = producer.handle(decode_request(json.dumps(request("resume")).encode()))
            self.assertEqual(result.stage, "install")
            self.assertEqual(result.outcome, "unknown")
            self.assertEqual(device.verify_calls, 1)
            self.assertEqual(device.pair_calls, 0)
            self.assertIsNotNone(store.read()["intent"]["artifact"])

    def test_v1_delivery_intent_is_one_time_even_after_unknown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = JournalStore(Path(directory))
            journal = store.create(SETUP_ID, DEVICE, {
                "source": "project", "artifactPath": None,
                "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            })
            calls = []

            def fail(_device: str, _setup: str) -> None:
                calls.append("attempt")
                raise RuntimeError("external ambiguity")

            with self.assertRaisesRegex(Exception, "transaction-unknown"):
                deliver_v1_once(store, journal, device_id=DEVICE, setup_id=SETUP_ID, deliver=fail)
            journal = store.read()
            self.assertEqual(journal["delivery"]["state"], "unknown")
            journal, delivered = deliver_v1_once(
                store,
                journal,
                device_id=DEVICE,
                setup_id=SETUP_ID,
                deliver=lambda *_args: calls.append("unexpected"),
            )
            self.assertFalse(delivered)
            self.assertEqual(calls, ["attempt"])


class FakeArtifactValidator:
    def inspect(self, _path: str, *, device_id: str, team_id: str) -> ArtifactIdentity:
        return ArtifactIdentity(
            str(_path),
            "com.neven.gofly",
            "GoFly",
            team_id,
            "a" * 64,
            "b" * 64,
            "c" * 64,
            "2030-01-01T00:00:00Z",
            {},
            "19",
        )


class UnknownInstallDevice:
    def __init__(self) -> None:
        self.install_calls = 0
        self.launch_calls = 0
        self.delivery_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def installed(self, device_id: str) -> InstalledAppObservation:
        # The app appears only after the controlled install boundary, which
        # then raises before a durable success result is returned.
        return InstalledAppObservation(self.install_calls > 0, "com.neven.gofly", "a" * 64, "b" * 64, "c" * 64)

    def pair(self, device_id: str, candidate: Path) -> PairingObservation:
        return PairingObservation("verified", device_id, "d" * 64)

    def verify_pairing(self, device_id: str, candidate: Path) -> PairingObservation:
        return PairingObservation("verified", device_id, "d" * 64)

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.install_calls += 1
        raise RuntimeError("controlled process death")

    def query_support(self, device_id: str, method: str) -> SupportObservation:
        return SupportObservation(True, method, "27.0", "generation", "com.apple.MobileAsset.DDI", "1")

    def install_support(self, device_id: str, method: str, restore_dir: Path) -> SupportObservation:
        raise AssertionError("support must not run after unknown install")

    def deliver_pairing(self, device_id: str, setup_id: str) -> None:
        self.delivery_calls += 1

    def launch(self, device_id: str) -> None:
        self.launch_calls += 1

    def stop(self, device_id: str) -> None:
        raise AssertionError("stop must not run after unknown install")

    def readback(self, device_id: str, setup_id: str, nonce: str) -> None:
        raise AssertionError("readback must not run after unknown install")


class ResumePairDevice:
    def __init__(self) -> None:
        self.verify_calls = 0
        self.pair_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def verify_pairing(self, device_id: str, candidate: Path) -> PairingObservation:
        self.verify_calls += 1
        return PairingObservation("verified", device_id, "d" * 64)

    def pair(self, device_id: str, candidate: Path) -> PairingObservation:
        self.pair_calls += 1
        raise AssertionError("resume must not run pair setup after unknown")


class ChangingBoundaryDevice:
    def __init__(self) -> None:
        self.boundary_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        self.boundary_calls += 1
        return DeviceObservation(device_id, "26.4.0", "USB", True, True)



class RenewDevice:
    def __init__(self, present: bool = True, fail_install: bool = False) -> None:
        self.present = present
        self.fail_install = fail_install
        self.install_calls = 0

    def observe(self, device_id: str) -> DeviceObservation:
        return DeviceObservation(device_id, "27.0", "USB", True, True)

    def installed(self, device_id: str) -> InstalledAppObservation:
        return InstalledAppObservation(self.present, "com.neven.gofly")

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.install_calls += 1
        if self.fail_install:
            raise RuntimeError("controlled process death")
        return InstalledAppObservation(True, "com.neven.gofly", build=artifact.build)

    def pair(self, *_args: object) -> PairingObservation:
        raise AssertionError("renew must not pair")

    def verify_pairing(self, *_args: object) -> PairingObservation:
        raise AssertionError("renew must not verify pairing")

    def deliver_pairing(self, *_args: object) -> None:
        raise AssertionError("renew must not deliver pairing")

    def launch(self, *_args: object) -> None:
        raise AssertionError("renew must not launch")

    def stop(self, *_args: object) -> None:
        raise AssertionError("renew must not stop")

    def readback(self, *_args: object) -> None:
        raise AssertionError("renew must not read back")

    def query_support(self, *_args: object) -> SupportObservation:
        raise AssertionError("renew must not query support")

    def install_support(self, *_args: object) -> SupportObservation:
        raise AssertionError("renew must not install support")


class RenewB1Tests(unittest.TestCase):
    def producer(self, directory: str, device: RenewDevice) -> SetupProducer:
        root = Path(directory)
        (root / "GoFly.app").mkdir(exist_ok=True)
        (root / "GoFly.xcodeproj").mkdir(exist_ok=True)
        (root / "Developer").mkdir(exist_ok=True)
        (root / "python").touch()
        config = SetupConfiguration(
            root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
            "com.neven.gofly", "GoFly", root / "state",
        )
        return SetupProducer(config, device=device, artifact_validator=FakeArtifactValidator())

    def options(self, root: Path) -> dict[str, object]:
        return {
            "source": "signedApp",
            "artifactPath": str(root / "GoFly.app"),
            "teamID": "ABCDEFGHIJ",
            "allowProvisioningUpdates": False,
        }

    def test_renew_preflight_rejects_a_missing_app(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            producer = self.producer(directory, RenewDevice(present=False))
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None):
                with self.assertRaisesRegex(SetupBridgeError, "app-not-installed"):
                    producer.handle(decode_request(json.dumps(request(
                        "preflight", mode="renew", options=self.options(root)
                    )).encode()))

    def test_renew_apply_installs_without_pairing_or_support(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = RenewDevice()
            producer = self.producer(directory, device)
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                result = producer.handle(decode_request(json.dumps(request(
                    "apply", mode="renew", options=self.options(root)
                )).encode()))
            self.assertEqual(result.stage, "complete")
            self.assertEqual(result.outcome, "confirmed")
            self.assertTrue(result.installation_confirmed)
            self.assertFalse(result.pairing_imported)
            self.assertFalse(result.support_observed)
            self.assertEqual(result.expires_at, "2030-01-01T00:00:00Z")
            journal = JournalStore(root / "state").read()
            self.assertEqual(set(journal["stages"]), {"artifact", "install", "complete"})
            for absent in ("pairing", "support", "handoff"):
                self.assertNotIn(absent, journal["stages"])
            self.assertEqual(device.install_calls, 1)

    def test_renew_unknown_install_resume_does_not_resubmit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = RenewDevice(fail_install=True)
            producer = self.producer(directory, device)
            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact):
                with self.assertRaises(SetupBridgeError):
                    producer.handle(decode_request(json.dumps(request(
                        "apply", mode="renew", options=self.options(root)
                    )).encode()))
                self.assertEqual(device.install_calls, 1)
                result = producer.handle(decode_request(json.dumps(request("resume", mode="renew")).encode()))
            self.assertEqual(result.outcome, "unknown")
            self.assertEqual(result.stage, "install")
            self.assertEqual(device.install_calls, 1)

    def test_install_mode_still_rejects_an_existing_app(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            producer = self.producer(directory, RenewDevice(present=True))
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None):
                with self.assertRaisesRegex(SetupBridgeError, "app-already-installed"):
                    producer.handle(decode_request(json.dumps(request(
                        "preflight", mode="install", options=self.options(root)
                    )).encode()))


class StdioB1Tests(unittest.TestCase):
    def test_process_group_owns_controlled_child_tree_for_cancel(self) -> None:
        bridge = Path(__file__).resolve().parents[1] / "setup_bridge.py"
        script = (
            "import os, subprocess, sys, time, runpy; "
            f"m=runpy.run_path({str(bridge)!r}); m['establish_process_group'](); "
            "child=subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)']); "
            "print(f'{os.getpid()} {child.pid}', flush=True); time.sleep(30)"
        )
        process = subprocess.Popen(
            [sys.executable, "-I", "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        grandchild_pid: int | None = None
        try:
            line = process.stdout.readline() if process.stdout is not None else ""
            parent_pid, grandchild_text = line.strip().split()
            self.assertEqual(int(parent_pid), process.pid)
            grandchild_pid = int(grandchild_text)
            os.kill(-process.pid, signal.SIGTERM)
            process.wait(timeout=5)
            time.sleep(0.1)
            with self.assertRaises(ProcessLookupError):
                os.kill(grandchild_pid, 0)
        finally:
            if process.poll() is None:
                os.kill(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
            if grandchild_pid is not None:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(grandchild_pid, signal.SIGKILL)
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()

    def test_invalid_request_has_bounded_protocol2_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "SetupConfiguration.json"
            response = run_stdio(missing, stdin=io.BytesIO(b"{}"))
            self.assertEqual(response["protocol"], 2)
            self.assertEqual(response["status"], "error")
            self.assertEqual(response["code"], "invalid-request")

    def test_status_does_not_create_state_or_lock(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "state"
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            (root / "Developer").mkdir()
            config = root / "SetupConfiguration.json"
            config.write_text(json.dumps({
                "workspaceRoot": str(root),
                "pythonPath": str(root / "python"),
                "developerDirectory": str(root / "Developer"),
                "projectPath": str(project),
                "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly",
                "stateRoot": str(state),
            }))
            response = run_stdio(config, stdin=io.BytesIO(json.dumps(request("status")).encode()))
            self.assertEqual(response["code"], "configuration-invalid")
            self.assertFalse(state.exists())

    def test_runtime_error_keeps_safe_unknown_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "GoFly.xcodeproj"
            project.mkdir()
            (root / "Developer").mkdir()
            config = root / "SetupConfiguration.json"
            config.write_text(json.dumps({
                "workspaceRoot": str(root),
                "pythonPath": str(root / "python"),
                "developerDirectory": str(root / "Developer"),
                "projectPath": str(project),
                "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly",
                "stateRoot": str(root / "state"),
            }))
            value = request("status")
            response = run_stdio(config, stdin=io.BytesIO(json.dumps(value).encode()))
            self.assertEqual(response["status"], "error")
            self.assertEqual(response["payload"]["outcome"], "unknown")
            self.assertEqual(response["payload"]["stage"], "preflight")

    def test_bridge_error_payload_reads_durable_stage_and_proof(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "SetupConfiguration.json"
            config.write_text(json.dumps({
                "workspaceRoot": str(root),
                "pythonPath": str(root / "python"),
                "developerDirectory": str(root / "Developer"),
                "projectPath": str(root / "GoFly.xcodeproj"),
                "targetBundleID": "com.neven.gofly",
                "targetName": "GoFly",
                "stateRoot": str(root / "state"),
            }))
            (root / "Developer").mkdir()
            (root / "GoFly.xcodeproj").mkdir()

            def failing_factory(loaded: SetupConfiguration) -> SetupProducer:
                store = JournalStore(loaded.state_root)
                journal = store.create(SETUP_ID, DEVICE, {
                    "source": "project", "artifactPath": None,
                    "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False,
                    "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
                })
                journal["stages"]["artifact"] = {"state": "confirmed"}
                journal["stages"]["pairing"] = {"state": "confirmed"}
                journal["stages"]["install"] = {"state": "inflight"}
                store.update(journal)
                raise SetupBridgeError("operation-failed")

            response = run_stdio(config, stdin=io.BytesIO(json.dumps(request("status")).encode()), producer_factory=failing_factory)
            self.assertEqual(response["code"], "configuration-invalid")


if __name__ == "__main__":
    unittest.main()
