from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


MODULE_ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(MODULE_ROOT))
import gofly_device as device  # noqa: E402


def create_using_usbmux(
    *, serial, label, autopair, connection_type, pair_timeout, pairing_records_cache_folder
):
    return object()


class FakeLockdown:
    def __init__(self, error: Exception | None = None):
        self.calls = []
        self.error = error

    async def create_using_usbmux(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        return object()


class CompatibilityTests(unittest.TestCase):
    def tearDown(self):
        device._modules = None

    def test_pinned_version_and_api_are_accepted(self):
        usbmux = SimpleNamespace(list_devices=lambda: [])
        lockdown = SimpleNamespace(create_using_usbmux=create_using_usbmux)
        with mock.patch.object(device.importlib.metadata, "version", return_value=device.PMD3_VERSION), \
                mock.patch.object(device.importlib, "import_module", side_effect=[usbmux, lockdown]):
            device.check_compatibility()

    def test_version_mismatch_fails_closed(self):
        with mock.patch.object(device.importlib.metadata, "version", return_value="0.0.0"), \
                mock.patch.object(device.importlib, "import_module", side_effect=[SimpleNamespace(), SimpleNamespace()]):
            with self.assertRaisesRegex(device.DeviceError, "runtime-version-mismatch"):
                device.check_compatibility()

    def test_missing_api_fails_closed(self):
        def narrow(serial):
            return object()

        lockdown = SimpleNamespace(create_using_usbmux=narrow)
        usbmux = SimpleNamespace(list_devices=lambda: [])
        with mock.patch.object(device.importlib.metadata, "version", return_value=device.PMD3_VERSION), \
                mock.patch.object(device.importlib, "import_module", side_effect=[usbmux, lockdown]):
            with self.assertRaisesRegex(device.DeviceError, "runtime-api-mismatch"):
                device.check_compatibility()


class ListingTests(unittest.TestCase):
    def tearDown(self):
        device._modules = None

    def test_returns_raw_rows(self):
        rows = [SimpleNamespace(serial="A", connection_type="USB")]
        device._modules = (SimpleNamespace(list_devices=lambda: rows), SimpleNamespace())
        self.assertEqual(asyncio.run(device.list_usb_devices()), rows)

    def test_failure_is_mapped(self):
        def broken():
            raise RuntimeError("boom")

        device._modules = (SimpleNamespace(list_devices=broken), SimpleNamespace())
        with self.assertRaisesRegex(device.DeviceError, "usb-device-list-failed"):
            asyncio.run(device.list_usb_devices())


class LockdownTests(unittest.TestCase):
    def tearDown(self):
        device._modules = None

    def test_uses_usb_without_autopair(self):
        lockdown = FakeLockdown()
        device._modules = (SimpleNamespace(), lockdown)
        cache = Path("/tmp/gofly-cache")
        asyncio.run(device.open_lockdown("ABC", "USB", cache))
        self.assertEqual(lockdown.calls, [{
            "serial": "ABC",
            "connection_type": "USB",
            "pairing_records_cache_folder": cache,
            "autopair": False,
            "pair_timeout": 60,
            "label": "GoFlyMac Read Only",
        }])

    def test_maps_network_connection(self):
        lockdown = FakeLockdown()
        device._modules = (SimpleNamespace(), lockdown)
        asyncio.run(device.open_lockdown("ABC", "Network", Path("/tmp/cache")))
        self.assertEqual(lockdown.calls[0]["connection_type"], "Network")

    def test_open_failure_is_mapped(self):
        device._modules = (SimpleNamespace(), FakeLockdown(error=RuntimeError("no trust")))
        with self.assertRaisesRegex(device.DeviceError, "usb-lockdown-failed"):
            asyncio.run(device.open_lockdown("ABC", "USB", Path("/tmp/cache")))


if __name__ == "__main__":
    unittest.main()
