from __future__ import annotations

import contextlib
import hashlib
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from dataclasses import replace
from types import SimpleNamespace
from unittest.mock import patch

import sys

BRIDGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BRIDGE_ROOT))

from Management.management_preparation import ManagementPreparationAdapter
from Management.management_protocol import ManagementBridgeError
from Management.management_source import PreparationAppIdentity


DEVICE = "00000000-000000000000abcd"
TEAM = "ABCDEFGHIJ"
SOURCE_SETUP = "11111111-1111-1111-1111-111111111111"
TARGET_SETUP = "22222222-2222-2222-2222-222222222222"
MANAGEMENT_ID = "33333333-3333-3333-3333-333333333333"
NONCE = "44444444-4444-4444-4444-444444444444"


class FakeAfc:
    def __init__(self, files: dict[str, bytes] | None = None):
        self.files = dict(files or {})
        self.closed = False
        self.stat_calls: dict[str, int] = {}
        self.stat_hook = None

    async def stat(self, path: str) -> dict[str, object]:
        count = self.stat_calls.get(path, 0) + 1
        self.stat_calls[path] = count
        if self.stat_hook is not None:
            self.stat_hook(path, count)
        if path not in self.files:
            raise FileNotFoundError(path)
        return {"st_ifmt": "S_IFREG", "st_size": len(self.files[path])}

    async def fopen(self, path: str, _mode: str = "r") -> list[object]:
        await self.stat(path)
        return [path, 0]

    async def fread(self, handle: list[object], count: int) -> bytes:
        path, offset = handle
        assert isinstance(path, str) and isinstance(offset, int)
        data = self.files[path]
        result = data[offset:offset + count]
        handle[1] = offset + len(result)
        return result

    async def fclose(self, _handle: object) -> None:
        return None

    async def set_file_contents(self, path: str, data: bytes) -> None:
        self.files[path] = data

    async def rename(self, source: str, target: str) -> None:
        self.files[target] = self.files.pop(source)

    async def rm_single(self, path: str, force: bool = False) -> bool:
        if path not in self.files:
            if force:
                return False
            raise FileNotFoundError(path)
        del self.files[path]
        return True

    async def makedirs(self, _path: str) -> None:
        return None

    async def close(self) -> None:
        self.closed = True


class FakeLockdown:
    udid = DEVICE

    async def get_value(self, **_kwargs: object) -> dict[str, str]:
        return {"UniqueDeviceID": DEVICE, "ProductVersion": "26.1"}

    async def close(self) -> None:
        return None


