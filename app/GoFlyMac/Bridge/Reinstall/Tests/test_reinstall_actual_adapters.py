from __future__ import annotations

import contextlib
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

PACKAGE_ROOT = Path(__file__).resolve().parents[2]
import sys

sys.path.insert(0, str(PACKAGE_ROOT))

from Reinstall.reinstall_adapters import (  # noqa: E402
    MAX_VALIDATOR_STDERR,
    MAX_VALIDATOR_STDOUT,
    DeviceObservation,
    PinnedReinstallDeviceAdapter,
    SwiftTransferValidator,
)
from Reinstall.reinstall_protocol import ReinstallBridgeError  # noqa: E402


DEVICE = "01234567-89abcdef01234567"
TRANSFER = "11111111-1111-1111-1111-111111111111"
DATASET = "22222222-2222-2222-2222-222222222222"
NONCE = "33333333-3333-3333-3333-333333333333"
SETUP = "44444444-4444-4444-4444-444444444444"
HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64


class Config:
    def __init__(self, state_root: Path):
        self.state_root = state_root
        self.developer_directory = Path("/Applications/Xcode.app/Contents/Developer")


def _validator_result() -> dict[str, object]:
    return {
        "version": 1,
        "transferID": TRANSFER,
        "dataSetID": DATASET,
        "nonce": NONCE,
        "sourceDeviceUDID": DEVICE,
        "destinationDeviceUDID": DEVICE,
        "sourceApp": {"bundleID": "com.neven.gofly", "build": "19", "profileSHA256": HASH_B, "executableSHA256": HASH_C},
        "targetApp": {"bundleID": "com.neven.gofly", "build": "20", "profileSHA256": HASH_B, "executableSHA256": HASH_C},
        "setupID": SETUP,
        "categories": [],
        "rawManifestSHA256": HASH_A,
        "counts": {"favorites": 0, "importedRoutes": 0, "favoriteRoutes": 0, "draftNodes": 0, "gpxPoints": 0},
    }


