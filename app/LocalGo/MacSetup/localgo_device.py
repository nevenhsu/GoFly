"""USB-only device inspection and LocalGo remote pairing.

This module deliberately keeps the pymobiledevice3 boundary small.  The CLI
owns presentation and application installation; this module only returns
structured values and fixed, safe error codes.  In particular, no dependency
exception, pairing record, key, or device identifier is logged here.
"""

from __future__ import annotations

import asyncio
import contextlib
import dataclasses
import importlib
import importlib.metadata
import inspect
import logging
import os
import plistlib
import re
import stat
import tempfile
import uuid
from collections.abc import Mapping
from pathlib import Path
from typing import Any, Final


PMD3_REQUIRED_VERSION: Final[str] = "11.31.0"
USB_CONNECTION_TYPE: Final[str] = "USB"
LOCALGO_LABEL: Final[str] = "LocalGo Setup"
PAIR_TIMEOUT_SECONDS: Final[int] = 60
PAIRING_RECORD_MAX_BYTES: Final[int] = 1024 * 1024
PRODUCT_VERSION_MAJOR: Final[int] = 26
DEVELOPER_MODE_DOMAIN: Final[str] = "com.apple.security.mac.amfi"
DEVELOPER_MODE_KEY: Final[str] = "DeveloperModeStatus"
WIFI_DEBUGGING_DOMAIN: Final[str] = "com.apple.mobile.wireless_lockdown"
WIFI_DEBUGGING_KEY: Final[str] = "EnableWifiDebugging"


class LocalGoSetupError(Exception):
    """A safe error which can cross the CLI boundary.

    ``message`` is intentionally fixed text.  Callers should expose ``code``
    to users and never format an arbitrary dependency exception.
    """

    def __init__(self, code: str, message: str | None = None) -> None:
        if not re.fullmatch(r"[a-z][a-z0-9-]{1,80}", code):
            code = "setup-failed"
        self.code = code
        self.message = message or code
        super().__init__(self.message)

    def __str__(self) -> str:
        return self.message


# Keep both names available while the CLI and tests settle on the public name.
SetupError = LocalGoSetupError


@dataclasses.dataclass(frozen=True)
class DeviceTarget:
    """Safe subset of device values needed by the setup flow."""

    udid: str
    os_version: str
    developer_mode: bool
    wifi_debugging: bool
    # pymobiledevice3 matches the transport serial case-sensitively.  Keep
    # that spelling for subsequent lockdown opens while exposing only the
    # normalized identifier through the public result.
    transport_serial: str | None = dataclasses.field(default=None, repr=False, compare=False)

    def __getitem__(self, key: str) -> Any:
        return getattr(self, key)


@dataclasses.dataclass(frozen=True)
class PairingResult:
    """The verified remote pairing record returned to the setup CLI."""

    udid: str
    os_version: str
    pairing_data: bytes


# These names are intentionally module globals.  They make the dependency
# seam straightforward to mock without importing the optional dependency in a
# system Python used only for read-only CLI commands.
try:  # pragma: no cover - exercised by the configured setup environment
    from pymobiledevice3 import lockdown as lockdown  # type: ignore[assignment]
    from pymobiledevice3 import usbmux as usbmux  # type: ignore[assignment]
    from pymobiledevice3.remote import tunnel_service as tunnel_service  # type: ignore[assignment]
except Exception:  # pragma: no cover - tested through compatibility failure
    lockdown = None  # type: ignore[assignment]
    usbmux = None  # type: ignore[assignment]
    tunnel_service = None  # type: ignore[assignment]

try:  # pragma: no cover - exercised by the configured setup environment
    from pymobiledevice3.exceptions import RemotePairingCompletedError
except Exception:  # pragma: no cover - compatibility failure path
    class RemotePairingCompletedError(Exception):
        pass


def _safe_error(code: str, message: str | None = None) -> LocalGoSetupError:
    return LocalGoSetupError(code, message)


