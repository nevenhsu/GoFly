from __future__ import annotations

import datetime as dt
import plistlib
import sys
import tempfile
import types
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

BRIDGE_ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(BRIDGE_ROOT))

from Management import management_adapters
from Management.management_adapters import PinnedManagementDeviceAdapter
from Setup import setup_adapters
from Setup.setup_adapters import close_async_runtime


DEVICE = "00000000-000000000000ABCD"
TEAM = "ABCDEFGHIJ"


class ManagementAdapterTests(unittest.TestCase):
    def tearDown(self) -> None:
        close_async_runtime()

    def test_observe_binds_normalized_udid_and_selected_transport(self) -> None:
        for transport in ("USB", "Network"):
            client = SimpleNamespace(close=AsyncMock())

            async def get_value(*_args: object, **kwargs: object) -> object:
                if kwargs.get("domain"):
                    return True
                return {
                    "UniqueDeviceID": DEVICE,
                    "ProductVersion": "26.1",
                    "TrustedHostAttached": True,
                }

            client.get_value = get_value
            usbmux = types.ModuleType("pymobiledevice3.usbmux")
            usbmux.list_devices = AsyncMock(
                return_value=[SimpleNamespace(serial=DEVICE.lower(), connection_type="Network"),
                                  SimpleNamespace(serial=DEVICE, connection_type="USB")]
            )
            lockdown = types.ModuleType("pymobiledevice3.lockdown")
            lockdown.create_using_usbmux = AsyncMock(return_value=client)
            with patch.dict(
                sys.modules,
                {
                    "pymobiledevice3.usbmux": usbmux,
                    "pymobiledevice3.lockdown": lockdown,
                },
            ), patch.object(
                management_adapters.importlib.metadata,
                "version",
                return_value=management_adapters.PMD3_VERSION,
            ):
                adapter = PinnedManagementDeviceAdapter(SimpleNamespace(), transport)
                observation = adapter.observe(DEVICE.upper())

            self.assertEqual(observation.device_id, DEVICE.lower())
            self.assertEqual(observation.transport, transport)
            self.assertTrue(observation.trust)
            self.assertTrue(observation.developer_mode)
            self.assertEqual(lockdown.create_using_usbmux.call_args.kwargs["serial"],
                             DEVICE if transport == "USB" else DEVICE.lower())
            self.assertIs(lockdown.create_using_usbmux.call_args.kwargs["autopair"], False)
            self.assertEqual(lockdown.create_using_usbmux.call_args.kwargs["connection_type"], transport)
            client.close.assert_awaited_once()

    def test_upgrade_uses_real_artifact_validation_and_fresh_installed_team_before_call(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "GoFly.app"
            app.mkdir()
            (app / "GoFly").write_bytes(b"controlled executable")
            (app / "embedded.mobileprovision").write_bytes(b"controlled profile")
            (app / "Info.plist").write_bytes(
                plistlib.dumps(
                    {
                        "CFBundleIdentifier": "com.neven.gofly",
                        "CFBundleExecutable": "GoFly",
                        "CFBundleVersion": "42",
                    }
                )
            )
            profile = plistlib.dumps(
                {
                    "Entitlements": {
                        "application-identifier": f"{TEAM}.com.neven.gofly",
                        "com.apple.developer.team-identifier": TEAM,
                        "get-task-allow": True,
                    },
                    "TeamIdentifier": [TEAM],
                    "ProvisionedDevices": [DEVICE.lower()],
                    "Platform": ["iOS"],
                    "ExpirationDate": dt.datetime(2027, 1, 1, tzinfo=dt.timezone.utc),
                }
            )
            signed = plistlib.dumps(
                {
                    "application-identifier": f"{TEAM}.com.neven.gofly",
                    "com.apple.developer.team-identifier": TEAM,
                    "get-task-allow": True,
                }
            )

            def controlled_subprocess(arguments: list[str], **_kwargs: object) -> SimpleNamespace:
                if arguments[:3] == ["/usr/bin/security", "cms", "-D"]:
                    output = profile
                elif arguments[:3] == ["/usr/bin/codesign", "-d", "--entitlements"]:
                    output = signed
                elif arguments[:2] == ["/usr/bin/codesign", "-d"]:
                    output = f"Authority=Apple Development: controlled\nTeamIdentifier={TEAM}\n".encode()
                else:
                    output = b""
                return SimpleNamespace(returncode=0, stdout=output, stderr=b"")

            client = SimpleNamespace(close=AsyncMock())

            async def get_value(*_args: object, **kwargs: object) -> object:
                if kwargs.get("domain"):
                    return True
                return {
                    "UniqueDeviceID": DEVICE,
                    "ProductVersion": "26.1",
                    "TrustedHostAttached": True,
                }

            client.get_value = get_value
            usbmux = types.ModuleType("pymobiledevice3.usbmux")
            usbmux.list_devices = AsyncMock(
                return_value=[SimpleNamespace(serial=DEVICE, connection_type="Network")]
            )
            lockdown = types.ModuleType("pymobiledevice3.lockdown")
            lockdown.create_using_usbmux = AsyncMock(return_value=client)
            service = SimpleNamespace(
                get_apps=AsyncMock(
                    side_effect=[
                        {
                            "com.neven.gofly": {
                                "CFBundleIdentifier": "com.neven.gofly",
                                "CFBundleVersion": "41",
                                "ApplicationIdentifier": f"{TEAM}.com.neven.gofly",
                                "TeamIdentifier": TEAM,
                            }
                        },
                        {
                            "com.neven.gofly": {
                                "CFBundleIdentifier": "com.neven.gofly",
                                "CFBundleVersion": "42",
                                "ApplicationIdentifier": f"{TEAM}.com.neven.gofly",
                                "TeamIdentifier": TEAM,
                            }
                        },
                    ]
                ),
                install_from_local=AsyncMock(),
                close=AsyncMock(),
            )
            installation_proxy = types.ModuleType("pymobiledevice3.services.installation_proxy")
            installation_proxy.InstallationProxyService = Mock(return_value=service)
            with patch.dict(
                sys.modules,
                {
                    "pymobiledevice3.usbmux": usbmux,
                    "pymobiledevice3.lockdown": lockdown,
                    "pymobiledevice3.services.installation_proxy": installation_proxy,
                },
            ), patch.object(
                management_adapters.importlib.metadata,
                "version",
                return_value=management_adapters.PMD3_VERSION,
            ), patch.object(setup_adapters.subprocess, "run", side_effect=controlled_subprocess):
                artifact = setup_adapters.FormalArtifactValidator(
                    now=dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
                ).inspect(app, device_id=DEVICE.lower(), team_id=TEAM)
                adapter = PinnedManagementDeviceAdapter(SimpleNamespace(), "Network")
                result = adapter.explicit_upgrade(DEVICE.lower(), artifact)

        self.assertTrue(result.confirmed)
        self.assertEqual(service.get_apps.await_count, 2)
        service.install_from_local.assert_awaited_once_with(
            Path(artifact.path), cmd="Upgrade", developer=True
        )
        service.close.assert_awaited_once()
        self.assertEqual(
            {call.kwargs["connection_type"] for call in lockdown.create_using_usbmux.await_args_list},
            {"Network"},
        )


if __name__ == "__main__":
    unittest.main()