class ManagementPreparationTests(unittest.TestCase):
    @contextlib.contextmanager
    def external_runtime(self, service: FakeAfc):
        async def list_devices() -> list[SimpleNamespace]:
            return [SimpleNamespace(serial=DEVICE, connection_type="Network")]

        async def create_using_usbmux(**_kwargs: object) -> FakeLockdown:
            return FakeLockdown()

        class FakeHouseArrestService:
            @classmethod
            async def create(cls, _client: FakeLockdown, _bundle: str, *, documents_only: bool = False) -> FakeAfc:
                self.assertFalse(documents_only)
                return service

        usbmux = SimpleNamespace(list_devices=list_devices)
        lockdown = SimpleNamespace(create_using_usbmux=create_using_usbmux)
        house_arrest = SimpleNamespace(HouseArrestService=FakeHouseArrestService)
        with patch.dict(
            sys.modules,
            {
                "pymobiledevice3.usbmux": usbmux,
                "pymobiledevice3.lockdown": lockdown,
                "pymobiledevice3.services.house_arrest": house_arrest,
            },
        ), patch("Management.management_adapters.importlib.metadata.version", return_value="11.31.0"):
            yield

    @staticmethod
    def make_adapter() -> ManagementPreparationAdapter:
        return ManagementPreparationAdapter(
            SimpleNamespace(state_root=Path(tempfile.mkdtemp(prefix="gofly-preparation-test-"))),
            "Network",
        )

    def test_fixed_read_distinguishes_missing_from_unknown(self) -> None:
        service = FakeAfc()
        with self.external_runtime(service):
            adapter = self.make_adapter()
            self.assertIsNone(adapter.read_file(DEVICE, "managementRequest"))
            # Turn the external AFC boundary into an unknown failure after
            # the missing case.
            original_stat = service.stat

            async def broken_stat(path: str) -> dict[str, object]:
                if path.endswith("response.json"):
                    raise RuntimeError("AFC session failed")
                return await original_stat(path)

            service.stat = broken_stat  # type: ignore[method-assign]
            with self.assertRaises(ManagementBridgeError) as unknown:
                adapter.read_file(DEVICE, "managementResponse")
            self.assertEqual(unknown.exception.code, "handoff-unknown")

            with self.assertRaises(ManagementBridgeError) as invalid:
                adapter.read_file(DEVICE, "../request.json")
            self.assertEqual(invalid.exception.code, "invalid-request")

    def test_legacy_removal_request_replacement_pairing_envelope_and_pathless_dispatch(self) -> None:
        legacy_path = "Library/Application Support/GoFlySetup/readback-request.json"
        service = FakeAfc({legacy_path: b"old metadata"})
        with self.external_runtime(service):
            adapter = self.make_adapter()

            self.assertTrue(adapter.remove_legacy(DEVICE, "setupReadbackRequest", b"old metadata"))
            self.assertNotIn(legacy_path, service.files)
            service.files[legacy_path] = b"old metadata"
            service.stat_calls.clear()

            def replace_before_removal(path: str, count: int) -> None:
                if path == legacy_path and count == 3:
                    service.files[path] = b"other writer's metadata"

            service.stat_hook = replace_before_removal
            with self.assertRaises(ManagementBridgeError):
                adapter.remove_legacy(DEVICE, "setupReadbackRequest", b"old metadata")
            self.assertEqual(service.files[legacy_path], b"other writer's metadata")
            service.stat_hook = None
            service.files[legacy_path] = b"new metadata"
            with self.assertRaises(ManagementBridgeError) as conflict:
                adapter.remove_legacy(DEVICE, "setupReadbackRequest", b"old metadata")
            self.assertEqual(conflict.exception.code, "transaction-conflict")
            del service.files[legacy_path]

            old = self.request(build="1")
            new = self.request(build="2", management_id="55555555-5555-5555-5555-555555555555")
            request_path = "Library/Application Support/GoFlyManagement/request.json"
            response_path = "Library/Application Support/GoFlyManagement/response.json"
            service.files[request_path] = old
            with self.assertRaises(ManagementBridgeError):
                adapter.publish_management_request(DEVICE, new, previous=old)

            old_value = json.loads(old)
            released = json.dumps(
                {
                    "version": 1,
                    "managementID": old_value["managementID"],
                    "nonce": old_value["nonce"],
                    "requestSHA256": hashlib.sha256(old).hexdigest(),
                    "phase": "released",
                    "pid": 123,
                    "app": old_value["sourceApp"],
                    "sourceSetupID": old_value["sourceSetupID"],
                    "activationSHA256": old_value["sourceActivationSHA256"],
                    "restoreRootSHA256": None,
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
            service.files[response_path] = released
            service.stat_calls.clear()

            def mutate_fresh_response(path: str, count: int) -> None:
                if path == response_path and count == 4:
                    service.files[response_path] = b"changed response"

            service.stat_hook = mutate_fresh_response
            with self.assertRaises(ManagementBridgeError) as response_changed:
                adapter.publish_management_request(DEVICE, new, previous=old)
            self.assertEqual(response_changed.exception.code, "transaction-conflict")
            self.assertEqual(service.files[request_path], old)

            service.files[response_path] = released
            service.stat_calls.clear()

            def mutate_fresh_request(path: str, count: int) -> None:
                if path == request_path and count == 4:
                    service.files[request_path] = b"changed request"

            service.stat_hook = mutate_fresh_request
            with self.assertRaises(ManagementBridgeError) as request_changed:
                adapter.publish_management_request(DEVICE, new, previous=old)
            self.assertEqual(request_changed.exception.code, "transaction-conflict")
            self.assertEqual(service.files[request_path], b"changed request")

            service.files[request_path] = old
            service.stat_calls.clear()
            service.stat_hook = None
            adapter.publish_management_request(DEVICE, new, previous=old)
            self.assertEqual(service.files[request_path], new)

            # Publish the real mailbox through the same external HouseArrest
            # boundary.  A pre-ready release is the only q->release escape;
            # reverse transitions remain rejected and never overwrite it.
            # The prior terminal response remains until this App responds.
            # It must not prevent cancelling the new request before ready.
            control_path = "Library/Application Support/GoFlyManagement/control-request.json"
            control = lambda action: json.dumps(
                {
                    "version": 1,
                    "managementID": json.loads(new)["managementID"],
                    "nonce": json.loads(new)["nonce"],
                    "requestSHA256": hashlib.sha256(new).hexdigest(),
                    "action": action,
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
            quiesce = control("quiesce")
            release = control("release")
            service.files[control_path + ".staging"] = quiesce
            adapter.publish_control(DEVICE, quiesce)
            self.assertEqual(service.files[control_path], quiesce)
            self.assertNotIn(control_path + ".staging", service.files)
            adapter.publish_control(DEVICE, quiesce, previous=quiesce)
            adapter.publish_control(DEVICE, release, previous=quiesce, previous_request=old)
            self.assertEqual(service.files[control_path], release)
            with self.assertRaises(ManagementBridgeError) as monotonic:
                adapter.publish_control(DEVICE, quiesce, previous=release)
            self.assertEqual(monotonic.exception.code, "transaction-conflict")

            bad_control = json.loads(release)
            bad_control["action"] = []
            with self.assertRaises(ManagementBridgeError) as bad_action:
                adapter.publish_control(
                    DEVICE,
                    json.dumps(bad_control, sort_keys=True, separators=(",", ":")).encode(),
                )
            self.assertEqual(bad_action.exception.code, "invalid-request")

            bad_request = json.loads(new)
            bad_request["kind"] = []
            with self.assertRaises(ManagementBridgeError) as bad_kind:
                adapter.publish_management_request(
                    DEVICE,
                    json.dumps(bad_request, sort_keys=True, separators=(",", ":")).encode(),
                )
            self.assertEqual(bad_kind.exception.code, "invalid-request")

            wrong_device = self.request(build="3", expected_device="00000000-000000000000beef")
            with self.assertRaises(ManagementBridgeError) as wrong_target:
                adapter.publish_management_request(DEVICE, wrong_device)
            self.assertEqual(wrong_target.exception.code, "identity-mismatch")

            with tempfile.TemporaryDirectory() as directory:
                candidate = Path(directory) / "pairing.candidate"
                candidate.write_bytes(b"pairing-record")
                candidate.chmod(0o600)
                adapter.deliver_pairing(
                    DEVICE,
                    candidate,
                    "66666666-6666-6666-6666-666666666666",
                    hashlib.sha256(b"pairing-record").hexdigest(),
                )
                remote = "Library/Application Support/LocalGoSetup/incoming.plist"
                envelope = plistlib.loads(service.files[remote])
                self.assertEqual(envelope["version"], 1)
                self.assertEqual(envelope["pairingFile"], b"pairing-record")
                self.assertEqual(envelope["sha256"], hashlib.sha256(b"pairing-record").digest())

            identity = PreparationAppIdentity(
                "com.neven.gofly", "2", "a" * 64, "b" * 64, TEAM,
                "2027-01-01T00:00:00Z",
            )
            readback_path = "Library/Application Support/GoFlySetup/readback-request.json"
            with self.assertRaises(ManagementBridgeError) as invalid_identity:
                adapter.prepare_readback(DEVICE, TARGET_SETUP, NONCE,
                                         replace(identity, bundle_id="com.other.app"))
            self.assertEqual(invalid_identity.exception.code, "identity-unverified")
            self.assertNotIn(readback_path, service.files)
            adapter.prepare_readback(DEVICE, TARGET_SETUP, NONCE, identity)
            readback = json.loads(service.files[readback_path])
            self.assertEqual(readback["setupID"], TARGET_SETUP)
            self.assertEqual(readback["app"]["build"], identity.build)

    @staticmethod
    def request(
        *,
        build: str,
        management_id: str = MANAGEMENT_ID,
        expected_device: str = DEVICE,
    ) -> bytes:
        app = {
            "bundleID": "com.neven.gofly",
            "build": build,
            "profileSHA256": "a" * 64,
            "executableSHA256": "b" * 64,
        }
        return json.dumps(
            {
                "version": 1,
                "managementID": management_id,
                "nonce": NONCE,
                "kind": "renew",
                "expectedDeviceUDID": expected_device,
                "sourceSetupID": SOURCE_SETUP,
                "sourceApp": app,
                "sourceActivationSHA256": "c" * 64,
                "sourceRestoreRootSHA256": None,
                "teamID": TEAM,
                "targetSetupID": TARGET_SETUP,
                "targetApp": {**app, "build": build},
            },
            sort_keys=True,
            separators=(",", ":"),
        ).encode()


if __name__ == "__main__":
    unittest.main()
