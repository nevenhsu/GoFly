from __future__ import annotations

import asyncio
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.append(str(Path(__file__).resolve().parents[1]))
from setup_adapters import PinnedPymobiledeviceAdapter, close_async_runtime
from setup_protocol import SetupBridgeError


class ProcessControlTests(unittest.TestCase):
    device = "00000000-000000000000abcd"

    def tearDown(self):
        close_async_runtime()

    def fixture(self, *, current=0, identity=None, version="27.0.1"):
        adapter = PinnedPymobiledeviceAdapter()

        def serial(device):
            self.assertEqual(device, self.device)
            with self.assertRaises(RuntimeError):
                asyncio.get_running_loop()
            return self.device.upper()

        adapter.transport_serial = serial
        rsd = SimpleNamespace(udid=identity or self.device, product_version=version)
        tunnel = SimpleNamespace(aopen=mock.AsyncMock(return_value=rsd), aclose=mock.AsyncMock())
        tunnel_cls = mock.Mock(return_value=tunnel)
        control = mock.MagicMock()
        control.__aenter__ = mock.AsyncMock(return_value=control)
        control.__aexit__ = mock.AsyncMock(return_value=False)
        control.process_identifier_for_bundle_identifier = mock.AsyncMock(return_value=current)
        control.launch = mock.AsyncMock(return_value=123)
        control.kill = mock.AsyncMock()
        provider = mock.MagicMock()
        provider.__aenter__ = mock.AsyncMock(return_value=provider)
        provider.__aexit__ = mock.AsyncMock(return_value=False)
        provider_cls = mock.Mock(return_value=provider)
        modules = {
            "pymobiledevice3.remote.userspace_tunnel": SimpleNamespace(UserspaceRsdTunnel=tunnel_cls),
            "pymobiledevice3.services.dvt.instruments.process_control": SimpleNamespace(ProcessControl=mock.Mock(return_value=control)),
            "pymobiledevice3.services.dvt.instruments.dvt_provider": SimpleNamespace(DvtProvider=provider_cls),
        }
        return adapter, tunnel, tunnel_cls, control, provider_cls, rsd, modules

    def test_launch_uses_verified_rsd_and_never_kills_existing(self):
        adapter, tunnel, constructor, control, provider, rsd, modules = self.fixture()
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            self.assertEqual(adapter.launch(self.device), 123)
        constructor.assert_called_once_with(serial=self.device.upper(), autopair=False, remotepairing_fallback=False)
        provider.assert_called_once_with(rsd)
        control.launch.assert_awaited_once_with("com.neven.gofly", kill_existing=False)
        tunnel.aclose.assert_awaited_once()

    def test_existing_process_is_not_adopted_or_relaunched(self):
        adapter, tunnel, _, control, _, _, modules = self.fixture(current=456)
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            with self.assertRaisesRegex(SetupBridgeError, "app-running"):
                adapter.launch(self.device)
        control.launch.assert_not_awaited()
        control.kill.assert_not_awaited()
        tunnel.aclose.assert_awaited_once()

    def test_stop_requires_observed_pid_match(self):
        adapter, tunnel, _, control, _, _, modules = self.fixture(current=456)
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            with self.assertRaisesRegex(SetupBridgeError, "handoff-unknown"):
                adapter.stop(self.device, expected_pid=123)
        control.kill.assert_not_awaited()
        tunnel.aclose.assert_awaited_once()

    def test_stop_only_kills_exact_transaction_pid(self):
        adapter, _, _, control, _, _, modules = self.fixture(current=123)
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            adapter.stop(self.device, expected_pid=123)
        control.kill.assert_awaited_once_with(123)

    def test_mismatched_rsd_is_closed_before_process_access(self):
        adapter, tunnel, _, control, provider, _, modules = self.fixture(identity="different")
        with mock.patch("setup_adapters.importlib.import_module", side_effect=modules.__getitem__):
            with self.assertRaisesRegex(SetupBridgeError, "identity-mismatch"):
                adapter.launch(self.device)
        provider.assert_not_called()
        control.launch.assert_not_awaited()
        tunnel.aclose.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