def _load_dependencies() -> tuple[Any, Any, Any]:
    """Load pymobiledevice3 lazily and never expose import details."""

    global lockdown, usbmux, tunnel_service, RemotePairingCompletedError
    if lockdown is None or usbmux is None or tunnel_service is None:
        try:
            lockdown = importlib.import_module("pymobiledevice3.lockdown")
            usbmux = importlib.import_module("pymobiledevice3.usbmux")
            tunnel_service = importlib.import_module("pymobiledevice3.remote.tunnel_service")
            exceptions = importlib.import_module("pymobiledevice3.exceptions")
            RemotePairingCompletedError = getattr(exceptions, "RemotePairingCompletedError")
        except Exception:
            raise _safe_error("runtime-import-unavailable") from None
    return usbmux, lockdown, tunnel_service


def _dependency_version() -> str:
    try:
        return importlib.metadata.version("pymobiledevice3")
    except Exception:
        try:
            module = importlib.import_module("pymobiledevice3")
            return str(getattr(module, "__version__"))
        except Exception:
            return ""


def _require_parameters(function: Any, names: set[str]) -> None:
    try:
        signature = inspect.signature(function)
    except (TypeError, ValueError):
        raise _safe_error("runtime-api-mismatch") from None
    parameters = signature.parameters
    # A **kwargs-only shim is not an accepted API: it could silently discard
    # one of the security-sensitive options below.
    if any(name not in parameters for name in names):
        raise _safe_error("runtime-api-mismatch")
    for name in names:
        parameter = parameters[name]
        if parameter.kind in (inspect.Parameter.POSITIONAL_ONLY, inspect.Parameter.VAR_POSITIONAL):
            raise _safe_error("runtime-api-mismatch")


def _require_callable(owner: Any, name: str) -> Any:
    function = getattr(owner, name, None)
    if not callable(function):
        raise _safe_error("runtime-api-mismatch")
    return function


def check_compatibility() -> None:
    """Fail closed if the pinned dependency or required API has changed."""

    usbmux_module, lockdown_module, tunnel_module = _load_dependencies()
    if _dependency_version() != PMD3_REQUIRED_VERSION:
        raise _safe_error("runtime-version-mismatch")

    _require_parameters(usbmux_module.list_devices, {"usbmux_address"})
    _require_parameters(
        lockdown_module.create_using_usbmux,
        {
            "serial",
            "label",
            "autopair",
            "connection_type",
            "pair_timeout",
            "pairing_records_cache_folder",
        },
    )

    remote = getattr(tunnel_module, "RemotePairingLockdownService", None)
    if remote is None:
        raise _safe_error("runtime-api-mismatch")
    if getattr(remote, "SERVICE_NAME", None) != "com.apple.dt.remotepairingdeviced.lockdown":
        raise _safe_error("runtime-api-mismatch")
    _require_parameters(remote.__init__, {"service", "remote_identifier"})
    _require_parameters(_require_callable(remote, "create"), {"lockdown"})
    _require_parameters(_require_callable(remote, "connect"), {"autopair"})
    _require_parameters(_require_callable(remote, "_attempt_pair_verify"), set())
    _require_parameters(_require_callable(remote, "_validate_pairing"), set())
    _require_callable(remote, "_pair")
    _require_callable(remote, "close")
    if not isinstance(getattr(remote, "pair_record_path", None), property):
        raise _safe_error("runtime-api-mismatch")
    _require_callable(remote, "save_pair_record")


@contextlib.contextmanager
def _silence_dependency_logs():
    """Prevent dependency loggers from exposing raw pairing protocol data."""

    previous = logging.root.manager.disable
    logging.disable(logging.CRITICAL)
    try:
        yield
    finally:
        logging.disable(previous)


@contextlib.contextmanager
def _private_umask():
    previous = os.umask(0o077)
    try:
        yield
    finally:
        os.umask(previous)


def _normalized_udid(value: Any) -> str:
    if not isinstance(value, str):
        raise _safe_error("invalid-device-identifier")
    value = value.strip().lower()
    # Keep the comparison exact after lowercase normalization.  Do not remove
    # punctuation: a different textual identifier must never be accepted.
    if not re.fullmatch(r"[0-9a-f]{40}", value) and not re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{16}", value
    ):
        raise _safe_error("invalid-device-identifier")
    return value


