#!/usr/bin/env python3
"""Small, read-only JSON bridge used by the GoFly macOS setup UI.

The process has one request and one response.  It deliberately keeps the
device dependency behind a narrow adapter so the same protocol can be tested
without an iPhone or Xcode.  The product scope is read-only.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import contextvars
import importlib.util
import io
import json
import logging
import os
import plistlib
import re
import selectors
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping


# Bundled legacy helpers are imported at runtime.  Avoid producing bytecode
# beside either the packaged helper or the workspace fallback.
sys.dont_write_bytecode = True


try:
    from .wire import (
        MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES, SAFE_ERROR_CODES, UUID_RE, TEAM_RE,
        WireError, action as wire_action, encode as wire_encode, emit as wire_emit,
        parse_object, read_request, request_id as wire_request_id, response as wire_response,
    )
except ImportError:  # direct script execution from the Bridge directory
    # ProcessBridge launches this file with `python -I`, which does not add the
    # script directory to sys.path.  Restore the sibling module lookup so the
    # packaged `wire.py` is importable.
    _bridge_root = str(Path(__file__).resolve().parent)
    if _bridge_root not in sys.path:
        sys.path.insert(0, _bridge_root)
    from wire import (
        MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES, SAFE_ERROR_CODES, UUID_RE, TEAM_RE,
        WireError, action as wire_action, encode as wire_encode, emit as wire_emit,
        parse_object, read_request, request_id as wire_request_id, response as wire_response,
    )

BridgeError = WireError
DEFAULT_BUNDLE_ID = "com.neven.gofly"
DEFAULT_TARGET_NAME = "GoFly"
PMD3_VERSION = "11.31.0"
LOCALDEVVPN_BUNDLE_ID = "com.jkcoxson.LocalDevVPN"
USB = "USB"
NETWORK = "Network"
SUPPORTED_OS_MAJOR = 26
UDID_RE = re.compile(r"(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{40})\Z")
_ACTIVE_RUNNER: contextvars.ContextVar[asyncio.Runner | None] = contextvars.ContextVar(
    "gofly_active_runner", default=None
)


@dataclass(frozen=True)
class Config:
    workspace_root: Path
    python_path: Path
    developer_directory: Path
    project_path: Path
    target_bundle_id: str = DEFAULT_BUNDLE_ID
    target_name: str = DEFAULT_TARGET_NAME

    @classmethod
    def load(cls, path: str | Path) -> "Config":
        path = Path(path)
        if not path.is_absolute() or path.is_symlink() or not path.is_file():
            raise BridgeError("configuration-invalid")
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError):
            raise BridgeError("configuration-invalid") from None
        if not isinstance(raw, dict):
            raise BridgeError("configuration-invalid")

        def required_path(name: str) -> Path:
            value = raw.get(name)
            if not isinstance(value, str) or not value or not Path(value).is_absolute():
                raise BridgeError("configuration-invalid")
            return Path(value)

        workspace = required_path("workspaceRoot")
        python = required_path("pythonPath")
        developer = required_path("developerDirectory")
        project = required_path("projectPath")
        bundle = raw.get("targetBundleID", DEFAULT_BUNDLE_ID)
        name = raw.get("targetName", DEFAULT_TARGET_NAME)
        if not isinstance(bundle, str) or not re.fullmatch(r"[A-Za-z0-9.-]{1,200}", bundle):
            raise BridgeError("configuration-invalid")
        if not isinstance(name, str) or not (1 <= len(name) <= 200):
            raise BridgeError("configuration-invalid")
        return cls(workspace, python, developer, project, bundle, name)


def _load_module(path: Path, name: str) -> Any:
    if path.is_symlink() or not path.is_file():
        raise BridgeError("runtime-unavailable")
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise BridgeError("runtime-unavailable")
    module = importlib.util.module_from_spec(spec)
    # Use a private module name so a different invocation cannot accidentally
    # reuse a module loaded from an arbitrary working directory.
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        sys.modules.pop(name, None)
        raise BridgeError("runtime-unavailable") from None
    return module


def load_device_module(config: Config) -> Any:
    """Load the packaged read-only device boundary, with a source-tree fallback."""

    bundled = Path(__file__).resolve().parent / "Device" / "gofly_device.py"
    source = config.workspace_root / "app" / "GoFlyMac" / "Bridge" / "Device" / "gofly_device.py"
    if bundled.is_file():
        path = bundled
    elif source.is_file():
        path = source
    else:
        raise BridgeError("runtime-unavailable")
    return _load_module(path, "_gofly_device_boundary")


@contextlib.contextmanager
def quiet_dependencies() -> Iterable[None]:
    """Prevent library diagnostics from corrupting the one-line protocol."""

    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        try:
            yield
        finally:
            logging.disable(previous)


def _await(value: Any) -> Any:
    if not asyncio.iscoroutine(value) and not isinstance(value, asyncio.Future):
        return value
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        runner = _ACTIVE_RUNNER.get()
        if runner is not None:
            return runner.run(value)
        return asyncio.run(value)
    raise BridgeError("operation-failed")


def _new_async_runner() -> Any:
    factory = getattr(asyncio, "Runner", None)
    if factory is not None:
        return factory()
    class LegacyRunner:
        def __init__(self) -> None:
            self.loop = asyncio.new_event_loop()
        def run(self, value: Any) -> Any:
            return self.loop.run_until_complete(value)
        def close(self) -> None:
            self.loop.close()
    return LegacyRunner()


def _normalized_udid(value: Any) -> str | None:
    if not isinstance(value, str) or not UDID_RE.fullmatch(value.strip()):
        return None
    return value.strip().lower()


def _value(item: Any, *names: str) -> Any:
    if isinstance(item, Mapping):
        for name in names:
            if name in item:
                return item[name]
    for name in names:
        try:
            result = getattr(item, name)
        except Exception:
            continue
        if result is not None:
            return result
    return None


def _transport(item: Any) -> str | None:
    value = _value(item, "connection_type", "ConnectionType", "connectionType")
    if isinstance(value, str):
        value = value.strip().lower()
        if value == "usb":
            return "usb"
        if value in {"network", "wifi", "wi-fi"}:
            return "wifi"
    if _value(item, "is_usb", "isUSB") is True:
        return "usb"
    if _value(item, "is_network", "isNetwork") is True:
        return "wifi"
    return None


def _version_supported(value: Any) -> bool:
    if not isinstance(value, str):
        return False
    match = re.match(r"\s*(\d+)(?:\.\d+)*\s*\Z", value)
    return bool(match and int(match.group(1)) >= SUPPORTED_OS_MAJOR)


def _safe_process(arguments: list[str], *, env: Mapping[str, str] | None = None, timeout: int = 30) -> tuple[int, bytes]:
    """Run one fixed command while bounding captured stdout and stderr."""

    process: subprocess.Popen[bytes] | None = None
    selector: selectors.BaseSelector | None = None
    try:
        process = subprocess.Popen(
            arguments,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=dict(env) if env is not None else None,
        )
        assert process.stdout is not None and process.stderr is not None
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ, False)
        selector.register(process.stderr, selectors.EVENT_READ, True)
        output = bytearray()
        deadline = time.monotonic() + timeout
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(arguments, timeout)
            for key, _ in selector.select(remaining):
                chunk = os.read(key.fileobj.fileno(), 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                if not key.data:
                    if len(output) + len(chunk) > 64 * 1024:
                        raise BridgeError("operation-failed")
                    output.extend(chunk)
        return process.wait(timeout=max(0.1, deadline - time.monotonic())), bytes(output)
    except BridgeError:
        if process is not None:
            with contextlib.suppress(OSError):
                process.kill()
            with contextlib.suppress(Exception):
                process.communicate(timeout=1)
        raise
    except (OSError, subprocess.TimeoutExpired):
        if process is not None:
            with contextlib.suppress(OSError):
                process.kill()
            with contextlib.suppress(Exception):
                process.communicate(timeout=1)
        raise BridgeError("operation-failed") from None
    finally:
        if selector is not None:
            selector.close()
        if process is not None:
            for stream in (process.stdout, process.stderr):
                if stream is not None:
                    with contextlib.suppress(OSError):
                        stream.close()


class Bridge:
    def __init__(self, config: Config, device: Any | None = None):
        self.config = config
        self._device = device

    @property
    def device(self) -> Any:
        if self._device is None:
            self._device = load_device_module(self.config)
        return self._device

    def _raw_devices(self) -> list[Any]:
        device = self.device
        check = getattr(device, "check_compatibility", None)
        list_devices = getattr(device, "list_usb_devices", None)
        if not callable(check) or not callable(list_devices):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                check()
                result = _await(list_devices())
        except BridgeError:
            raise
        except Exception as error:
            code = getattr(error, "code", "")
            raise BridgeError(_map_error(code or "operation-failed")) from None
        if not isinstance(result, list):
            raise BridgeError("operation-failed")
        return result

    def _device_rows(self, raw: list[Any]) -> list[dict[str, Any]]:
        selected: dict[tuple[str, str], dict[str, Any]] = {}
        for item in raw:
            transport = _transport(item)
            identity = _normalized_udid(_value(item, "serial", "SerialNumber", "UDID", "udid", "unique_device_id"))
            if transport is None or identity is None:
                continue
            name = _value(item, "name", "device_name", "DeviceName")
            version = _value(item, "os_version", "ProductVersion", "product_version")
            row = {
                "id": identity,
                # usbmux usually does not expose a name.  Empty is an
                # explicit unknown value while preserving the stable shape
                # required by the macOS UI.
                "name": name if isinstance(name, str) else "",
                "transport": transport,
                "osVersion": version if isinstance(version, str) else None,
            }
            selected.setdefault((identity, transport), row)
        return list(selected.values())

    def devices(self) -> dict[str, Any]:
        return {"devices": self._device_rows(self._raw_devices())}

    def _teams(self) -> list[dict[str, Any]]:
        defaults = Path("/usr/bin/defaults")
        if not defaults.is_file():
            return []
        env = os.environ.copy()
        try:
            status, data = _safe_process([str(defaults), "export", "com.apple.dt.Xcode", "-"], env=env, timeout=20)
        except BridgeError:
            return []
        if status != 0:
            return []
        try:
            values = plistlib.loads(data)
        except Exception:
            return []
        if not isinstance(values, dict):
            return []
        groups = values.get("IDEProvisioningTeamByIdentifier")
        if not isinstance(groups, Mapping):
            return []
        found: dict[str, dict[str, Any]] = {}
        for group in groups.values():
            if not isinstance(group, list):
                continue
            for item in group:
                if not isinstance(item, Mapping):
                    continue
                team_id = item.get("teamID")
                if not isinstance(team_id, str) or TEAM_RE.fullmatch(team_id) is None:
                    continue
                name = item.get("teamName")
                if not isinstance(name, str) or not name or len(name) > 200:
                    name = f"Team {team_id}"
                free = item.get("isFreeProvisioningTeam") is True
                found.setdefault(team_id, {
                    "teamID": team_id,
                    "teamName": name,
                    "isFreeProvisioningTeam": free,
                })
        return sorted(found.values(), key=lambda team: (team["teamName"], team["teamID"]))

    def _check_python(self) -> bool:
        path = self.config.python_path
        if not path.is_file() or not os.access(path, os.X_OK):
            return False
        # A standard venv exposes ``bin/python`` as a symlink.  Require the
        # adjacent pyvenv.cfg and verify the interpreter reports that same
        # venv prefix; this permits the normal symlink while rejecting an
        # arbitrary executable supplied under a Python-looking name.
        venv = path.parent.parent
        if not (venv / "pyvenv.cfg").is_file():
            return False
        try:
            status, data = _safe_process(
                [
                    str(path),
                    "-c",
                    "import importlib.metadata as m,sys; print(sys.executable); print(sys.prefix); print(m.version('pymobiledevice3'))",
                ],
                timeout=20,
            )
        except BridgeError:
            return False
        try:
            lines = data.decode("ascii", "strict").strip().splitlines()
            executable, prefix, version = lines[-3:]
        except (UnicodeDecodeError, ValueError):
            return False
        return status == 0 and Path(prefix).resolve() == venv.resolve() and version == PMD3_VERSION and Path(executable).resolve() == path.resolve()

    def _check_project(self) -> bool:
        path = self.config.project_path
        return path.is_absolute() and not path.is_symlink() and path.is_dir() and path.suffix == ".xcodeproj"

    def _check_developer_tools(self) -> bool:
        developer = self.config.developer_directory
        if developer.is_symlink() or not developer.is_dir():
            return False
        # xcrun is intentionally the fixed system shim; DEVELOPER_DIR selects
        # the configured Xcode installation without trusting PATH.
        return (developer / "usr/bin/xcodebuild").is_file()

    def _check_first_launch(self) -> bool:
        if not self._check_developer_tools() or not Path("/usr/bin/xcrun").is_file():
            return False
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(self.config.developer_directory)
        try:
            status, _ = _safe_process(["/usr/bin/xcrun", "xcodebuild", "-checkFirstLaunchStatus"], env=env, timeout=30)
        except BridgeError:
            return False
        return status == 0

    def _xcode_version(self) -> str | None:
        if not Path("/usr/bin/xcrun").is_file():
            return None
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(self.config.developer_directory)
        try:
            status, data = _safe_process(["/usr/bin/xcrun", "xcodebuild", "-version"], env=env, timeout=20)
        except BridgeError:
            return None
        if status != 0:
            return None
        try:
            first = data.decode("utf-8", "strict").splitlines()[0].strip()
        except (UnicodeDecodeError, IndexError):
            return None
        match = re.fullmatch(r"Xcode\s+([0-9][^\r\n]{0,40})", first)
        return match.group(1) if match else None

    @staticmethod
    def _macos_version() -> str | None:
        executable = Path("/usr/bin/sw_vers")
        if not executable.is_file():
            return None
        try:
            status, data = _safe_process([str(executable), "-productVersion"], timeout=10)
        except BridgeError:
            return None
        if status != 0:
            return None
        try:
            value = data.decode("ascii", "strict").strip()
        except UnicodeDecodeError:
            return None
        return value if re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", value) else None

    def environment(self) -> dict[str, Any]:
        checks: list[dict[str, Any]] = []

        def check(identifier: str, title: str, detail: str, passed: bool) -> None:
            checks.append({"id": identifier, "title": title, "detail": detail, "passed": bool(passed)})

        project = self._check_project()
        check("project", "Xcode 專案", "已找到設定的 Xcode 專案。" if project else "找不到設定的 Xcode 專案。", project)
        tools_ok = self._check_developer_tools()
        xcode = self._xcode_version() if tools_ok else None
        macos = self._macos_version()
        tool_detail = "已找到設定的 Xcode 開發者目錄。"
        if xcode:
            tool_detail += f" Xcode {xcode}。"
        if macos:
            tool_detail += f" macOS {macos}。"
        if not tools_ok:
            tool_detail = "找不到可用的 Xcode 開發者目錄。"
        check("developer-tools", "Xcode 開發者工具", tool_detail, tools_ok)
        first = self._check_first_launch() if tools_ok else False
        check("xcode-first-launch", "Xcode 初始狀態", "Xcode 已完成初始檢查。" if first else "Xcode 初始檢查未通過。", first)
        python_ok = self._check_python()
        check("python-runtime", "Python 檢查環境", "已確認固定版本的 Python 依賴。" if python_ok else "找不到固定版本的 Python 依賴。", python_ok)

        device_ok = False
        try:
            raw = self._raw_devices()
            device_ok = True
            device_count = len(self._device_rows(raw))
            detail = f"裝置清單可讀取，目前觀察到 {device_count} 台裝置。"
        except BridgeError:
            detail = "無法讀取裝置清單。"
        check("device-discovery", "裝置清單", detail, device_ok)

        teams = self._teams()
        check("apple-account", "Apple 開發者帳號",
              f"已找到 {len(teams)} 個可用 Team。" if teams else "請在 Xcode → Settings → Apple Accounts 登入。",
              bool(teams))

        # A missing team blocks installation in the future, but does not make
        # read-only environment/device management unavailable.
        base_ids = {"project", "developer-tools", "xcode-first-launch", "python-runtime",
                    "device-discovery", "apple-account"}
        ready = all(item["passed"] for item in checks if item["id"] in base_ids)
        return {"ready": ready, "checks": checks, "teams": teams, "xcodeVersion": xcode}

    def _find_device(self, raw: list[Any], target: str, selected_transport: str | None = None) -> tuple[Any, str, str]:
        matches: list[tuple[int, Any, str, str]] = []
        for item in raw:
            transport = _transport(item)
            serial = _value(item, "serial", "SerialNumber", "UDID", "udid", "unique_device_id")
            identity = _normalized_udid(serial)
            if transport is None or identity != target or (selected_transport is not None and transport != selected_transport):
                continue
            connection = _value(item, "connection_type", "ConnectionType", "connectionType")
            connection = connection.strip() if isinstance(connection, str) else (USB if transport == "usb" else NETWORK)
            matches.append((0 if transport == "usb" else 1, item, str(serial), connection))
        if not matches:
            raise BridgeError("device-disconnected")
        matches.sort(key=lambda item: item[0])
        _, item, serial, connection = matches[0]
        return item, serial, connection

    def _open_lockdown(self, serial: str, connection: str, cache: Path) -> Any:
        opener = getattr(self.device, "open_lockdown", None)
        if not callable(opener):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                return _await(opener(serial, connection, cache, autopair=False))
        except BridgeError:
            raise
        except Exception as error:
            raise BridgeError(_map_error(getattr(error, "code", "trust-required"))) from None

    def _read_values(self, client: Any, expected: str) -> dict[str, Any]:
        getter = getattr(client, "get_value", None)
        if not callable(getter):
            raise BridgeError("runtime-api-mismatch")
        try:
            with quiet_dependencies():
                values = _await(getter())
        except Exception:
            raise BridgeError("trust-required") from None
        if not isinstance(values, Mapping):
            raise BridgeError("operation-failed")
        # Older lockdown variants may not expose DeveloperModeStatus.  That
        # is an unknown observation, not evidence that developer mode is off.
        developer_mode: bool | None = None
        try:
            with quiet_dependencies():
                developer_value = _await(getter(domain="com.apple.security.mac.amfi", key="DeveloperModeStatus"))
            if isinstance(developer_value, bool):
                developer_mode = developer_value
        except Exception:
            developer_mode = None
        actual = _normalized_udid(values.get("UniqueDeviceID"))
        if actual is None or actual != expected:
            raise BridgeError("identity-mismatch")
        version = values.get("ProductVersion")
        return {
            "id": actual,
            "name": values.get("DeviceName") if isinstance(values.get("DeviceName"), str) else "",
            "osVersion": version if isinstance(version, str) else None,
            "developerMode": developer_mode,
            "supportedOS": _version_supported(version),
        }

    def _installed_info(self, client: Any, *, bundle_id: str | None = None) -> tuple[bool | None, Mapping[str, Any] | None]:
        bundle_id = bundle_id or self.config.target_bundle_id
        try:
            from pymobiledevice3.services.installation_proxy import InstallationProxyService
        except Exception:
            return None, None
        service = None
        try:
            with quiet_dependencies():
                service = InstallationProxyService(client)
                apps = _await(service.get_apps(bundle_identifiers=[bundle_id]))
        except Exception:
            return None, None
        finally:
            if service is not None:
                with contextlib.suppress(Exception):
                    _await(service.close())
        if not isinstance(apps, Mapping):
            raise BridgeError("operation-failed")
        if bundle_id not in apps:
            return False, None
        target = apps[bundle_id]
        if not isinstance(target, Mapping):
            raise BridgeError("operation-failed")
        return True, target

    def inspect(self, target: str, selected_transport: str | None = None) -> dict[str, Any]:
        target = _normalized_udid(target) or (_ for _ in ()).throw(BridgeError("invalid-request"))
        raw = self._raw_devices()
        item, serial, connection = self._find_device(raw, target, selected_transport)
        with tempfile.TemporaryDirectory(prefix="goflymac-inspect-") as temporary:
            cache = Path(temporary)
            client = self._open_lockdown(serial, connection, cache)
            try:
                values = self._read_values(client, target)
                if not values["supportedOS"]:
                    raise BridgeError("unsupported-os")
                installed, info = self._installed_info(client)
                vpn_installed, _ = self._installed_info(client, bundle_id=LOCALDEVVPN_BUNDLE_ID)
            finally:
                with contextlib.suppress(Exception):
                    _await(getattr(client, "close")())
        raw_name = _value(item, "name", "device_name", "DeviceName")
        if not values["name"] and isinstance(raw_name, str):
            values["name"] = raw_name
        version = info.get("CFBundleShortVersionString") if isinstance(info, Mapping) else None
        if not isinstance(version, str) and isinstance(info, Mapping):
            version = info.get("CFBundleVersion")
        if not isinstance(version, str):
            version = None
        return {
            "device": {
                "id": values["id"],
                "name": values["name"],
                "transport": "usb" if connection.upper() == USB else "wifi",
                "osVersion": values["osVersion"],
            },
            "developerMode": values["developerMode"],
            "installed": installed,
            "vpnInstalled": vpn_installed,
            "appVersion": version,
            "teamID": None,
            "expiresAt": None,
        }

    def handle(self, request: Any) -> dict[str, Any]:
        runner = _ACTIVE_RUNNER.get()
        if runner is not None:
            return self._handle(request)
        # Keep one event loop alive for every async dependency call in this
        # request.  In particular, a lockdown client must be opened, used,
        # and closed on the same loop.
        runner = _new_async_runner()
        token = _ACTIVE_RUNNER.set(runner)
        try:
            return self._handle(request)
        finally:
            _ACTIVE_RUNNER.reset(token)
            runner.close()

    def _handle(self, request: Any) -> dict[str, Any]:
        request_id = request.get("requestID") if isinstance(request, dict) else None
        try:
            action = _validate_request(request)
            if action == "environment":
                payload = self.environment()
            elif action == "devices":
                payload = self.devices()
            else:
                payload = self.inspect(request["deviceID"], request.get("transport"))
            return wire_response(request, status="ok", payload=payload)
        except BridgeError as error:
            return wire_response(request, status="error", code=error.code)
        except Exception:
            return wire_response(request, status="error", code="operation-failed")


def _validate_request(request: Any) -> str:
    if not isinstance(request, dict):
        raise BridgeError("invalid-request")
    wire_request_id(request)
    action = wire_action(request)
    if action not in {"environment", "devices", "inspect"}:
        raise BridgeError("invalid-request")
    allowed = {"requestID", "action"}
    if action in {"inspect"}:
        allowed.add("deviceID")
        target = request.get("deviceID")
        if _normalized_udid(target) is None:
            raise BridgeError("invalid-request")
        if "transport" in request:
            allowed.add("transport")
            if not isinstance(request["transport"], str) or request["transport"] not in {"usb", "wifi"}:
                raise BridgeError("invalid-request")
    if set(request) - allowed:
        raise BridgeError("invalid-request")
    return action


def _map_error(code: Any) -> str:
    mapping = {
        "no-usb-device": "device-disconnected",
        "target-device-not-found": "device-disconnected",
        "usb-device-list-failed": "operation-failed",
        "usb-lockdown-failed": "trust-required",
        "device-values-unavailable": "trust-required",
        "device-identity-unavailable": "identity-mismatch",
        "device-identity-mismatch": "identity-mismatch",
        "unsupported-os-version": "unsupported-os",
        "runtime-import-unavailable": "runtime-unavailable",
        "runtime-version-mismatch": "dependency-mismatch",
    }
    mapped = mapping.get(str(code), "operation-failed")
    return mapped if mapped in SAFE_ERROR_CODES else "operation-failed"


def establish_process_group() -> None:
    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise BridgeError("environment-not-ready")


def _setup_error_payload(request: Any, config: Any = None) -> dict[str, Any]:
    if config is not None:
        try:
            from Setup.setup_journal import JournalStore
        except ImportError:
            from setup_journal import JournalStore
        try:
            journal = JournalStore(config.state_root).read()
            if isinstance(journal, dict) and (
                getattr(request, "setup_id", None) is None or journal.get("setupID") == request.setup_id
            ) and (
                getattr(request, "device_id", None) is None or journal.get("deviceID") == request.device_id
            ):
                stages = journal.get("stages", {})
                mode = journal.get("mode", "install")
                order = ("artifact", "install", "complete") if mode == "renew" else (
                    "artifact", "pairing", "install", "support", "handoff", "complete"
                )
                current, outcome = "complete", "confirmed"
                for stage in order:
                    state = stages.get(stage, {}).get("state")
                    if state in {"unknown", "inflight"}:
                        current, outcome = stage, "unknown"
                        break
                    if state != "confirmed":
                        current, outcome = stage, "inProgress"
                        break
                proof = journal.get("proof", {})
                if current == "complete" and outcome == "confirmed" and not (
                    proof.get("installationConfirmed") is True
                    and (mode == "renew" or (
                        proof.get("pairingImported") is True and proof.get("supportObserved") is True
                    ))
                    and isinstance(journal.get("receiptSHA256"), str)
                    and re.fullmatch(r"[0-9a-f]{64}", journal["receiptSHA256"]) is not None
                ):
                    outcome = "unknown"
                delivery_state = journal.get("delivery", {}).get("state")
                payload: dict[str, Any] = {
                    "stage": current, "outcome": outcome,
                    "canResume": outcome != "confirmed" and delivery_state not in {"inflight", "unknown"},
                    "proof": {
                        "installationConfirmed": proof.get("installationConfirmed") is True,
                        "pairingImported": proof.get("pairingImported") is True,
                        "supportObserved": proof.get("supportObserved") is True,
                    },
                }
                artifact = journal.get("intent", {}).get("artifact")
                if isinstance(artifact, dict):
                    payload["app"] = {
                        "bundleID": artifact.get("bundleID"), "build": artifact.get("build"),
                        "profileSHA256": artifact.get("profileSHA256"),
                        "executableSHA256": artifact.get("executableSHA256"),
                    }
                    payload["teamID"] = journal.get("intent", {}).get("teamID")
                    payload["expiresAt"] = artifact.get("expiresAt")
                receipt = journal.get("receiptSHA256")
                if isinstance(receipt, str) and re.fullmatch(r"[0-9a-f]{64}", receipt) is not None:
                    payload["receiptSHA256"] = receipt
                return payload
        except Exception:
            pass
    action = getattr(request, "action", None)
    stage = action if action in {"preflight", "artifact", "pairing", "install", "support", "handoff"} else "preflight"
    return {"stage": stage, "outcome": "unknown", "canResume": stage != "preflight" and action not in {"status", "resume"},
            "proof": {"installationConfirmed": False, "pairingImported": False, "supportObserved": False}}


def _setup_response(value: Mapping[str, Any], config_path: Path, *, producer_factory: Any = None) -> dict[str, Any]:
    try:
        from Setup.setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
        from Setup.setup_config import SetupConfiguration
        from Setup.setup_producer import SetupProducer
        from Setup.setup_protocol import decode_request
        from Setup.setup_support import PinnedSupportAdapter
    except ImportError:
        from setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
        from setup_config import SetupConfiguration
        from setup_producer import SetupProducer
        from setup_protocol import decode_request
        from setup_support import PinnedSupportAdapter
    config = None
    request = None
    try:
        config = SetupConfiguration.load(config_path)
        config.validate_read_only_paths()
        request = decode_request(value)
        if producer_factory is not None:
            producer = producer_factory(config)
        else:
            device = PinnedPymobiledeviceAdapter(state_root=config.state_root)
            producer = SetupProducer(config, device=device, process=PinnedXcodeProcessAdapter(config),
                                     support=PinnedSupportAdapter(device))
        payload = producer.handle(request).as_dict()
        from Setup.setup_protocol import _response_payload
        if request.action == "status" and request.setup_id is None:
            journal = __import__("Setup.setup_journal", fromlist=["JournalStore"]).JournalStore(config.state_root).read()
            if isinstance(journal, dict):
                value = dict(value)
                value["setupID"] = journal.get("setupID")
                value["deviceID"] = journal.get("deviceID")
                value["mode"] = journal.get("mode", "install")
        return wire_response(value, status="ok", payload=_response_payload(payload))
    except WireError as error:
        return wire_response(value, status="error", code=error.code, payload=_setup_error_payload(request, config))
    except Exception:
        return wire_response(value, status="error", code="operation-failed", payload=_setup_error_payload(request, config))
    finally:
        try:
            close_async_runtime()
        except Exception:
            pass


def run_stdio(config_path: str | Path, *, stdin: Any = None, setup_producer_factory: Any = None,
              producer_factory: Any = None) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    setup_producer_factory = setup_producer_factory or producer_factory
    try:
        value = parse_object(read_request(stream))
        action = wire_action(value)
    except WireError as error:
        return wire_response(None, status="error", code=error.code)
    if action in {"environment", "devices", "inspect"}:
        try:
            _validate_request(value)
            return Bridge(Config.load(config_path)).handle(value)
        except WireError as error:
            return wire_response(value, status="error", code=error.code)
        except Exception:
            return wire_response(value, status="error", code="operation-failed")
    if action in {"preflight", "apply", "status", "resume"}:
        return _setup_response(value, Path(config_path), producer_factory=setup_producer_factory)
    return wire_response(value, status="error", code="invalid-request")


def _emit(response: dict[str, Any], stream: Any = None) -> None:
    try:
        wire_emit(response, stream)
    except WireError:
        wire_emit(wire_response(None, status="error", code="operation-failed"), stream)


def main(argv: list[str] | None = None) -> int:
    # The Swift caller terminates the process group on cancellation.  Failure
    # to create a new group is harmless in an embedded test process.
    try:
        establish_process_group()
    except BridgeError as error:
        _emit(wire_response(None, status="error", code=error.code))
        return 1
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--config", required=True)
    try:
        arguments, _ = parser.parse_known_args(argv)
    except SystemExit:
        return 2
    response = run_stdio(arguments.config)
    _emit(response)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