class ActualAdapterBoundaryTests(unittest.TestCase):
    def test_swift_validator_drains_both_streams_and_rejects_limits(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            validator = root / "GoFlyTransferValidator"
            validator.write_text(
                "#!/bin/sh\n"
                f"python3 -c 'import sys; sys.stdout.write(\"x\"*{MAX_VALIDATOR_STDOUT + 1}); sys.stderr.write(\"y\"*{MAX_VALIDATOR_STDERR + 1})'\n",
                encoding="utf-8",
            )
            validator.chmod(0o755)
            package = root / "package"
            package.mkdir()
            with self.assertRaisesRegex(ReinstallBridgeError, "backup-invalid"):
                SwiftTransferValidator(validator).validate(package)

    def test_swift_validator_decodes_closed_result(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            validator = root / "GoFlyTransferValidator"
            payload = json.dumps(_validator_result(), separators=(",", ":"))
            validator.write_text(f"#!/bin/sh\nprintf '%s' '{payload}'\n", encoding="utf-8")
            validator.chmod(0o755)
            package = root / "package"
            package.mkdir()
            result = SwiftTransferValidator(validator).validate(package)
            self.assertEqual(result["transferID"], TRANSFER)
            self.assertEqual(result["counts"]["gpxPoints"], 0)

    def test_swift_validator_timeout_kills_child_and_returns_bounded_error(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            validator = root / "GoFlyTransferValidator"
            validator.write_text("#!/bin/sh\nsleep 2\n", encoding="utf-8")
            validator.chmod(0o755)
            package = root / "package"
            package.mkdir()
            with self.assertRaisesRegex(ReinstallBridgeError, "timeout"):
                SwiftTransferValidator(validator, timeout=0.01).validate(package)

    def test_source_package_destination_is_transaction_bound_before_device_access(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            called = False

            def fail_if_open(*_args, **_kwargs):
                nonlocal called
                called = True
                raise AssertionError("device must not be opened for an invalid local path")

            adapter._source_package_context = fail_if_open  # type: ignore[method-assign]
            with self.assertRaisesRegex(ReinstallBridgeError, "storage-unavailable"):
                adapter.copy_source_package(DEVICE, TRANSFER, root / "arbitrary")
            self.assertFalse(called)

    def test_source_package_rejects_existing_unsafe_mode_without_repair(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            destination = root / "state" / "transactions" / TRANSFER / "backup"
            destination.mkdir(parents=True, mode=0o755)
            adapter._source_package_context = lambda *_args: (None, {"dataSetID": DATASET, "artifacts": []}, b"{}")  # type: ignore[method-assign]

            @contextlib.contextmanager
            def fail_if_open(_device: str):
                raise AssertionError("unsafe local destination must fail before AFC access")
                yield

            adapter._house_arrest = fail_if_open  # type: ignore[method-assign]
            with self.assertRaisesRegex(ReinstallBridgeError, "storage-unavailable"):
                adapter.copy_source_package(DEVICE, TRANSFER, destination)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o755)

    def test_source_package_inventory_is_bounded_before_afc_copy(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            destination = root / "state" / "transactions" / TRANSFER / "backup"
            destination.mkdir(parents=True, mode=0o700)
            artifacts = []
            for index in range(513):
                name = f"artifact-{index}.bin"
                path = destination / name
                path.write_bytes(b"x")
                path.chmod(0o600)
                artifacts.append({"path": name, "byteCount": 1, "sha256": HASH_A, "id": f"{index:08d}-1111-1111-1111-111111111111"})
            adapter._source_package_context = lambda *_args: (None, {"dataSetID": DATASET, "artifacts": artifacts}, b"{}")  # type: ignore[method-assign]

            @contextlib.contextmanager
            def fail_if_open(_device: str):
                raise AssertionError("bounded inventory must fail before AFC access")
                yield

            adapter._house_arrest = fail_if_open  # type: ignore[method-assign]
            with self.assertRaisesRegex(ReinstallBridgeError, "backup-invalid"):
                adapter.copy_source_package(DEVICE, TRANSFER, destination)

    def test_source_readback_binds_actual_seal_wire_fields_without_package_fetch(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            request = {
                "version": 1,
                "transferID": TRANSFER,
                "dataSetID": DATASET,
                "nonce": NONCE,
                "sourceDeviceUDID": DEVICE,
                "destinationDeviceUDID": DEVICE,
                "sourceBundleID": "com.neven.gofly",
                "sourceBuild": "19",
                "targetApp": {"bundleID": "com.neven.gofly", "build": "20", "profileSHA256": HASH_B, "executableSHA256": HASH_C},
                "setupID": SETUP,
                "categories": [],
            }
            request_raw = adapter._json_bytes(request, maximum=256 * 1024)
            adapter._write_private_file(root / "state" / "transactions" / TRANSFER / "export-request.json", request_raw, maximum=256 * 1024)
            request_sha = hashlib.sha256(request_raw).hexdigest()
            source = {"bundleID": "com.neven.gofly", "build": "19", "profileSHA256": HASH_B, "executableSHA256": HASH_C}
            control = {
                "version": 1,
                "action": "seal",
                "commandID": "55555555-5555-5555-5555-555555555555",
                "transferID": TRANSFER,
                "nonce": NONCE,
                "requestSHA256": request_sha,
                "manifestSHA256": HASH_A,
                "sourceApp": source,
            }
            response = {
                "version": 1,
                "commandID": control["commandID"],
                "action": "seal",
                "transferID": TRANSFER,
                "nonce": NONCE,
                "requestSHA256": request_sha,
                "manifestSHA256": HASH_A,
                "sourceApp": source,
                "pid": 1234,
                "phase": "removalSealed",
                "receiptSHA256": HASH_C,
                "errorCode": None,
            }
            remote = {
                adapter._CONTROL_REQUEST: adapter._json_bytes(control, maximum=256 * 1024),
                adapter._CONTROL_RESPONSE: adapter._json_bytes(response, maximum=256 * 1024),
            }

            @contextlib.contextmanager
            def fake_house(_device: str):
                yield object()

            adapter._house_arrest = fake_house  # type: ignore[method-assign]
            adapter._base._remote_exists = lambda _service, path: path in remote  # type: ignore[method-assign]
            adapter._base._read_remote_bounded = lambda _service, path, *, max_bytes: remote[path]  # type: ignore[method-assign]
            adapter._current_pid = lambda _device: 1234  # type: ignore[method-assign]

            readback = adapter.source_readback(DEVICE, TRANSFER, NONCE)
            self.assertIsNotNone(readback)
            assert readback is not None
            self.assertEqual(readback.action, "seal")
            self.assertEqual(readback.raw_manifest_sha256, HASH_A)
            self.assertEqual(readback.receipt_sha256, HASH_C)
            self.assertEqual(readback.pid, 1234)

            release_control = {
                **control,
                "action": "release",
                "commandID": "66666666-6666-6666-6666-666666666666",
                "manifestSHA256": None,
                "sourceApp": None,
            }
            release_response = {
                **response,
                "commandID": release_control["commandID"],
                "action": "release",
                "manifestSHA256": HASH_A,
                "phase": "ready",
                "errorCode": "export-conflict",
            }
            remote[adapter._CONTROL_REQUEST] = adapter._json_bytes(release_control, maximum=256 * 1024)
            remote[adapter._CONTROL_RESPONSE] = adapter._json_bytes(release_response, maximum=256 * 1024)
            release_readback = adapter.source_readback(DEVICE, TRANSFER, NONCE)
            self.assertIsNotNone(release_readback)
            assert release_readback is not None
            self.assertEqual(release_readback.action, "release")
            self.assertEqual(release_readback.phase, "ready")
            self.assertEqual(release_readback.error_code, "export-conflict")

    def test_restore_response_rejects_malformed_bytes_without_claiming_receipt(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))

            @contextlib.contextmanager
            def fake_house(_device: str):
                class Base:
                    @staticmethod
                    def _remote_exists(_service, _path):
                        return True

                    @staticmethod
                    def _read_remote_bounded(_service, _path, *, max_bytes):
                        return b"{\"version\":1,\"intent\":null}"

                yield object()

            adapter._house_arrest = fake_house  # type: ignore[method-assign]
            adapter._base._remote_exists = lambda *_args, **_kwargs: True  # type: ignore[method-assign]
            adapter._base._read_remote_bounded = lambda *_args, **_kwargs: b"{\"version\":1,\"intent\":null}"  # type: ignore[method-assign]
            with self.assertRaisesRegex(ReinstallBridgeError, "backup-invalid|restore-unknown"):
                adapter.restore_readback(DEVICE, TRANSFER)

    def test_source_control_reuses_producer_command_and_original_request_digest(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            request = {
                "version": 1,
                "transferID": TRANSFER,
                "dataSetID": DATASET,
                "nonce": NONCE,
                "sourceDeviceUDID": DEVICE,
                "destinationDeviceUDID": DEVICE,
                "sourceBundleID": "com.neven.gofly",
                "sourceBuild": "19",
                "targetApp": {"bundleID": "com.neven.gofly", "build": "20", "profileSHA256": HASH_B, "executableSHA256": HASH_C},
                "setupID": SETUP,
                "categories": [],
            }
            request_raw = adapter._json_bytes(request, maximum=256 * 1024)
            request_path = root / "state" / "transactions" / TRANSFER / "export-request.json"
            adapter._write_private_file(request_path, request_raw, maximum=256 * 1024)
            request_sha = hashlib.sha256(request_raw).hexdigest()
            command_id = "55555555-5555-5555-5555-555555555555"
            control = {
                "version": 1,
                "action": "export",
                "commandID": command_id,
                "transferID": TRANSFER,
                "nonce": NONCE,
                "requestSHA256": request_sha,
                "manifestSHA256": None,
                "sourceApp": None,
            }
            value, control_raw, control_sha = adapter._control_value(
                control,
                device_id=DEVICE,
                expected_action="export",
                expected_request_sha=request_sha,
            )
            self.assertEqual(value["commandID"], command_id)
            self.assertEqual(control_raw, json.dumps(control, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))
            self.assertEqual(control_sha, hashlib.sha256(control_raw).hexdigest())

    def test_source_control_rejects_mixed_release_nullability(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            root = Path(directory)
            adapter = PinnedReinstallDeviceAdapter(Config(root / "state"))
            request = {
                "version": 1,
                "transferID": TRANSFER,
                "dataSetID": DATASET,
                "nonce": NONCE,
                "sourceDeviceUDID": DEVICE,
                "destinationDeviceUDID": DEVICE,
                "sourceBundleID": "com.neven.gofly",
                "sourceBuild": "19",
                "targetApp": {"bundleID": "com.neven.gofly", "build": "20", "profileSHA256": HASH_B, "executableSHA256": HASH_C},
                "setupID": SETUP,
                "categories": [],
            }
            request_raw = adapter._json_bytes(request, maximum=256 * 1024)
            adapter._write_private_file(root / "state" / "transactions" / TRANSFER / "export-request.json", request_raw, maximum=256 * 1024)
            control = {
                "version": 1,
                "action": "release",
                "commandID": "55555555-5555-5555-5555-555555555555",
                "transferID": TRANSFER,
                "nonce": NONCE,
                "requestSHA256": hashlib.sha256(request_raw).hexdigest(),
                "manifestSHA256": HASH_A,
                "sourceApp": None,
            }
            with self.assertRaisesRegex(ReinstallBridgeError, "invalid-request"):
                adapter._control_value(control, device_id=DEVICE, expected_action="release")

    def test_source_signal_uses_closed_url_argv_and_reobserves_pid(self) -> None:
        with tempfile.TemporaryDirectory(dir="/private/tmp") as directory:
            adapter = PinnedReinstallDeviceAdapter(Config(Path(directory) / "state"))
            observed = DeviceObservation(DEVICE, "27.1", "USB", True, True)
            adapter.observe = lambda _device: observed  # type: ignore[method-assign]
            pids = iter((0, 1234))
            adapter._current_pid = lambda _device: next(pids)  # type: ignore[method-assign]
            completed = mock.Mock(returncode=0)
            with mock.patch("Reinstall.reinstall_adapters.subprocess.run", return_value=completed) as run:
                self.assertEqual(adapter._signal_source(DEVICE, TRANSFER, NONCE), 1234)
            argv = run.call_args.args[0]
            self.assertEqual(
                argv,
                [
                    "/usr/bin/xcrun", "devicectl", "device", "process", "launch",
                    "--device", DEVICE, "--payload-url",
                    f"gofly://transfer/export?id={TRANSFER}&nonce={NONCE}",
                    "com.neven.gofly",
                ],
            )
            self.assertNotIn("--terminate-existing", argv)
            self.assertEqual(run.call_args.kwargs["env"]["DEVELOPER_DIR"], "/Applications/Xcode.app/Contents/Developer")


if __name__ == "__main__":
    unittest.main()