def _device_value(device: Any, *names: str) -> Any:
    if isinstance(device, Mapping):
        for name in names:
            if name in device:
                return device[name]
    for name in names:
        try:
            return getattr(device, name)
        except Exception:
            continue
    return None


def _device_is_usb(device: Any) -> bool:
    connection = _device_value(device, "connection_type", "ConnectionType", "connectionType")
    if isinstance(connection, str):
        return connection.strip().upper() == USB_CONNECTION_TYPE
    usb = _device_value(device, "is_usb", "isUSB")
    return usb is True


def _device_transport_serial(device: Any) -> str | None:
    serial = _device_value(device, "serial", "SerialNumber", "UDID", "udid", "unique_device_id")
    if not isinstance(serial, str):
        return None
    serial = serial.strip()
    try:
        _normalized_udid(serial)
    except LocalGoSetupError:
        return None
    return serial


def _device_serial(device: Any) -> str | None:
    serial = _device_transport_serial(device)
    if serial is None:
        return None
    return _normalized_udid(serial)


def _ensure_private_directory(path: Path) -> Path:
    path = Path(path)
    try:
        if path.is_symlink():
            raise _safe_error("unsafe-state-directory")
        previous_umask = os.umask(0o077)
        try:
            path.mkdir(parents=True, exist_ok=True, mode=0o700)
        finally:
            os.umask(previous_umask)
        st = path.lstat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
            # Tightening an existing private directory is safe and avoids
            # leaving records readable when a caller created the directory.
            if stat.S_IMODE(st.st_mode) & 0o077:
                path.chmod(0o700)
                st = path.lstat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
            raise _safe_error("unsafe-state-directory")
    except LocalGoSetupError:
        raise
    except (OSError, ValueError):
        raise _safe_error("unsafe-state-directory") from None
    return path


def _assert_private_regular_file(path: Path) -> None:
    try:
        st = path.lstat()
    except FileNotFoundError:
        return
    except OSError:
        raise _safe_error("unsafe-pairing-record") from None
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid():
        raise _safe_error("unsafe-pairing-record")
    if st.st_size > PAIRING_RECORD_MAX_BYTES:
        raise _safe_error("pairing-record-too-large")
    try:
        if stat.S_IMODE(st.st_mode) & 0o077:
            path.chmod(0o600)
    except OSError:
        raise _safe_error("unsafe-pairing-record") from None


def _atomic_private_write(path: Path, data: bytes) -> None:
    parent = _ensure_private_directory(path.parent)
    _assert_private_regular_file(path)
    fd = -1
    temporary: Path | None = None
    previous_umask = os.umask(0o077)
    try:
        fd, temporary_name = tempfile.mkstemp(prefix=".localgo-pair-", dir=str(parent))
        temporary = Path(temporary_name)
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=True) as stream:
            fd = -1
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # Recheck a destination symlink immediately before replacing it.  A
        # replacement never follows a symlink, but rejecting one is the
        # fail-closed behavior required for a private key file.
        _assert_private_regular_file(path)
        os.replace(temporary, path)
        temporary = None
        os.chmod(path, 0o600)
    except LocalGoSetupError:
        raise
    except (OSError, ValueError):
        raise _safe_error("pairing-record-write-failed") from None
    finally:
        os.umask(previous_umask)
        if fd >= 0:
            with contextlib.suppress(OSError):
                os.close(fd)
        if temporary is not None:
            with contextlib.suppress(OSError):
                temporary.unlink()


def _record_path(state_dir: Path, udid: str) -> Path:
    return _ensure_private_directory(state_dir) / f"remote_{udid}.plist"


