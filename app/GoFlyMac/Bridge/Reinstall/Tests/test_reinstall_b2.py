from __future__ import annotations

import tempfile
import unittest
import uuid
import plistlib
import shutil
import hashlib
import json
import copy
import dataclasses
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
import sys
sys.path.append(str(PACKAGE_ROOT))

from Reinstall.reinstall_adapters import ExportReadback, InstallObservation, SourceAppIdentity  # noqa: E402
from Reinstall.reinstall_journal import ReinstallJournalStore, is_completed_journal  # noqa: E402
from Reinstall.reinstall_producer import ReinstallProducer  # noqa: E402
from Reinstall.reinstall_protocol import ReinstallBridgeError, ReinstallOptions, ReinstallRequest  # noqa: E402
from Setup.setup_adapters import (  # noqa: E402
    ActivationReceiptObservation,
    ArtifactIdentity,
    DeviceObservation,
    InstalledAppObservation,
    PairingObservation,
    ReadbackObservation,
    SupportObservation,
)
from Setup.setup_protocol import SetupBridgeError  # noqa: E402


DEVICE = "01234567-89abcdef01234567"


class Config:
    def __init__(self, state_root: Path, validator_path: Path):
        self.state_root = state_root
        self.validator_path = validator_path

    def validate_read_only_paths(self):
        return None

    def ensure_state_root(self):
        self.state_root.mkdir(parents=True, exist_ok=True)
        self.state_root.chmod(0o700)
        return self.state_root


class ArtifactValidator:
    def __init__(self, artifact: ArtifactIdentity):
        self.artifact = artifact

    def inspect(self, *_args, **_kwargs):
        return self.artifact


class Validator:
    def __init__(self, *, fail=False, device=None):
        self.fail = fail
        self.device = device

    def validate(self, _backup: Path):
        if self.fail:
            raise ReinstallBridgeError("backup-invalid")
        return {
            "version": 1,
            "transferID": self.device.transfer_id,
            "dataSetID": self.device.data_set_id,
            "nonce": self.device.nonce,
            "sourceDeviceUDID": DEVICE,
            "destinationDeviceUDID": DEVICE,
            "sourceApp": {"bundleID": "com.neven.gofly", "build": "19", "profileSHA256": "b" * 64, "executableSHA256": "c" * 64},
            "targetApp": {"bundleID": "com.neven.gofly", "build": "20", "profileSHA256": "3" * 64, "executableSHA256": "2" * 64},
            "setupID": self.device.setup_id,
            "categories": ["favorites"],
            "rawManifestSHA256": "a" * 64,
            "counts": {"favorites": 1, "importedRoutes": 0, "favoriteRoutes": 0, "draftNodes": 0, "gpxPoints": 0},
        }


