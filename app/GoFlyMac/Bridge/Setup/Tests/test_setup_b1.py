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
from unittest.mock import AsyncMock
from types import SimpleNamespace
from pathlib import Path
import importlib.util

import sys

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(PACKAGE_ROOT))

from bridge import run_stdio as bridge_run_stdio, _setup_error_payload as _error_payload  # noqa: E402
from setup_protocol import SetupBridgeError, decode_request, encode_response  # noqa: E402
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
        "requestID": REQUEST_ID,
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
            self.assertEqual(result.stage, "complete", result.as_dict())
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



class AdapterBoundaryTests(unittest.TestCase):
    """The two single-point regressions kept from the deleted USB/process files."""

    serial = "00000000-000000000000ABCD"

    def tearDown(self) -> None:
        close_async_runtime()

    def test_normalized_identity_opens_exact_usb_serial_without_autopair(self) -> None:
        client = SimpleNamespace(get_value=AsyncMock(return_value={"UniqueDeviceID": self.serial}), close=AsyncMock())
        create = AsyncMock(return_value=client)
        adapter = PinnedPymobiledeviceAdapter()
        adapter._modules = (
            SimpleNamespace(list_devices=AsyncMock(return_value=[SimpleNamespace(serial=self.serial, connection_type="USB")])),
            SimpleNamespace(create_using_usbmux=create),
            SimpleNamespace(),
        )
        with tempfile.TemporaryDirectory() as directory:
            self.assertIs(adapter._open(self.serial.lower(), Path(directory)), client)
        self.assertEqual(create.call_args.kwargs["serial"], self.serial)
        self.assertIs(create.call_args.kwargs["autopair"], False)
        self.assertEqual(create.call_args.kwargs["connection_type"], "USB")

    def test_launch_uses_verified_rsd_and_never_kills_existing(self) -> None:
        device = "00000000-000000000000abcd"
        adapter = PinnedPymobiledeviceAdapter()

        def serial(value: str) -> str:
            self.assertEqual(value, device)
            with self.assertRaises(RuntimeError):
                asyncio.get_running_loop()
            return device.upper()

        adapter.transport_serial = serial
        rsd = SimpleNamespace(udid=device, product_version="27.0.1")
        tunnel = SimpleNamespace(aopen=mock.AsyncMock(return_value=rsd), aclose=mock.AsyncMock())
        control = mock.MagicMock()
        control.__aenter__ = mock.AsyncMock(return_value=control)
        control.__aexit__ = mock.AsyncMock(return_value=False)
        control.process_identifier_for_bundle_identifier = mock.AsyncMock(return_value=0)
        control.launch = mock.AsyncMock(return_value=123)
        provider = mock.MagicMock()
        provider.__aenter__ = mock.AsyncMock(return_value=provider)
        provider.__aexit__ = mock.AsyncMock(return_value=False)
        modules = {
            "pymobiledevice3.remote.userspace_tunnel": SimpleNamespace(UserspaceRsdTunnel=mock.Mock(return_value=tunnel)),
            "pymobiledevice3.services.dvt.instruments.process_control": SimpleNamespace(ProcessControl=mock.Mock(return_value=control)),
            "pymobiledevice3.services.dvt.instruments.dvt_provider": SimpleNamespace(DvtProvider=mock.Mock(return_value=provider)),
        }
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            self.assertEqual(adapter.launch(device), 123)
        control.launch.assert_awaited_once_with("com.neven.gofly", kill_existing=False)
        tunnel.aclose.assert_awaited_once()

    @unittest.skipUnless(
        all(importlib.util.find_spec(name) is not None for name in ("pymobiledevice3", "cryptography")),
        "pymobiledevice3／cryptography 未安裝，跳過裝置依賴測試",
    )
    def test_pinned_device_dependencies_are_available(self) -> None:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from pymobiledevice3.services.cryptexd import load_cryptex1_assets
        self.assertTrue(callable(load_cryptex1_assets))
        self.assertTrue(callable(Ed25519PrivateKey.generate))


class InstallDevice(RenewDevice):
    def __init__(self) -> None:
        super().__init__(present=False)
        self.installed_present = False

    def installed(self, device_id: str) -> InstalledAppObservation:
        return InstalledAppObservation(self.installed_present, "com.neven.gofly")

    def prepare_pairing(self, _device_id: str, candidate: Path) -> None:
        candidate.write_bytes(b"pairing")

    def pair(self, _device_id: str, _candidate: Path) -> PairingObservation:
        return PairingObservation("verified", "com.neven.gofly", "a" * 64)

    def verify_pairing(self, _device_id: str, _candidate: Path) -> PairingObservation:
        return PairingObservation("verified", "com.neven.gofly", "a" * 64)

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstalledAppObservation:
        self.installed_present = True
        return InstalledAppObservation(True, "com.neven.gofly", build=artifact.build)


class InstallApplyTests(unittest.TestCase):
    def test_install_apply_reaches_complete_with_the_full_stage_list(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "GoFly.app").mkdir()
            (root / "GoFly.xcodeproj").mkdir()
            (root / "Developer").mkdir()
            (root / "python").touch()
            config = SetupConfiguration(root, root / "python", root / "Developer", root / "GoFly.xcodeproj",
                                        "com.neven.gofly", "GoFly", root / "state")
            producer = SetupProducer(config, device=InstallDevice(), artifact_validator=FakeArtifactValidator())
            options = {"source": "signedApp", "artifactPath": str(root / "GoFly.app"),
                       "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False}
            def fake_handoff(journal, *_args, **_kwargs):
                journal = producer.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
                return producer.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})

            with mock.patch("setup_producer.snapshot_artifact", side_effect=lambda artifact, *_a, **_k: artifact), \
                 mock.patch.object(SetupProducer, "_handoff", side_effect=fake_handoff):
                result = producer.handle(decode_request(json.dumps(request("apply", mode="install", options=options)).encode()))
            self.assertEqual(result.stage, "complete", result.as_dict())
            self.assertEqual(result.outcome, "confirmed")
            self.assertTrue(result.installation_confirmed and result.pairing_imported and result.support_observed)
            journal = JournalStore(root / "state").read()
            self.assertEqual(set(journal["stages"]), {"artifact", "pairing", "install", "support", "handoff", "complete"})

class StdioB1Tests(unittest.TestCase):
    def test_process_group_owns_controlled_child_tree_for_cancel(self) -> None:
        bridge = Path(__file__).resolve().parents[2] / "bridge.py"
        script = (
            "import os, subprocess, sys, time; "
            f"sys.path.insert(0, {str(bridge.parent)!r}); import bridge; bridge.establish_process_group(); "
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
            response = bridge_run_stdio(missing, stdin=io.BytesIO(b"{}"))
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
            response = bridge_run_stdio(config, stdin=io.BytesIO(json.dumps(request("status")).encode()))
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
            response = bridge_run_stdio(config, stdin=io.BytesIO(json.dumps(value).encode()))
            self.assertEqual(response["status"], "error")
            self.assertEqual(response["payload"]["outcome"], "unknown")
            self.assertEqual(response["payload"]["stage"], "preflight")

if __name__ == "__main__":
    unittest.main()