def _record_from_bytes(data: bytes) -> dict[str, Any]:
    if not data or len(data) > PAIRING_RECORD_MAX_BYTES:
        raise _safe_error("invalid-pairing-record")
    try:
        value = plistlib.loads(data)
    except Exception:
        raise _safe_error("invalid-pairing-record") from None
    if not isinstance(value, dict):
        raise _safe_error("invalid-pairing-record")
    private_key = value.get("private_key")
    public_key = value.get("public_key")
    identifier = value.get("host_identifier") or value.get("identifier")
    if not isinstance(private_key, bytes) or len(private_key) != 32:
        raise _safe_error("invalid-pairing-record")
    if not isinstance(public_key, bytes) or len(public_key) != 32:
        raise _safe_error("invalid-pairing-record")
    if not isinstance(identifier, str):
        raise _safe_error("invalid-pairing-record")
    try:
        uuid.UUID(identifier)
    except (ValueError, AttributeError, TypeError):
        raise _safe_error("invalid-pairing-record") from None
    alt_irk = value.get("alt_irk")
    if alt_irk is not None and (not isinstance(alt_irk, bytes) or len(alt_irk) != 16):
        raise _safe_error("invalid-pairing-record")
    # Check the public key against the private key.  cryptography is already a
    # pymobiledevice3 dependency; import only after the record shape is known.
    try:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

        expected_public = Ed25519PrivateKey.from_private_bytes(private_key).public_key().public_bytes_raw()
    except Exception:
        raise _safe_error("invalid-pairing-record") from None
    if expected_public != public_key:
        raise _safe_error("invalid-pairing-record")
    return value


def _read_record(path: Path) -> tuple[dict[str, Any], bytes]:
    _assert_private_regular_file(path)
    try:
        data = path.read_bytes()
    except OSError:
        raise _safe_error("pairing-record-read-failed") from None
    return _record_from_bytes(data), data


def _fresh_pair_path(path: Path) -> Path:
    # Keep temporary pairing data in the same private directory so os.replace
    # is atomic and never crosses a filesystem boundary.
    return path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")


def _version_is_supported(version: Any) -> bool:
    if not isinstance(version, str):
        return False
    match = re.fullmatch(r"\s*(\d+)(?:\.\d+)*\s*", version)
    return bool(match and int(match.group(1)) >= PRODUCT_VERSION_MAJOR)


async def _close_quietly(value: Any) -> None:
    close = getattr(value, "close", None)
    if not callable(close):
        return
    with contextlib.suppress(Exception):
        result = close()
        if inspect.isawaitable(result):
            await result


async def _list_usb_devices() -> list[Any]:
    usbmux_module, _, _ = _load_dependencies()
    try:
        with _silence_dependency_logs():
            result = usbmux_module.list_devices()
            if inspect.isawaitable(result):
                result = await result
    except LocalGoSetupError:
        raise
    except Exception:
        raise _safe_error("usb-device-list-failed") from None
    if not isinstance(result, list):
        raise _safe_error("runtime-api-mismatch")
    return result


async def inspect_devices() -> list[dict[str, str]]:
    """Return normalized identifiers for currently attached USB devices."""

    check_compatibility()
    devices = await _list_usb_devices()
    result: list[dict[str, str]] = []
    for device in devices:
        if not _device_is_usb(device):
            continue
        serial = _device_serial(device)
        if serial is not None:
            result.append({"udid": serial})
    return result


def _find_target(devices: list[Any], udid: str) -> tuple[Any, str]:
    usb_seen = False
    for device in devices:
        if not _device_is_usb(device):
            continue
        usb_seen = True
        transport_serial = _device_transport_serial(device)
        if transport_serial is not None and _normalized_udid(transport_serial) == udid:
            return device, transport_serial
    if not usb_seen:
        raise _safe_error("no-usb-device")
    raise _safe_error("target-device-not-found")


async def _open_usb_lockdown(udid: str, cache: Path, *, autopair: bool) -> Any:
    _, lockdown_module, _ = _load_dependencies()
    try:
        with _private_umask(), _silence_dependency_logs():
            client = lockdown_module.create_using_usbmux(
                serial=udid,
                connection_type=USB_CONNECTION_TYPE,
                pairing_records_cache_folder=cache,
                autopair=autopair,
                pair_timeout=PAIR_TIMEOUT_SECONDS,
                label=LOCALGO_LABEL,
            )
            if inspect.isawaitable(client):
                client = await client
    except LocalGoSetupError:
        raise
    except Exception:
        raise _safe_error("usb-lockdown-failed") from None
    return client


