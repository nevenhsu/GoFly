from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(PACKAGE_ROOT))

from setup_adapters import (  # noqa: E402
    ActivationReceiptObservation,
    ArtifactIdentity,
    DeviceObservation,
    InstalledAppObservation,
    PairingObservation,
    snapshot_artifact,
)
from setup_config import SetupConfiguration  # noqa: E402
from setup_journal import JournalStore  # noqa: E402
from setup_producer import SetupProducer  # noqa: E402
from setup_protocol import SetupBridgeError, bundle_id_for_team, decode_request  # noqa: E402


DEVICE = "0123456789abcdef0123456789abcdef01234567"
TEAM_ID = "ABCDEFGHIJ"
BUNDLE_ID = bundle_id_for_team(TEAM_ID)
PAIRING_BYTES = b"verified existing Wi-Fi pairing"
PAIRING_SHA256 = hashlib.sha256(PAIRING_BYTES).hexdigest()


def _seal(journal: dict[str, object]) -> None:
    journal.pop("receiptSHA256", None)
    journal["receiptSHA256"] = hashlib.sha256(
        json.dumps(journal, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def seed_completed_usb_transaction(store: JournalStore) -> tuple[str, str]:
    """Create a private, eligible source journal and retained candidate."""
    setup_id = str(uuid.uuid4())
    transaction = store.transaction_root(setup_id)
    app_path = transaction / "artifact" / "GoFly.app"
    app_path.mkdir(parents=True)
    candidate = transaction / "pairing.candidate"
    candidate.write_bytes(PAIRING_BYTES)
    candidate.chmod(0o600)
    artifact = {
        "path": str(app_path),
        "bundleID": BUNDLE_ID,
        "executable": "GoFly",
        "teamID": TEAM_ID,
        "artifactSHA256": "a" * 64,
        "executableSHA256": "b" * 64,
        "profileSHA256": "c" * 64,
        "expiresAt": "2030-01-01T00:00:00Z",
        "build": "19",
    }
    journal = store.create(
        setup_id,
        DEVICE,
        {
            "teamID": TEAM_ID,
            "allowProvisioningUpdates": False,
            "targetBundleID": BUNDLE_ID,
            "targetName": "GoFly",
            "fullSetup": True,
            "deviceObservation": {
                "deviceID": DEVICE,
                "osVersion": "27.0",
                "transport": "USB",
                "developerMode": True,
                "trust": True,
            },
        },
        mode="renew",
    )
    journal["intent"]["artifact"] = artifact
    journal["stages"] = {name: {"state": "confirmed"} for name in journal["stages"]}
    journal["proof"] = {
        "installationConfirmed": True,
        "pairingImported": True,
        "supportObserved": True,
    }
    journal["delivery"] = {"state": "delivered"}
    journal["pairing"] = {
        "candidate": f"transactions/{setup_id}/pairing.candidate",
        "sha256": PAIRING_SHA256,
    }
    journal["installOwnership"] = {
        "transactionID": setup_id,
        "bundleID": BUNDLE_ID,
        "build": "19",
        "artifactSHA256": "a" * 64,
        "executableSHA256": "b" * 64,
        "profileSHA256": "c" * 64,
    }
    journal["support"] = {
        "method": "cryptex",
        "osVersion": "27.0",
        "generationID": setup_id,
        "identifier": "com.apple.MobileAsset.DDI",
        "version": "1",
    }
    nonce = str(uuid.uuid4()).upper()
    raw_manifest = "{}"
    manifest_sha256 = hashlib.sha256(raw_manifest.encode()).hexdigest()
    formal = [{
        "id": str(uuid.uuid4()),
        "filename": "MountMethod",
        "byteCount": 1,
        "sha256": "d" * 64,
    }]
    journal["handoff"] = {
        "nonce": nonce,
        "setupID": setup_id,
        "formalPublished": True,
        "rawManifest": raw_manifest,
        "manifestSHA256": manifest_sha256,
        "formalArtifacts": formal,
    }
    journal["activationReceipt"] = {
        "setupID": setup_id,
        "nonce": nonce,
        "deviceID": DEVICE,
        "rawManifestSHA256": manifest_sha256,
        "pairingTransactionID": journal["intent"]["pairingTransactionID"],
        "pairingSHA256": PAIRING_SHA256,
        "bundleID": BUNDLE_ID,
        "build": "19",
        "profileSHA256": "c" * 64,
        "executableSHA256": "b" * 64,
        "teamID": TEAM_ID,
        "signingExpiry": artifact["expiresAt"],
        "deviceOS": "27.0",
        "method": "cryptex",
        "generationID": setup_id,
        "artifacts": formal,
    }
    _seal(journal)
    store.update(journal)
    if not store._completed_eligible(journal):
        raise AssertionError("seeded USB transaction must be eligible for Wi-Fi renewal")
    return setup_id, str(journal["intent"]["pairingTransactionID"])


class FakeArtifactValidator:
    def inspect(self, path, *, device_id, team_id, target_bundle_id=None):
        return ArtifactIdentity(
            str(path), target_bundle_id or BUNDLE_ID, "GoFly", team_id,
            "a" * 64, "b" * 64, "c" * 64,
            "2030-01-01T00:00:00Z", {}, "20",
        )


class FakeProcess:
    def __init__(self, state_root: Path):
        self.state_root = state_root

    def build(self, setup_id: str, *_args, **_kwargs) -> Path:
        app = self.state_root / "transactions" / setup_id / "build" / "GoFly.app"
        app.mkdir(parents=True, exist_ok=True)
        return app


class WifiDevice:
    def __init__(self, *, observe_error: str | None = None, pairing_ok: bool = True,
                 fail_install: bool = False, fail_receipt: bool = False):
        self.observe_error = observe_error
        self.pairing_ok = pairing_ok
        self.fail_install = fail_install
        self.fail_receipt = fail_receipt
        self.verify_calls = 0
        self.install_calls = 0
        self.pair_calls = 0
        self.prepare_pairing_calls = 0
        self.delivery_calls = 0
        self.plan = None
        self.producer = None

    def observe(self, device_id: str, *, transport: str = "usb") -> DeviceObservation:
        if self.observe_error:
            raise SetupBridgeError(self.observe_error)
        if transport != "wifi":
            raise AssertionError(f"expected wifi observation, got {transport}")
        return DeviceObservation(device_id, "27.0", "Network", True, True)

    def installed(self, _device_id: str, *, transport: str = "usb") -> InstalledAppObservation:
        if transport != "wifi":
            raise AssertionError(f"expected wifi install query, got {transport}")
        return InstalledAppObservation(True, BUNDLE_ID, build="19")

    def verify_pairing(self, device_id: str, candidate: Path, *, transport: str = "usb") -> PairingObservation:
        self.verify_calls += 1
        if transport != "wifi":
            raise AssertionError(f"expected wifi pairing verification, got {transport}")
        if not self.pairing_ok:
            return PairingObservation("unknown", device_id, None)
        return PairingObservation("verified", device_id, hashlib.sha256(candidate.read_bytes()).hexdigest())

    def prepare_pairing(self, *_args, **_kwargs):
        self.prepare_pairing_calls += 1
        raise AssertionError("Wi-Fi renewal must never create a new pairing")

    def pair(self, *_args, **_kwargs):
        self.pair_calls += 1
        raise AssertionError("Wi-Fi renewal must never pair")

    def deliver_pairing(self, *_args, **_kwargs):
        self.delivery_calls += 1
        raise AssertionError("Wi-Fi renewal must never deliver a pairing file")

    def install(self, _device_id: str, artifact: ArtifactIdentity, *, transport: str = "usb") -> InstalledAppObservation:
        self.install_calls += 1
        if transport != "wifi":
            raise AssertionError(f"expected Wi-Fi install, got {transport}")
        if self.fail_install:
            raise SetupBridgeError("device-disconnected")
        return InstalledAppObservation(True, artifact.bundle_id, build=artifact.build)

    def prepare_setup_input(self, _device_id, _setup_id, _nonce, _artifact, _pairing_tx, _pairing_sha,
                            _support, *, plan, transport="usb"):
        if transport != "wifi":
            raise AssertionError(f"expected Wi-Fi handoff, got {transport}")
        self.plan = plan
        return plan.sha256

    def formal_inventory(self, _setup_id, _nonce):
        return self.plan.artifacts

    def launch(self, _device_id, *, transport="usb"):
        if transport != "wifi":
            raise AssertionError(f"expected Wi-Fi launch, got {transport}")
        return 42

    def read_activation_receipt(self, _device_id, _setup_id, _nonce, *, transport="usb"):
        if transport != "wifi":
            raise AssertionError(f"expected Wi-Fi receipt read, got {transport}")
        if self.fail_receipt:
            raise SetupBridgeError("handoff-unknown")
        journal = self.producer.store.read()
        intent = journal["intent"]
        artifact = intent["artifact"]
        support = journal["support"]
        handoff = journal["handoff"]
        artifacts = tuple((item[0], item[2], item[3]) for item in self.plan.artifacts)
        records = self.plan.artifacts
        return ActivationReceiptObservation(
            journal["setupID"], handoff["nonce"], journal["deviceID"], self.plan.sha256,
            intent["pairingTransactionID"], journal["pairing"]["sha256"], artifact["bundleID"],
            artifact["build"], artifact["profileSHA256"], artifact["executableSHA256"],
            artifact["teamID"], artifact["expiresAt"], support["osVersion"], support["method"],
            support["generationID"], artifacts, records,
        )

    def stop(self, _device_id, _pid, *, transport="usb"):
        if transport != "wifi":
            raise AssertionError(f"expected Wi-Fi stop, got {transport}")


class WifiRenewTests(unittest.TestCase):
    def make_producer(self, root: Path, device: WifiDevice) -> SetupProducer:
        (root / "GoFly.xcodeproj").mkdir(exist_ok=True)
        (root / "Developer").mkdir(exist_ok=True)
        (root / "python").touch()
        config = SetupConfiguration(
            root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
            BUNDLE_ID, "GoFly", root / "state",
        )
        producer = SetupProducer(
            config, device=device, process=FakeProcess(root / "state"),
            artifact_validator=FakeArtifactValidator(),
        )
        device.producer = producer
        return producer

    @staticmethod
    def options() -> dict[str, object]:
        return {"teamID": TEAM_ID, "allowProvisioningUpdates": False}

    @staticmethod
    def support_for(setup_id: str) -> dict[str, object]:
        files = {
            label: [1, hashlib.sha256(label.encode()).hexdigest()]
            for label in ("MountMethod", "manifest", "image", "trustcache", "cryptex_info", "root_hash")
        }
        return {
            "method": "cryptex", "osVersion": "27.0", "generationID": setup_id,
            "identifier": "com.apple.MobileAsset.DDI", "version": "1",
            "inputFiles": files, "inputManifestSHA256": files["manifest"][1],
        }

    def test_wifi_success_reuses_pairing_and_reads_exact_activation_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = WifiDevice()
            producer = self.make_producer(root, device)
            source_setup_id, source_pairing_tx = seed_completed_usb_transaction(producer.store)
            request = decode_request(json.dumps({
                "requestID": str(uuid.uuid4()), "action": "apply", "setupID": str(uuid.uuid4()),
                "deviceID": DEVICE, "mode": "renew", "transport": "wifi", "options": self.options(),
            }).encode())

            def confirm_support(journal, _request, _observed, *, expected=None):
                return producer.store.checkpoint(
                    journal, "support", "confirmed", proof={"supportObserved": True}
                )

            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None), \
                 mock.patch.object(producer, "_prepare_local_support", side_effect=lambda journal, req, _obs: self.support_for(req.setup_id)), \
                 mock.patch.object(producer, "_support", side_effect=confirm_support):
                result = producer.handle(request)

            journal = producer.store.read()
            self.assertEqual(result.stage, "complete")
            self.assertEqual(result.outcome, "confirmed")
            self.assertTrue(all((result.installation_confirmed, result.pairing_imported, result.support_observed)))
            self.assertTrue(producer.store._completed_eligible(journal))
            self.assertIs(journal["intent"]["wifiRenew"], True)
            self.assertEqual(journal["delivery"]["state"], "notStarted")
            self.assertEqual(journal["intent"]["pairingSourceSetupID"], source_setup_id)
            self.assertEqual(journal["intent"]["pairingTransactionID"], source_pairing_tx)
            self.assertEqual(journal["pairing"]["candidate"], f"transactions/{source_setup_id}/pairing.candidate")
            self.assertEqual(device.verify_calls, 2)
            self.assertEqual(device.install_calls, 1)
            self.assertEqual(device.prepare_pairing_calls, 0)
            self.assertEqual(device.pair_calls, 0)
            self.assertEqual(device.delivery_calls, 0)
            self.assertEqual(journal["activationReceipt"]["pairingTransactionID"], source_pairing_tx)

    def test_preflight_without_network_device_has_stable_wifi_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = WifiDevice(observe_error="device-disconnected")
            producer = self.make_producer(root, device)
            request = decode_request(json.dumps({
                "requestID": str(uuid.uuid4()), "action": "preflight", "setupID": str(uuid.uuid4()),
                "deviceID": DEVICE, "mode": "renew", "transport": "wifi", "options": self.options(),
            }).encode())
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None), \
                 self.assertRaisesRegex(SetupBridgeError, "wifi-device-not-found"):
                producer.handle(request)
            self.assertEqual(device.install_calls, 0)
            self.assertEqual(device.verify_calls, 0)

    def test_existing_pairing_verification_failure_never_installs_or_regenerates_pairing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = WifiDevice(pairing_ok=False)
            producer = self.make_producer(root, device)
            seed_completed_usb_transaction(producer.store)
            request = decode_request(json.dumps({
                "requestID": str(uuid.uuid4()), "action": "preflight", "setupID": str(uuid.uuid4()),
                "deviceID": DEVICE, "mode": "renew", "transport": "wifi", "options": self.options(),
            }).encode())
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None), \
                 self.assertRaisesRegex(SetupBridgeError, "wifi-pairing-unknown"):
                producer.handle(request)
            self.assertEqual(device.verify_calls, 1)
            self.assertEqual(device.install_calls, 0)
            self.assertEqual(device.prepare_pairing_calls, 0)
            self.assertEqual(device.pair_calls, 0)
            self.assertEqual(device.delivery_calls, 0)

    def test_disconnect_at_install_becomes_unknown_without_pairing_fallback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = WifiDevice(fail_install=True)
            producer = self.make_producer(root, device)
            seed_completed_usb_transaction(producer.store)
            request = decode_request(json.dumps({
                "requestID": str(uuid.uuid4()), "action": "apply", "setupID": str(uuid.uuid4()),
                "deviceID": DEVICE, "mode": "renew", "transport": "wifi", "options": self.options(),
            }).encode())
            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None), \
                 self.assertRaisesRegex(SetupBridgeError, "wifi-device-not-found"):
                producer.handle(request)
            journal = producer.store.read()
            self.assertEqual(journal["intent"]["transport"], "wifi")
            self.assertEqual(journal["stages"]["install"]["state"], "unknown")
            self.assertEqual(device.install_calls, 1)
            self.assertEqual(device.prepare_pairing_calls, 0)
            self.assertEqual(device.pair_calls, 0)
            self.assertEqual(device.delivery_calls, 0)

    def test_activation_receipt_failure_has_a_stable_wifi_code(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = WifiDevice(fail_receipt=True)
            producer = self.make_producer(root, device)
            seed_completed_usb_transaction(producer.store)
            request = decode_request(json.dumps({
                "requestID": str(uuid.uuid4()), "action": "apply", "setupID": str(uuid.uuid4()),
                "deviceID": DEVICE, "mode": "renew", "transport": "wifi", "options": self.options(),
            }).encode())

            def confirm_support(journal, _request, _observed, *, expected=None):
                return producer.store.checkpoint(
                    journal, "support", "confirmed", proof={"supportObserved": True}
                )

            with mock.patch.object(SetupConfiguration, "validate_read_only_paths", return_value=None), \
                 mock.patch.object(producer, "_prepare_local_support", side_effect=lambda journal, req, _obs: self.support_for(req.setup_id)), \
                 mock.patch.object(producer, "_support", side_effect=confirm_support), \
                 self.assertRaisesRegex(SetupBridgeError, "wifi-renew-unknown"):
                producer.handle(request)
            journal = producer.store.read()
            self.assertEqual(journal["stages"]["handoff"]["state"], "unknown")
            self.assertEqual(journal["stages"]["complete"]["state"], "pending")
            self.assertEqual(device.prepare_pairing_calls, 0)
            self.assertEqual(device.pair_calls, 0)
            self.assertEqual(device.delivery_calls, 0)


if __name__ == "__main__":
    unittest.main()
