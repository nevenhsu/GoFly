from __future__ import annotations

import sys
import plistlib
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from setup_adapters import PinnedPymobiledeviceAdapter, close_async_runtime
from setup_protocol import SetupBridgeError


class USBSerialTests(unittest.TestCase):
    serial = "00000000-000000000000ABCD"

    def tearDown(self) -> None:
        close_async_runtime()

    def adapter(self, rows: list[object], identity: str | None = None):
        client = SimpleNamespace(
            get_value=AsyncMock(return_value={"UniqueDeviceID": identity or self.serial}),
            close=AsyncMock(),
        )
        create = AsyncMock(return_value=client)
        adapter = PinnedPymobiledeviceAdapter()
        adapter._modules = (
            SimpleNamespace(list_devices=AsyncMock(return_value=rows)),
            SimpleNamespace(create_using_usbmux=create),
            SimpleNamespace(),
        )
        return adapter, create, client

    def test_normalized_identity_opens_exact_usb_serial_without_autopair(self):
        rows = [SimpleNamespace(serial=self.serial, connection_type="USB")]
        adapter, create, client = self.adapter(rows)
        with tempfile.TemporaryDirectory() as directory:
            self.assertIs(adapter._open(self.serial.lower(), Path(directory)), client)
        self.assertEqual(create.call_args.kwargs["serial"], self.serial)
        self.assertIs(create.call_args.kwargs["autopair"], False)
        self.assertEqual(create.call_args.kwargs["connection_type"], "USB")

    def test_network_only_match_is_not_selected(self):
        rows = [SimpleNamespace(serial=self.serial, connection_type="Network")]
        adapter, create, _ = self.adapter(rows)
        with self.assertRaisesRegex(SetupBridgeError, "device-disconnected"):
            adapter._open(self.serial.lower(), Path("/tmp"))
        create.assert_not_called()

    def test_other_usb_device_is_not_selected(self):
        adapter, create, _ = self.adapter([
            SimpleNamespace(serial="00000000-000000000000BBBB", connection_type="USB")
        ])
        with self.assertRaisesRegex(SetupBridgeError, "device-disconnected"):
            adapter.transport_serial(self.serial.lower())
        create.assert_not_called()

    def test_lockdown_identity_still_must_match(self):
        adapter, _, client = self.adapter(
            [SimpleNamespace(serial=self.serial, connection_type="USB")],
            identity="00000000-000000000000BBBB",
        )
        with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
            adapter._open(self.serial.lower(), Path("/tmp"))
        client.close.assert_awaited_once()

    def test_pair_candidate_preserves_dependency_remote_unlock_key_types(self):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        key = Ed25519PrivateKey.generate()
        for remote in ("", "peer-host-key", b"peer-host-key"):
            with self.subTest(remote_type=type(remote).__name__, empty=not remote):
                service = SimpleNamespace(
                    ed25519_private_key=key,
                    identifier="12345678-1234-1234-1234-123456789abc",
                    remote_unlock_host_key=remote,
                )
                record = plistlib.loads(PinnedPymobiledeviceAdapter._pair_record_bytes(service))
                self.assertEqual(record["remote_unlock_host_key"], remote)
                self.assertEqual(record["private_key"], key.private_bytes_raw())
                self.assertEqual(record["host_identifier"], service.identifier)

    def test_pair_candidate_rejects_unknown_remote_unlock_key_type(self):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        service = SimpleNamespace(
            ed25519_private_key=Ed25519PrivateKey.generate(),
            identifier="12345678-1234-1234-1234-123456789abc",
            remote_unlock_host_key=123,
        )
        with self.assertRaisesRegex(SetupBridgeError, "pairing-unknown"):
            PinnedPymobiledeviceAdapter._pair_record_bytes(service)


if __name__ == "__main__":
    unittest.main()
