from __future__ import annotations

import asyncio
import sys
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


MODULE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODULE_ROOT))
import localgo_device as device  # noqa: E402


UDID = "0123456789abcdef0123456789abcdef01234567"


PmdRequired = unittest.skipUnless(
    device.tunnel_service is not None,
    "pymobiledevice3 is provided by the configured setup virtualenv",
)


class FakeLockdown:
    def __init__(self, values: dict, developer: object = True, wifi: object = False):
        self.udid = UDID
        self.values = values
        self.developer = developer
        self.wifi = wifi
        self.closed = False
        self.started = []

    async def get_value(self, domain=None, key=None):
        if domain == device.DEVELOPER_MODE_DOMAIN and key == device.DEVELOPER_MODE_KEY:
            return self.developer
        if domain == device.WIFI_DEBUGGING_DOMAIN and key == device.WIFI_DEBUGGING_KEY:
            return self.wifi
        return self.values

    async def set_value(self, value, domain=None, key=None):
        if domain == device.WIFI_DEBUGGING_DOMAIN and key == device.WIFI_DEBUGGING_KEY:
            self.wifi = value
        return {}

    async def close(self):
        self.closed = True


@PmdRequired
class LocalGoDeviceTests(unittest.TestCase):
    def test_runtime_pin_and_import_guard(self):
        device.check_compatibility()
        with mock.patch.object(device, "_dependency_version", return_value="0.0.0"):
            with self.assertRaisesRegex(device.SetupError, "runtime-version-mismatch"):
                device.check_compatibility()

    def test_inspect_devices_returns_only_usb_identifiers(self):
        usb = SimpleNamespace(serial=UDID.upper(), connection_type="USB")
        network = SimpleNamespace(serial=UDID, connection_type="Network")
        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[usb, network])):
            result = asyncio.run(device.inspect_devices())
        self.assertEqual(result, [{"udid": UDID}])

    def test_inspect_target_passes_raw_transport_serial_to_lockdown(self):
        raw_serial = UDID.upper()
        usb = SimpleNamespace(serial=raw_serial, connection_type="USB")
        values = {"UniqueDeviceID": UDID, "ProductVersion": "26.0"}
        client = FakeLockdown(values)
        calls = []

        async def case_sensitive_open(serial, cache, *, autopair):
            # pymobiledevice3's MuxDevice selector compares this spelling
            # case-sensitively even though our public identity is normalized.
            self.assertEqual(serial, raw_serial)
            calls.append(serial)
            return client

        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[usb])), \
                mock.patch.object(device, "_open_usb_lockdown", new=case_sensitive_open):
            result = asyncio.run(device.inspect_target(UDID))
        self.assertEqual(calls, [raw_serial])
        self.assertEqual(result.udid, UDID)
        self.assertEqual(result.transport_serial, raw_serial)

    def test_inspect_target_rejects_wrong_target_before_lockdown(self):
        usb = SimpleNamespace(serial=UDID, connection_type="USB")
        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[usb])):
            with self.assertRaisesRegex(device.SetupError, "target-device-not-found"):
                asyncio.run(device.inspect_target("fedcba9876543210fedcba9876543210fedcba98"))

    def test_inspect_target_rejects_missing_usb(self):
        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[])):
            with self.assertRaisesRegex(device.SetupError, "no-usb-device"):
                asyncio.run(device.inspect_target(UDID))

    def test_inspect_target_rejects_unsupported_os_and_developer_mode(self):
        usb = SimpleNamespace(serial=UDID, connection_type="USB")
        values = {"UniqueDeviceID": UDID, "ProductVersion": "25.9"}
        client = FakeLockdown(values)
        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[usb])), \
                mock.patch.object(device, "_open_usb_lockdown", new=mock.AsyncMock(return_value=client)):
            with self.assertRaisesRegex(device.SetupError, "unsupported-os-version"):
                asyncio.run(device.inspect_target(UDID))
        values["ProductVersion"] = "26.0"
        client = FakeLockdown(values, developer=False)
        with mock.patch.object(device, "_list_usb_devices", new=mock.AsyncMock(return_value=[usb])), \
                mock.patch.object(device, "_open_usb_lockdown", new=mock.AsyncMock(return_value=client)):
            with self.assertRaisesRegex(device.SetupError, "developer-mode-required"):
                asyncio.run(device.inspect_target(UDID))

    def test_fresh_record_uses_uuid4_and_ed25519_public_key_matches(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "remote_device.plist"
            service = device.LocalGoRemotePairingLockdownService(
                SimpleNamespace(reader=None, writer=None), UDID, path
            )
            identifier = uuid.UUID(service.identifier)
            self.assertEqual(identifier.version, 4)
            service.save_pair_record()
            record, data = device._read_record(path)
            self.assertEqual(len(data), len(path.read_bytes()))
            self.assertEqual(record["identifier"], service.identifier)
            self.assertEqual(record["host_identifier"], service.identifier)
            self.assertEqual(len(record["private_key"]), 32)
            self.assertEqual(len(record["public_key"]), 32)
            self.assertEqual(
                record["public_key"],
                service.ed25519_private_key.public_key().public_bytes_raw(),
            )

    def test_existing_record_reuses_key_and_identifier(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "remote_device.plist"
            original = device.LocalGoRemotePairingLockdownService(
                SimpleNamespace(reader=None, writer=None), UDID, path
            )
            original.save_pair_record()
            key = original.ed25519_private_key.private_bytes_raw()
            identifier = original.identifier
            restored = device.LocalGoRemotePairingLockdownService(
                SimpleNamespace(reader=None, writer=None), UDID, path
            )
            self.assertEqual(restored.identifier, identifier)
            self.assertEqual(restored.ed25519_private_key.private_bytes_raw(), key)

    def test_pair_device_passes_raw_transport_serial_to_lockdown(self):
        raw_serial = UDID.upper()
        values = {"UniqueDeviceID": UDID, "ProductVersion": "26.0"}
        client = FakeLockdown(values)
        calls = []

        class PairingStub:
            _last_pair_verified = False

            @classmethod
            async def create(cls, lockdown_client, pair_record_path):
                return cls()

            async def connect(self, autopair=True):
                self._last_pair_verified = True

            async def close(self):
                return None

        async def case_sensitive_open(serial, cache, *, autopair):
            self.assertEqual(serial, raw_serial)
            calls.append(serial)
            return client

        with tempfile.TemporaryDirectory() as temporary:
            state_dir = Path(temporary)
            record_path = state_dir / f"remote_{UDID}.plist"
            seed = device.LocalGoRemotePairingLockdownService(
                SimpleNamespace(reader=None, writer=None), UDID, record_path
            )
            seed.save_pair_record()
            target = device.DeviceTarget(
                UDID, "26.0", True, False, transport_serial=raw_serial
            )
            with mock.patch.object(device, "inspect_target", new=mock.AsyncMock(return_value=target)), \
                    mock.patch.object(device, "_open_usb_lockdown", new=case_sensitive_open), \
                    mock.patch.object(device, "_pairing_service_class", return_value=PairingStub):
                result = asyncio.run(device.pair_device(UDID, state_dir))
        self.assertEqual(calls, [raw_serial])
        self.assertEqual(result.udid, UDID)

    def test_fresh_pair_verification_failure_does_not_publish_record(self):
        values = {"UniqueDeviceID": UDID, "ProductVersion": "26.0"}
        client = FakeLockdown(values)
        target = device.DeviceTarget(UDID, "26.0", True, False, transport_serial=UDID)

        class PairingStub:
            _last_pair_verified = False

            @classmethod
            async def create(cls, lockdown_client, pair_record_path):
                # Simulate the dependency generating a record during the
                # pairing attempt.  The driver must keep this temporary.
                seed = device.LocalGoRemotePairingLockdownService(
                    SimpleNamespace(reader=None, writer=None), UDID, pair_record_path
                )
                seed.save_pair_record()
                return cls()

            async def connect(self, autopair=True):
                self._last_pair_verified = False

            async def close(self):
                return None

        with tempfile.TemporaryDirectory() as temporary:
            state_dir = Path(temporary)
            with mock.patch.object(device, "inspect_target", new=mock.AsyncMock(return_value=target)), \
                    mock.patch.object(device, "_open_usb_lockdown", new=mock.AsyncMock(return_value=client)), \
                    mock.patch.object(device, "_pairing_service_class", return_value=PairingStub):
                with self.assertRaisesRegex(device.SetupError, "remote-pairing-verification-failed"):
                    asyncio.run(device.pair_device(UDID, state_dir))
            self.assertFalse((state_dir / f"remote_{UDID}.plist").exists())


if __name__ == "__main__":
    unittest.main()