async def _device_values(
    client: Any,
    udid: str,
    *,
    require_developer: bool,
    transport_serial: str | None = None,
) -> DeviceTarget:
    get_value = getattr(client, "get_value", None)
    if not callable(get_value):
        raise _safe_error("runtime-api-mismatch")
    try:
        with _silence_dependency_logs():
            values = get_value()
            if inspect.isawaitable(values):
                values = await values
            developer = get_value(domain=DEVELOPER_MODE_DOMAIN, key=DEVELOPER_MODE_KEY)
            if inspect.isawaitable(developer):
                developer = await developer
            wifi = get_value(domain=WIFI_DEBUGGING_DOMAIN, key=WIFI_DEBUGGING_KEY)
            if inspect.isawaitable(wifi):
                wifi = await wifi
    except Exception:
        raise _safe_error("device-values-unavailable") from None
    if not isinstance(values, Mapping):
        raise _safe_error("device-values-unavailable")
    actual = values.get("UniqueDeviceID")
    try:
        actual = _normalized_udid(actual)
    except LocalGoSetupError:
        raise _safe_error("device-identity-unavailable") from None
    if actual != udid:
        raise _safe_error("device-identity-mismatch")
    version = values.get("ProductVersion")
    if not _version_is_supported(version):
        raise _safe_error("unsupported-os-version")
    if require_developer and developer is not True:
        raise _safe_error("developer-mode-required")
    return DeviceTarget(
        udid=actual,
        os_version=str(version),
        developer_mode=developer is True,
        wifi_debugging=wifi is True,
        transport_serial=transport_serial,
    )


async def inspect_target(udid: str) -> DeviceTarget:
    """Perform a read-only USB, identity, OS, and developer-mode preflight."""

    check_compatibility()
    normalized = _normalized_udid(udid)
    devices = await _list_usb_devices()
    _, transport_serial = _find_target(devices, normalized)
    # A temporary private cache prevents pymobiledevice3 from falling back to
    # the user's home pairing directory during a read-only preflight.
    with tempfile.TemporaryDirectory(prefix="localgo-preflight-") as temporary:
        cache = _ensure_private_directory(Path(temporary))
        client = await _open_usb_lockdown(transport_serial, cache, autopair=False)
        try:
            return await _device_values(
                client,
                normalized,
                require_developer=True,
                transport_serial=transport_serial,
            )
        finally:
            await _close_quietly(client)


async def _enable_wifi_debugging(client: Any) -> None:
    setter = getattr(client, "set_value", None)
    getter = getattr(client, "get_value", None)
    if not callable(setter) or not callable(getter):
        raise _safe_error("runtime-api-mismatch")
    try:
        with _silence_dependency_logs():
            result = setter(True, domain=WIFI_DEBUGGING_DOMAIN, key=WIFI_DEBUGGING_KEY)
            if inspect.isawaitable(result):
                await result
            value = getter(domain=WIFI_DEBUGGING_DOMAIN, key=WIFI_DEBUGGING_KEY)
            if inspect.isawaitable(value):
                value = await value
    except Exception:
        raise _safe_error("wifi-debugging-unsupported") from None
    if value is not True:
        raise _safe_error("wifi-debugging-unsupported")


class LocalGoRemotePairingLockdownService:  # replaced below when pmd3 is available
    pass