class Device:
    def __init__(self, package: Path):
        self.package = package
        self.uninstalled = False
        self.installed_target = False
        self.uninstall_calls = 0
        self.calls = []
        self.copy_calls = []
        self.restore_intent = None

    def observe(self, device_id):
        return DeviceObservation(device_id, "26.3", "USB", True, True)

    def installed(self, _device_id):
        if self.installed_target:
            return InstalledAppObservation(True, build="20")
        if self.uninstalled:
            return InstalledAppObservation(False)
        return InstalledAppObservation(True, build="19")

    def source_request(self, *_args):
        request, control = _args[-2:]
        self.transfer_id = request["transferID"]
        self.data_set_id = request["dataSetID"]
        self.nonce = request["nonce"]
        self.setup_id = request["setupID"]
        self.control = dict(control)
        self.phase = "ready"

    def source_readback(self, _device_id, transfer_id, nonce):
        return ExportReadback(
            phase=self.phase,
            transfer_id=transfer_id,
            data_set_id=self.data_set_id,
            nonce=nonce,
            raw_manifest_sha256="a" * 64 if self.phase != "releasedNoSnapshot" else None,
            source_app=SourceAppIdentity("com.neven.gofly", "19", "b" * 64, "c" * 64),
            command_id=self.control["commandID"],
            action=self.control["action"],
            request_sha256=self.control["requestSHA256"],
            pid=1234,
            error_code="export-conflict" if self.phase == "ready" and self.control["action"] == "release" else None,
        )

    def copy_source_package(self, _device_id, _transfer_id, destination):
        self.copy_calls.append(destination)
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.package, destination, dirs_exist_ok=True)

    def source_seal(self, _device_id, control):
        self.control = dict(control)
        self.phase = "removalSealed"

    def source_release(self, _device_id, control):
        self.control = dict(control)
        self.phase = "released"

    def source_pid(self, *_args):
        return 0

    def stop_source(self, *_args):
        raise AssertionError("source is already absent")

    def uninstall(self, *_args):
        self.uninstall_calls += 1
        self.uninstalled = True

    def install(self, *_args):
        self.installed_target = True
        return InstallObservation("confirmed")

    def publish_restore_intent(self, _device_id, intent):
        self.calls.append("publish_restore_intent")
        self.restore_intent = dict(intent)
        return None

    def deliver_restore(self, *_args):
        self.calls.append("deliver_restore")
        return None

    def restore_readback(self, _device_id, _transfer_id):
        counts = {"favorites": 1, "importedRoutes": 0, "favoriteRoutes": 0, "draftNodes": 0, "gpxPoints": 0}
        receipt = {
            "version": 1,
            "intent": self.restore_intent,
            "categoryReceipts": [{"category": "favorites", "receiptSHA256": "f" * 64}],
            "sessionSeedSHA256": "e" * 64,
            "counts": counts,
        }
        receipt["receiptSHA256"] = hashlib.sha256(json.dumps(receipt, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
        return {
            "phase": "committed",
            "categories": [{"category": "favorites", "state": "committed", "receiptSHA256": "f" * 64}],
            "counts": counts,
            "intent": self.restore_intent,
            "receipt": receipt,
        }

    # The producer now reuses the private M1 stages through actual adapter
    # seams.  These methods are deliberately protocol-shaped fakes rather
    # than a positive support/pairing callback.
    def prepare_pairing(self, _device_id, candidate):
        candidate.parent.mkdir(parents=True, exist_ok=True)
        candidate.write_bytes(b"pairing")

    def pair(self, device_id, candidate):
        self.calls.append("pair")
        return PairingObservation("verified", device_id, "d" * 64)

    def verify_pairing(self, device_id, candidate):
        self.calls.append("verify_pairing")
        return PairingObservation("verified", device_id, "d" * 64)

    def prepare_readback(self, *_args):
        self.calls.append("prepare_readback")

    def launch(self, _device_id):
        self.calls.append("launch")
        return 1234

    def readback(self, _device_id, setup_id, nonce):
        self.calls.append("readback")
        return ReadbackObservation(nonce, setup_id, DEVICE, "1" * 64, "2" * 64, "3" * 64, "d" * 64, "personalized", setup_id, "20")

    def stop(self, _device_id, _pid=None):
        self.calls.append("stop")

    def prepare_generation(self, _method, restore_dir):
        self.calls.append("prepare_generation")
        restore_dir.mkdir(parents=True, exist_ok=True)
        (restore_dir / "MountMethod").write_bytes(b"personalized")
        (restore_dir / "BuildManifest.plist").write_bytes(plistlib.dumps({}))
        (restore_dir / "Image.dmg").write_bytes(b"image")
        (restore_dir / "Image.dmg.trustcache").write_bytes(b"trust")
        for path in restore_dir.iterdir():
            path.chmod(0o600)
        restore_dir.chmod(0o700)

    def query_support(self, _device, method):
        self.calls.append("query_support")
        return SupportObservation(True, method, "26.3", self.setup_id, "com.apple.MobileAsset.DDI", "1")

    def support(self, _device_id):
        self.calls.append("support")
        return {
            "observed": True,
            "method": "personalized",
            "osVersion": "26.3",
            "generationID": self.setup_id,
            "identifier": "com.apple.MobileAsset.DDI",
            "version": "1",
        }

    def install_support(self, *_args):
        raise AssertionError("query should prove support in this controlled flow")

    def deliver_pairing(self, *_args):
        self.calls.append("deliver_pairing")

    def prepare_setup_input(self, _device, _setup, _nonce, _artifact, pairing_transaction_id, _pairing_sha, _support, *, plan):
        self.calls.append("prepare_setup_input")
        self.plan = plan
        self.pairing_transaction_id = pairing_transaction_id
        return plan.sha256

    def formal_inventory(self, _setup, _nonce):
        return self.plan.artifacts

    def read_activation_receipt(self, _device, setup_id, nonce):
        self.calls.append("activation")
        return ActivationReceiptObservation(
            setup_id, nonce, DEVICE, self.plan.sha256, self.pairing_transaction_id, "d" * 64,
            "com.neven.gofly", "20", "3" * 64, "2" * 64, "ABCDEFGHIJ",
            "2030-01-01T00:00:00Z", "26.3", "personalized", setup_id,
            tuple((item[0], item[2], item[3]) for item in self.plan.artifacts),
            self.plan.artifacts,
        )


def request(transfer_id: str, options: ReinstallOptions) -> ReinstallRequest:
    return ReinstallRequest(str(uuid.uuid4()), "apply", transfer_id, DEVICE, options)


class ReinstallB2Tests(unittest.TestCase):
    def test_journal_has_frozen_header_and_same_operation_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            store = ReinstallJournalStore(Path(directory) / "state")
            with store.lock():
                transfer = str(uuid.uuid4())
                store.create(transfer, DEVICE, data_set_id=str(uuid.uuid4()), nonce=str(uuid.uuid4()), setup_id=str(uuid.uuid4()), known_source={"bundleID": "com.neven.gofly", "build": "19"}, options={"source": "project", "artifactPath": None, "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False, "categories": ["favorites"]})
                header = store.read_header()
            self.assertEqual(header["transferID"], transfer)
            self.assertEqual(header["version"], 1)
            self.assertEqual(header["operation"], "reinstall")
            self.assertEqual(header["options"]["categories"], ["favorites"])
            self.assertEqual(store.journal_path.name, "reinstall-journal.json")
            self.assertTrue(store.lock_path.exists())

    def test_backup_validation_precedes_uninstall(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")
            device = Device(package)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            with self.assertRaisesRegex(Exception, "backup-invalid"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=Validator(fail=True)).apply(request(str(uuid.uuid4()), options))
            self.assertEqual(device.uninstall_calls, 0)
            self.assertEqual(len(device.copy_calls), 1)
            self.assertIsNotNone(ReinstallJournalStore(config.state_root).read())

    def test_validator_binding_rejects_target_identity_before_uninstall(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")
            device = Device(package)

            class WrongTarget(Validator):
                def validate(self, backup):
                    result = dict(super().validate(backup))
                    result["targetApp"] = dict(result["targetApp"])
                    result["targetApp"]["build"] = "wrong"
                    return result

            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            with self.assertRaisesRegex(Exception, "backup-invalid"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=WrongTarget(device=device)).apply(request(str(uuid.uuid4()), options))
            self.assertEqual(device.uninstall_calls, 0)
            self.assertEqual(len(device.copy_calls), 1)

    def test_full_controlled_flow_only_marks_complete_after_restore_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")
            device = Device(package)
            validator = Validator(device=device)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            result = ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).apply(request(transfer, options))
            self.assertEqual(result.stage, "complete")
            self.assertTrue(result.proof["backupValidated"] if "backupValidated" in result.proof else False)
            completed = ReinstallJournalStore(config.state_root).read()
            self.assertTrue(is_completed_journal(completed))
            unknown_artifact = copy.deepcopy(completed)
            unknown_artifact["stages"]["artifact"] = {"state": "unknown"}
            self.assertFalse(is_completed_journal(unknown_artifact))
            self.assertEqual(device.uninstall_calls, 1)
            self.assertEqual(device.copy_calls, [config.state_root / "reinstall-transactions" / transfer / "backup"])
            self.assertLess(device.calls.index("publish_restore_intent"), device.calls.index("launch"))
            self.assertLess(device.calls.index("deliver_restore"), device.calls.index("launch"))

    def test_backup_is_revalidated_before_destructive_intent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")
            device = Device(package)

            class ChangedBackup(Validator):
                def __init__(self, **kwargs):
                    super().__init__(**kwargs)
                    self.calls = 0

                def validate(self, backup):
                    self.calls += 1
                    if self.calls == 2:
                        raise ReinstallBridgeError("backup-invalid")
                    return super().validate(backup)

            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            with self.assertRaisesRegex(Exception, "backup-invalid"):
                ReinstallProducer(
                    config,
                    device=device,
                    artifact_validator=ArtifactValidator(artifact),
                    validator=ChangedBackup(device=device),
                ).apply(request(str(uuid.uuid4()), options))
            self.assertEqual(device.uninstall_calls, 0)
            journal = ReinstallJournalStore(config.state_root).read()
            self.assertEqual(journal["stages"]["destructiveIntent"]["state"], "pending")

    def test_changed_sealed_pid_blocks_source_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class ChangedPID(Device):
                def source_pid(self, *_args):
                    return 4321

            device = ChangedPID(package)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                ReinstallProducer(
                    config,
                    device=device,
                    artifact_validator=ArtifactValidator(artifact),
                    validator=Validator(device=device),
                ).apply(request(str(uuid.uuid4()), options))
            self.assertEqual(device.uninstall_calls, 0)
            self.assertNotIn("stop", device.calls)

    def test_final_support_failure_keeps_bound_restore_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class BadSupport(Device):
                def __init__(self, package_root):
                    super().__init__(package_root)
                    self.bad = True

                def support(self, device_id):
                    value = dict(super().support(device_id))
                    if self.bad:
                        value["identifier"] = "unexpected"
                    return value

            device = BadSupport(package)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            apply_request = request(transfer, options)
            with self.assertRaisesRegex(Exception, "support-unavailable"):
                ReinstallProducer(
                    config,
                    device=device,
                    artifact_validator=ArtifactValidator(artifact),
                    validator=Validator(device=device),
                ).apply(apply_request)
            journal = ReinstallJournalStore(config.state_root).read()
            self.assertIsInstance(journal["restoreReceipt"], dict)
            self.assertEqual(journal["stages"]["restoreReceipt"]["state"], "confirmed")
            self.assertEqual(journal["stages"]["finalSupport"]["state"], "unknown")
            device.bad = False
            resumed = ReinstallProducer(
                config,
                device=device,
                artifact_validator=ArtifactValidator(artifact),
                validator=Validator(device=device),
            ).resume(ReinstallRequest(apply_request.request_id, "resume", transfer, DEVICE, options))
            self.assertEqual(resumed.stage, "complete")
            self.assertEqual(device.calls.count("publish_restore_intent"), 1)
            self.assertEqual(device.calls.count("deliver_restore"), 1)

    def test_install_readback_unknown_never_enters_embedded_m1(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class LostInstall(Device):
                def installed(self, _device_id):
                    if self.uninstalled and not self.installed_target:
                        return InstalledAppObservation(False)
                    if self.installed_target:
                        return InstalledAppObservation(False)
                    return InstalledAppObservation(True, build="19")

            device = LostInstall(package)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=Validator(device=device)).apply(request(str(uuid.uuid4()), options))
            self.assertNotIn("launch", device.calls)
            journal = ReinstallJournalStore(config.state_root).read()
            self.assertEqual(journal["stages"]["install"]["state"], "unknown")

    def test_uninstall_unknown_reconciles_absence_without_resubmitting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class UnknownAbsent(Device):
                def uninstall(self, *args):
                    self.uninstall_calls += 1
                    self.uninstalled = True
                    raise SetupBridgeError("removal-unknown")

            device = UnknownAbsent(package)
            validator = Validator(device=device)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            apply_request = request(transfer, options)
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).apply(apply_request)
            resume = ReinstallRequest(apply_request.request_id, "resume", transfer, DEVICE, options)
            result = ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).resume(resume)
            self.assertEqual(result.stage, "complete")
            self.assertEqual(device.uninstall_calls, 1)

    def test_uninstall_unknown_present_stays_locked_without_resubmitting(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class UnknownPresent(Device):
                def uninstall(self, *args):
                    self.uninstall_calls += 1
                    raise SetupBridgeError("removal-unknown")

            device = UnknownPresent(package)
            validator = Validator(device=device)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            apply_request = request(transfer, options)
            producer = ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator)
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                producer.apply(apply_request)
            resume = ReinstallRequest(apply_request.request_id, "resume", transfer, DEVICE, options)
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                producer.resume(resume)
            self.assertEqual(device.uninstall_calls, 1)
            self.assertNotIn("launch", device.calls)

    def test_unknown_export_reuses_durable_command_identity_on_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / "package"
            package.mkdir()
            (package / "manifest.json").write_text("{}", encoding="utf-8")
            config = Config(root / "state", root / "validator")
            artifact = ArtifactIdentity(str(root / "GoFly.app"), "com.neven.gofly", "GoFly", "ABCDEFGHIJ", "1" * 64, "2" * 64, "3" * 64, "2030-01-01T00:00:00Z", {}, "20")

            class FlakyExport(Device):
                def __init__(self, package_root):
                    super().__init__(package_root)
                    self.export_attempts = 0
                    self.export_command_ids = []
                    self.fail_next_readback = False

                def source_request(self, device_id, request_value, control):
                    self.export_attempts += 1
                    self.export_command_ids.append(control["commandID"])
                    if self.export_attempts == 1:
                        raise SetupBridgeError("source-busy")
                    return super().source_request(device_id, request_value, control)

                def source_readback(self, device_id, transfer_id, nonce):
                    existing = super().source_readback(device_id, transfer_id, nonce)
                    if self.fail_next_readback:
                        self.fail_next_readback = False
                        return dataclasses.replace(existing, error_code="source-busy")
                    return existing

            device = FlakyExport(package)
            validator = Validator(device=device)
            options = ReinstallOptions("signedApp", str(root / "GoFly.app"), "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            apply_request = request(transfer, options)
            with self.assertRaisesRegex(Exception, "source-busy"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).apply(apply_request)
            stored = ReinstallJournalStore(config.state_root).read()
            self.assertIsNotNone(stored)
            first_command = stored["commands"]["sourceRequest"]
            self.assertEqual(stored["stages"]["sourceRequest"]["state"], "unknown")

            resume_request = ReinstallRequest(apply_request.request_id, "resume", transfer, DEVICE, options)
            device.fail_next_readback = True
            with self.assertRaisesRegex(Exception, "source-busy"):
                ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).resume(resume_request)
            rejected = ReinstallJournalStore(config.state_root).read()
            self.assertEqual(rejected["commands"]["sourceRequest"]["commandID"], first_command["commandID"])
            self.assertEqual(rejected["commands"]["sourceRequest"]["controlSHA256"], first_command["controlSHA256"])
            self.assertEqual(rejected["stages"]["sourceReady"]["state"], "unknown")
            self.assertEqual(rejected["outcome"], "unknown")
            self.assertNotIn("sourcePID", rejected["commands"]["sourceRequest"])
            self.assertEqual(device.copy_calls, [])
            self.assertEqual(device.uninstall_calls, 0)

            result = ReinstallProducer(config, device=device, artifact_validator=ArtifactValidator(artifact), validator=validator).resume(resume_request)
            self.assertEqual(result.stage, "complete")
            self.assertEqual(device.export_command_ids, [first_command["commandID"], first_command["commandID"]])
            final = ReinstallJournalStore(config.state_root).read()
            self.assertEqual(final["commands"]["sourceRequest"]["commandID"], first_command["commandID"])
            self.assertEqual(final["commands"]["sourceRequest"]["controlSHA256"], first_command["controlSHA256"])

    def test_release_ready_wins_transition_allocates_new_control_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = Config(root / "state", root / "validator")
            device = Device(root / "package")
            producer = ReinstallProducer(config, device=device)
            transfer = str(uuid.uuid4())
            with producer.store.lock():
                journal = producer.store.create(
                    transfer,
                    DEVICE,
                    data_set_id=str(uuid.uuid4()),
                    nonce=str(uuid.uuid4()),
                    setup_id=str(uuid.uuid4()),
                    known_source={"bundleID": "com.neven.gofly", "build": "19"},
                    options={"source": "project", "artifactPath": None, "teamID": "ABCDEFGHIJ", "allowProvisioningUpdates": False, "categories": ["favorites"]},
                )
                journal["requestSHA256"] = "a" * 64
                journal = producer.store.update(journal)
                journal, first = producer._prepare_control(journal, slot="release", action="release", manifest=None, source=None)
                journal["rawManifestSHA256"] = "b" * 64
                journal["sourceApp"] = {"bundleID": "com.neven.gofly", "build": "19", "profileSHA256": "c" * 64, "executableSHA256": "d" * 64}
                journal = producer.store.update(journal)
                journal, second = producer._prepare_control(
                    journal,
                    slot="release",
                    action="release",
                    manifest="b" * 64,
                    source=journal["sourceApp"],
                )
            self.assertNotEqual(first["commandID"], second["commandID"])
            self.assertIsNone(first["manifestSHA256"])
            self.assertEqual(second["manifestSHA256"], "b" * 64)

    def test_abandon_ready_wins_persists_observation_then_uses_new_full_release(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = Config(root / "state", root / "validator")

            class ReadyWins(Device):
                def source_release(self, device_id, control):
                    self.control = dict(control)
                    self.phase = "ready" if control["manifestSHA256"] is None else "released"

            device = ReadyWins(root / "package")
            options = ReinstallOptions("project", None, "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            req = ReinstallRequest(str(uuid.uuid4()), "abandon", transfer, DEVICE, options)
            producer = ReinstallProducer(config, device=device)
            with producer.store.lock():
                journal = producer.store.create(
                    transfer,
                    DEVICE,
                    data_set_id=str(uuid.uuid4()),
                    nonce=str(uuid.uuid4()),
                    setup_id=str(uuid.uuid4()),
                    known_source={"bundleID": "com.neven.gofly", "build": "19"},
                    options=options.as_dict(),
                )
                journal["requestSHA256"] = "e" * 64
                journal = producer.store.update(journal)
                device.transfer_id = transfer
                device.data_set_id = journal["dataSetID"]
                device.nonce = journal["nonce"]
            result = producer.abandon(req)
            self.assertEqual(result.stage, "abandon")
            stored = producer.store.read()
            self.assertEqual(stored["stages"]["abandon"]["state"], "confirmed")
            self.assertEqual(stored["stages"]["sourceReady"]["state"], "confirmed")
            self.assertEqual(len(device.copy_calls), 0)
            self.assertEqual(len(stored["history"]), 1)
            self.assertEqual(stored["history"][0]["phase"], "ready")
            self.assertEqual(stored["commands"]["release"]["action"], "release")
            self.assertNotEqual(stored["commands"]["release"]["commandID"], stored["history"][0]["commandID"])
            self.assertEqual(stored["rawManifestSHA256"], "a" * 64)

    def test_unknown_release_remains_durable_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = Config(root / "state", root / "validator")

            class UnknownRelease(Device):
                def source_release(self, _device_id, control):
                    self.control = dict(control)
                    raise SetupBridgeError("removal-unknown")

            device = UnknownRelease(root / "package")
            options = ReinstallOptions("project", None, "ABCDEFGHIJ", False, ("favorites",))
            transfer = str(uuid.uuid4())
            req = ReinstallRequest(str(uuid.uuid4()), "abandon", transfer, DEVICE, options)
            producer = ReinstallProducer(config, device=device)
            with producer.store.lock():
                journal = producer.store.create(
                    transfer,
                    DEVICE,
                    data_set_id=str(uuid.uuid4()),
                    nonce=str(uuid.uuid4()),
                    setup_id=str(uuid.uuid4()),
                    known_source={"bundleID": "com.neven.gofly", "build": "19"},
                    options=options.as_dict(),
                )
                journal["requestSHA256"] = "e" * 64
                producer.store.update(journal)
            with self.assertRaisesRegex(Exception, "removal-unknown"):
                producer.abandon(req)
            stored = producer.store.read()
            self.assertEqual(stored["stages"]["abandon"]["state"], "unknown")
            self.assertEqual(stored["outcome"], "unknown")
            self.assertEqual(stored["errorCode"], "removal-unknown")


if __name__ == "__main__":
    unittest.main()
