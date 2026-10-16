from __future__ import annotations

import io
import asyncio
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import bridge  # noqa: E402


UDID = "0123456789abcdef0123456789abcdef01234567"
RID = str(uuid.uuid4())


class FakeClient:
    def __init__(self, values, developer=True):
        self.values = values
        self.developer = developer
        self.closed = False
        self.loop_ids = set()

    async def get_value(self, domain=None, key=None):
        self.loop_ids.add(id(asyncio.get_running_loop()))
        if domain == "com.apple.security.mac.amfi" and key == "DeveloperModeStatus":
            return self.developer
        return self.values

    async def close(self):
        self.loop_ids.add(id(asyncio.get_running_loop()))
        self.closed = True


class FakeDeviceModule:
    def __init__(self, rows, client=None):
        self.rows = rows
        self.client = client
        self.calls = []

    def check_compatibility(self):
        return None

    async def _list_usb_devices(self):
        return self.rows

    async def _open_usb_lockdown(self, serial, cache, *, autopair):
        self.calls.append((serial, autopair))
        return self.client


class BridgeTests(unittest.TestCase):
    def config(self):
        root = Path(tempfile.mkdtemp())
        project = root / "StikDebug.xcodeproj"
        project.mkdir()
        return bridge.Config(root, root / "python", root / "Developer", project)

    def modules(self, rows, client=None):
        return bridge.LegacyModules(FakeDeviceModule(rows, client), SimpleNamespace(personal_team=lambda _: "ABCDEFGHIJ"))

    def test_install_rejected_before_loading_or_mutating(self):
        value = {"protocol": 1, "requestID": RID, "action": "install", "deviceID": UDID, "teamID": "ABCDEFGHIJ", "confirmed": True}
        instance = bridge.Bridge(self.config(), None)
        with mock.patch.object(bridge, "load_legacy_modules", side_effect=AssertionError("must not load legacy modules")):
            response = instance.handle(value)
        self.assertEqual(response["status"], "error")
        self.assertEqual(response["code"], "read-only-mode")

    def test_protocol_uuid_and_bounds(self):
        self.assertEqual(bridge._validate_request({"protocol": 1, "requestID": RID, "action": "devices"}), "devices")
        with self.assertRaisesRegex(bridge.BridgeError, "protocol-mismatch"):
            bridge._validate_request({"protocol": 2, "requestID": RID, "action": "devices"})
        with self.assertRaisesRegex(bridge.BridgeError, "invalid-request"):
            bridge._validate_request({"protocol": 1, "requestID": "bad", "action": "devices"})
        self.assertEqual(len(bridge._request_bytes(io.BytesIO(b"a" * bridge.MAX_REQUEST_BYTES))), bridge.MAX_REQUEST_BYTES)
        with self.assertRaises(bridge.BridgeError):
            bridge._request_bytes(io.BytesIO(b"a" * (bridge.MAX_REQUEST_BYTES + 1)))

    def test_internal_error_codes_are_normalized(self):
        self.assertEqual(bridge._map_error("SECRET-PAIRING-DATA"), "operation-failed")
        self.assertEqual(bridge.BridgeError("unexpected-internal").code, "operation-failed")

    def test_device_dedup_prefers_usb_and_skips_unknown_transport(self):
        rows = [
            SimpleNamespace(serial=UDID, connection_type="Network"),
            SimpleNamespace(serial=UDID.upper(), connection_type="USB", name="Phone"),
            SimpleNamespace(serial="not-an-udid", connection_type="USB"),
        ]
        result = bridge.Bridge(self.config(), self.modules(rows)).devices()
        self.assertEqual(result["devices"], [{"id": UDID, "name": "Phone", "transport": "usb", "osVersion": None}])

    def test_inspect_uses_exact_usb_autopair_false_and_unknown_capabilities(self):
        values = {"UniqueDeviceID": UDID, "ProductVersion": "27.0", "DeviceName": "Test Phone"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID.upper(), connection_type="USB")], client)
        result = bridge.Bridge(self.config(), bridge.LegacyModules(device, None)).inspect(UDID)
        self.assertEqual(device.calls, [(UDID.upper(), False)])
        self.assertEqual(result["device"]["transport"], "usb")
        self.assertTrue(result["developerMode"])
        self.assertIsNone(result["vpnInstalled"])
        self.assertFalse(result["canInstall"])
        self.assertFalse(result["canRenew"])

    def test_handle_reuses_one_asyncio_runner_for_open_read_and_close(self):
        values = {"UniqueDeviceID": UDID, "ProductVersion": "27.0", "DeviceName": "Test Phone"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        response = bridge.Bridge(self.config(), bridge.LegacyModules(device, None)).handle(
            {"protocol": 1, "requestID": RID, "action": "inspect", "deviceID": UDID}
        )
        self.assertEqual(response["status"], "ok")
        self.assertEqual(len(client.loop_ids), 1)

    def test_configured_venv_python_symlink_is_accepted(self):
        configured = Path.cwd() / "work/mac-setup-env/bin/python"
        if not configured.is_file() or not (configured.parent.parent / "pyvenv.cfg").is_file():
            self.skipTest("configured mac setup venv is unavailable")
        config = bridge.Config(
            Path.cwd(), configured, self.config().developer_directory, self.config().project_path
        )
        self.assertTrue(bridge.Bridge(config, self.modules([]))._check_python())

    def test_developer_tools_only_require_xcodebuild_under_directory(self):
        config = self.config()
        xcodebuild = config.developer_directory / "usr/bin/xcodebuild"
        xcodebuild.parent.mkdir(parents=True)
        xcodebuild.touch()
        self.assertTrue(bridge.Bridge(config, self.modules([]))._check_developer_tools())

    def test_missing_developer_mode_observation_remains_unknown(self):
        class MissingDeveloper(FakeClient):
            async def get_value(self, domain=None, key=None):
                if domain is not None:
                    raise RuntimeError("unsupported key")
                return self.values

        client = MissingDeveloper({"UniqueDeviceID": UDID, "ProductVersion": "27.0"})
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        result = bridge.Bridge(self.config(), bridge.LegacyModules(device, None)).inspect(UDID)
        self.assertIsNone(result["developerMode"])

    def test_identity_mismatch_fails_closed(self):
        values = {"UniqueDeviceID": "fedcba9876543210fedcba9876543210fedcba98", "ProductVersion": "27.0"}
        client = FakeClient(values)
        device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
        with self.assertRaisesRegex(bridge.BridgeError, "identity-mismatch"):
            bridge.Bridge(self.config(), bridge.LegacyModules(device, None)).inspect(UDID)

    def test_unsupported_or_unknown_ios_stops_before_app_lookup(self):
        for version in ["25.9", None, "invalid"]:
            with self.subTest(version=version):
                client = FakeClient({"UniqueDeviceID": UDID, "ProductVersion": version})
                device = FakeDeviceModule([SimpleNamespace(serial=UDID, connection_type="USB")], client)
                instance = bridge.Bridge(self.config(), bridge.LegacyModules(device, None))
                with mock.patch.object(instance, "_installed_info", side_effect=AssertionError("must not query apps")):
                    response = instance.handle({"protocol": 1, "requestID": RID, "action": "inspect", "deviceID": UDID})
                self.assertEqual(response["status"], "error")
                self.assertEqual(response["code"], "unsupported-os")
                self.assertTrue(client.closed)

    def test_stdio_response_is_single_json_object(self):
        config = self.config()
        config_file = config.workspace_root / "bridge.json"
        config_file.write_text(json.dumps({
            "workspaceRoot": str(config.workspace_root),
            "pythonPath": str(config.python_path),
            "developerDirectory": str(config.developer_directory),
            "projectPath": str(config.project_path),
        }))
        request = json.dumps({"protocol": 1, "requestID": RID, "action": "install"}).encode()
        response = bridge.run_stdio(config_file, stdin=io.BytesIO(request))
        self.assertEqual(response["code"], "read-only-mode")

    def test_stdio_install_gate_precedes_invalid_config(self):
        request = json.dumps({"protocol": 1, "requestID": RID, "action": "install"}).encode()
        with mock.patch.object(bridge.Config, "load", side_effect=AssertionError("config must not load")):
            response = bridge.run_stdio("/missing/config.json", stdin=io.BytesIO(request))
        self.assertEqual(response["code"], "read-only-mode")


if __name__ == "__main__":
    unittest.main()