def _build_pairing_service_class() -> type[Any]:
    _, _, tunnel_module = _load_dependencies()
    base = getattr(tunnel_module, "RemotePairingLockdownService", None)
    if base is None:
        raise _safe_error("runtime-api-mismatch")

    class _LocalGoRemotePairingLockdownService(base):
        def __init__(
            self,
            service: Any,
            remote_identifier: str,
            pair_record_path: Path | None = None,
            *,
            record_path: Path | None = None,
        ) -> None:
            if pair_record_path is None:
                pair_record_path = record_path
            if pair_record_path is None:
                raise _safe_error("pairing-record-path-required")
            super().__init__(service, remote_identifier)
            self._local_pair_record_path = Path(pair_record_path)
            self._last_pair_verified = False
            self._pair_record_cache: dict[str, Any] | None = None
            if self._local_pair_record_path.exists():
                record, _ = _read_record(self._local_pair_record_path)
                self._pair_record_cache = record
                self._load_identity(record)
            else:
                self.identifier = str(uuid.uuid4())

        def _load_identity(self, record: dict[str, Any]) -> None:
            try:
                from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

                self.ed25519_private_key = Ed25519PrivateKey.from_private_bytes(record["private_key"])
            except Exception:
                raise _safe_error("invalid-pairing-record") from None
            self.identifier = str(record.get("host_identifier") or record.get("identifier"))

        @classmethod
        async def create(
            cls,
            lockdown_client: Any,
            pair_record_path: Path | None = None,
            *,
            record_path: Path | None = None,
        ) -> Any:
            if pair_record_path is None:
                pair_record_path = record_path
            if pair_record_path is None:
                raise _safe_error("pairing-record-path-required")
            service_name = getattr(cls, "SERVICE_NAME", "com.apple.dt.remotepairingdeviced.lockdown")
            udid = getattr(lockdown_client, "udid", None)
            starter = getattr(lockdown_client, "start_lockdown_service", None)
            if not isinstance(udid, str) or not callable(starter):
                raise _safe_error("remote-service-unavailable")
            try:
                service = starter(service_name)
                if inspect.isawaitable(service):
                    service = await service
            except Exception:
                raise _safe_error("remote-service-unavailable") from None
            return cls(service, udid, Path(pair_record_path))

        @property
        def pair_record_path(self) -> Path:
            return self._local_pair_record_path

        @property
        def pair_record(self) -> dict[str, Any] | None:
            if self._pair_record_cache is not None:
                return self._pair_record_cache
            if not self._local_pair_record_path.exists():
                return None
            self._pair_record_cache, _ = _read_record(self._local_pair_record_path)
            return self._pair_record_cache

        def save_pair_record(self) -> None:
            try:
                public_key = self.ed25519_private_key.public_key().public_bytes_raw()
                private_key = self.ed25519_private_key.private_bytes_raw()
            except Exception:
                raise _safe_error("pairing-record-invalid") from None
            if len(public_key) != 32 or len(private_key) != 32:
                raise _safe_error("pairing-record-invalid")
            identifier = getattr(self, "identifier", None)
            try:
                uuid.UUID(str(identifier))
            except (ValueError, AttributeError, TypeError):
                raise _safe_error("pairing-record-invalid") from None
            record: dict[str, Any] = {
                "public_key": public_key,
                "private_key": private_key,
                "identifier": str(identifier),
                "host_identifier": str(identifier),
            }
            alt_irk = getattr(self, "peer_alt_irk", None)
            if alt_irk is not None:
                if not isinstance(alt_irk, bytes) or len(alt_irk) != 16:
                    raise _safe_error("pairing-record-invalid")
                record["alt_irk"] = alt_irk
            data = plistlib.dumps(record, fmt=plistlib.FMT_XML, sort_keys=True)
            _atomic_private_write(self._local_pair_record_path, data)
            self._pair_record_cache = record

        async def connect(self, autopair: bool = True) -> None:
            # Do not delegate to the dependency's connect method: its
            # autopair=False path intentionally returns after a failed verify.
            await self._attempt_pair_verify()
            verified = await self._validate_pairing()
            self._last_pair_verified = verified is True
            if self._last_pair_verified:
                initialize_keys = getattr(self, "_init_client_server_main_encryption_keys", None)
                if callable(initialize_keys):
                    initialize_keys()
                return
            if autopair:
                await self._pair()
                await self.close()
                raise RemotePairingCompletedError()

    return _LocalGoRemotePairingLockdownService


def _pairing_service_class() -> type[Any]:
    # Rebuild after a test replaces the dependency module, while keeping the
    # public class name useful for callers that import it directly.
    return _build_pairing_service_class()


async def _verify_remote_service(service: Any, *, autopair: bool) -> bool:
    try:
        with _silence_dependency_logs():
            await service.connect(autopair=autopair)
    except RemotePairingCompletedError:
        raise
    except LocalGoSetupError:
        raise
    except Exception:
        raise _safe_error("remote-pairing-failed") from None
    return getattr(service, "_last_pair_verified", False) is True


async def pair_device(udid: str, state_dir: Path, repair: bool = False) -> PairingResult:
    """Pair one trusted USB device and return a verified private RP record."""

    check_compatibility()
    normalized = _normalized_udid(udid)
    # This is deliberately repeated inside the mutating operation so a caller
    # cannot bypass the USB/OS/developer-mode gate by calling pair_device.
    target = await inspect_target(normalized)
    root = _ensure_private_directory(Path(state_dir))
    pair_path = _record_path(root, normalized)
    existing = pair_path.exists()
    if existing:
        _read_record(pair_path)
    if repair and existing:
        working_path = _fresh_pair_path(pair_path)
    elif existing:
        working_path = pair_path
    else:
        # A first pairing must never publish an unverified record.  Keep all
        # generated keys in a sibling temporary file until the fresh USB
        # session has completed an explicit bool verification.
        working_path = _fresh_pair_path(pair_path)

    client: Any = None
    remote: Any = None
    try:
        transport_serial = target.transport_serial or normalized
        client = await _open_usb_lockdown(transport_serial, root, autopair=True)
        live_target = await _device_values(
            client,
            normalized,
            require_developer=True,
            transport_serial=transport_serial,
        )
        if live_target.os_version != target.os_version:
            raise _safe_error("device-changed-during-setup")
        await _enable_wifi_debugging(client)
        service_class = _pairing_service_class()
        remote = await service_class.create(client, working_path)

        if existing and not repair:
            verified = await _verify_remote_service(remote, autopair=False)
            if not verified:
                raise _safe_error("remote-pairing-verification-failed")
            await _close_quietly(remote)
            remote = None
            await _close_quietly(client)
            client = None
            _, data = _read_record(pair_path)
            return PairingResult(normalized, target.os_version, data)

        # New pairing and explicit repair both use a temporary path.  Existing
        # records remain untouched until a fresh USB session verifies the new
        # identity.
        try:
            await _verify_remote_service(remote, autopair=True)
        except RemotePairingCompletedError:
            pass
        await _close_quietly(remote)
        remote = None
        await _close_quietly(client)
        client = None

        # A completed remote pairing closes its control channel.  Reopen USB,
        # create a fresh control service, and require explicit bool verification
        # before moving the temporary record into place.
        client = await _open_usb_lockdown(transport_serial, root, autopair=True)
        await _device_values(
            client,
            normalized,
            require_developer=True,
            transport_serial=transport_serial,
        )
        remote = await service_class.create(client, working_path)
        verified = await _verify_remote_service(remote, autopair=False)
        if not verified:
            raise _safe_error("remote-pairing-verification-failed")
        await _close_quietly(remote)
        remote = None
        await _close_quietly(client)
        client = None

        _assert_private_regular_file(working_path)
        _, data = _read_record(working_path)
        if working_path != pair_path:
            if pair_path.exists() or pair_path.is_symlink():
                _assert_private_regular_file(pair_path)
            os.replace(working_path, pair_path)
            os.chmod(pair_path, 0o600)
            data = pair_path.read_bytes()
        return PairingResult(normalized, target.os_version, data)
    except LocalGoSetupError:
        raise
    except RemotePairingCompletedError:
        # The expected completion exception is handled around the first pair;
        # reaching this boundary means the follow-up verification was absent.
        raise _safe_error("remote-pairing-verification-failed") from None
    except Exception:
        raise _safe_error("pairing-failed") from None
    finally:
        await _close_quietly(remote)
        await _close_quietly(client)
        if working_path != pair_path and working_path.exists():
            with contextlib.suppress(OSError):
                working_path.unlink()


# Export a useful class object in the configured environment.  This is best
# effort at import time; compatibility is still checked before any operation.
try:  # pragma: no cover - exercised by normal imports
    if tunnel_service is not None:
        LocalGoRemotePairingLockdownService = _build_pairing_service_class()
except Exception:
    pass


__all__ = [
    "DeviceTarget",
    "LocalGoRemotePairingLockdownService",
    "LocalGoSetupError",
    "PairingResult",
    "SetupError",
    "check_compatibility",
    "inspect_devices",
    "inspect_target",
    "pair_device",
]
