"""Transport-pinned preparation primitives for the M3 management bridge.

This module is deliberately smaller than the first-install producer.  It
reuses the real M1 AFC, pairing, support, formal-input, readback, and DVT
primitives through a private adapter whose transport is selected by the M3
device adapter.  It never opens an M1 journal or claims installation proof.
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib
import json
import plistlib
import re
import tempfile
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path
from typing import TYPE_CHECKING, Any, Callable, Iterator, Mapping, TypeVar

try:
    from ..Setup.setup_adapters import (
        FormalSetupInput,
        PinnedPymobiledeviceAdapter,
        _RemoteMissing,
        _is_remote_missing,
        _read_private_regular,
        _run,
    )
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device
    from .management_adapters import PinnedManagementDeviceAdapter
    from .management_protocol import ManagementBridgeError, TEAM_RE, _expiry, _validate_app
    from .management_source import PreparationAppIdentity
except ImportError:  # direct execution from the packaged Bridge root
    from Setup.setup_adapters import (
        FormalSetupInput,
        PinnedPymobiledeviceAdapter,
        _RemoteMissing,
        _is_remote_missing,
        _read_private_regular,
        _run,
    )
    from Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device
    from Management.management_adapters import PinnedManagementDeviceAdapter
    from Management.management_protocol import ManagementBridgeError, TEAM_RE, _expiry, _validate_app
    from Management.management_source import PreparationAppIdentity

if TYPE_CHECKING:
    from .management_lineage import ManagementGeneration


MAX_MANAGEMENT_REQUEST_BYTES = 32 * 1024
MAX_MANAGEMENT_RESPONSE_BYTES = 64 * 1024
MAX_MANAGEMENT_CONTROL_BYTES = 4 * 1024
MAX_PAIRING_BYTES = 1024 * 1024
MAX_PAIRING_ENVELOPE_BYTES = 1024 * 1024 + 64 * 1024

_LOGICAL_FILES: dict[str, tuple[str, int]] = {
    "managementRequest": ("Library/Application Support/GoFlyManagement/request.json", 32 * 1024),
    "managementRoot": ("Library/Application Support/GoFlyManagement/root.json", 512 * 1024),
    "managementResponse": ("Library/Application Support/GoFlyManagement/response.json", 64 * 1024),
    "managementControl": ("Library/Application Support/GoFlyManagement/control-request.json", MAX_MANAGEMENT_CONTROL_BYTES),
    "restoreIntent": ("Library/Application Support/GoFlyTransfer/restore-intent.json", 256 * 1024),
    "restoreRoot": ("Library/Application Support/GoFlyTransfer/restore-root.json", 1024 * 1024),
    "setupIncoming": ("Library/Application Support/GoFlySetup/incoming.json", 256 * 1024),
    "setupReadbackRequest": ("Library/Application Support/GoFlySetup/readback-request.json", 64 * 1024),
    "setupReadbackResponse": ("Library/Application Support/GoFlySetup/readback-response.json", 64 * 1024),
}
_LEGACY_FILES = {
    "setupIncoming": _LOGICAL_FILES["setupIncoming"],
    "setupReadbackRequest": _LOGICAL_FILES["setupReadbackRequest"],
    "setupReadbackResponse": _LOGICAL_FILES["setupReadbackResponse"],
}
_UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
_UDID_RE = re.compile(r"(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})\Z")
_HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
_CORE_REQUEST_KEYS = {
    "version", "managementID", "nonce", "kind", "expectedDeviceUDID", "sourceSetupID",
    "sourceApp", "sourceActivationSHA256", "sourceRestoreRootSHA256", "teamID",
    "targetSetupID", "targetApp",
}
_RELEASED_RESPONSE_KEYS = {
    "version", "managementID", "nonce", "requestSHA256", "phase", "pid", "app",
    "sourceSetupID", "activationSHA256", "restoreRootSHA256",
}
_ADOPTED_RESPONSE_KEYS = {
    "version", "managementID", "nonce", "requestSHA256", "sourceSetupID", "targetSetupID",
    "sourceApp", "targetApp", "expectedDeviceUDID", "teamID", "sourceActivationSHA256",
    "sourceRestoreRootSHA256", "targetActivationSHA256", "receiptSHA256",
}
_CONTROL_KEYS = {"version", "managementID", "nonce", "requestSHA256", "action"}
_CONTROL_ACTIONS = frozenset({"quiesce", "seal", "release"})
T = TypeVar("T")


def _error(code: str) -> ManagementBridgeError:
    return ManagementBridgeError(code)


def _map_exception(error: BaseException) -> ManagementBridgeError:
    if isinstance(error, ManagementBridgeError):
        return error
    if isinstance(error, SetupBridgeError):
        return ManagementBridgeError(error.code)
    return ManagementBridgeError("operation-failed")


def _strict_object(raw: bytes, *, limit: int) -> dict[str, Any]:
    if not isinstance(raw, bytes) or not raw or len(raw) > limit:
        raise _error("invalid-request")

    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = value
        return result

    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                           parse_float=lambda _value: (_ for _ in ()).throw(ValueError()),
                           parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()))
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError):
        raise _error("invalid-request") from None
    if not isinstance(value, dict):
        raise _error("invalid-request")
    return value


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or _UUID_RE.fullmatch(value) is None:
        raise _error("invalid-request")
    return value


def _hash(value: Any, *, nullable: bool = False) -> str | None:
    if nullable and value is None:
        return None
    if not isinstance(value, str) or _HEX64_RE.fullmatch(value) is None:
        raise _error("invalid-request")
    return value


def _device(value: Any) -> str:
    if not isinstance(value, str) or value != value.lower() or _UDID_RE.fullmatch(value) is None:
        raise _error("invalid-request")
    return value


def _app(value: Any) -> dict[str, str]:
    # Core's helper rejects all Unicode control, format, and surrogate
    # characters (Cc/Cf/Cs), in addition to the byte and field checks.
    try:
        return _validate_app(value, code="invalid-request")
    except ManagementBridgeError:
        raise
    except Exception:
        raise _error("invalid-request") from None


def _validate_management_request(raw: bytes) -> dict[str, Any]:
    value = _strict_object(raw, limit=MAX_MANAGEMENT_REQUEST_BYTES)
    if set(value) != _CORE_REQUEST_KEYS or value.get("version") != 1 or type(value.get("version")) is not int:
        raise _error("invalid-request")
    management_id = _uuid(value.get("managementID"))
    _uuid(value.get("nonce"))
    kind = value.get("kind")
    if not isinstance(kind, str) or kind not in {"renew", "repair"}:
        raise _error("invalid-request")
    device_id = _device(value.get("expectedDeviceUDID"))
    source_setup = _uuid(value.get("sourceSetupID"))
    target_setup = _uuid(value.get("targetSetupID"))
    if source_setup == target_setup:
        raise _error("identity-mismatch")
    source_app = _app(value.get("sourceApp"))
    target_app = _app(value.get("targetApp"))
    if kind == "repair" and source_app != target_app:
        raise _error("identity-mismatch")
    team = value.get("teamID")
    if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
        raise _error("invalid-request")
    _hash(value.get("sourceActivationSHA256"))
    _hash(value.get("sourceRestoreRootSHA256"), nullable=True)
    return {
        "version": 1,
        "managementID": management_id,
        "nonce": value["nonce"],
        "kind": kind,
        "expectedDeviceUDID": device_id,
        "sourceSetupID": source_setup,
        "sourceApp": source_app,
        "sourceActivationSHA256": value["sourceActivationSHA256"],
        "sourceRestoreRootSHA256": value["sourceRestoreRootSHA256"],
        "teamID": team,
        "targetSetupID": target_setup,
        "targetApp": target_app,
    }


def _canonical_adoption_sha256(value: Mapping[str, Any]) -> str:
    """Match ManagementCodec.adoptionDigest's sorted, compact JSON bytes."""
    canonical = {
        key: value[key]
        for key in _ADOPTED_RESPONSE_KEYS
        if key != "receiptSHA256"
    }
    encoded = json.dumps(
        canonical,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _terminal_response_is_bound(raw: bytes, request: Mapping[str, Any]) -> bool:
    """Validate the two Core terminal response forms used by response.json."""
    try:
        value = _strict_object(raw, limit=MAX_MANAGEMENT_RESPONSE_BYTES)
        request_sha = hashlib.sha256(request["_raw"]).hexdigest()
        if set(value) == _RELEASED_RESPONSE_KEYS:
            if value.get("version") != 1 or value.get("phase") != "released" or type(value.get("version")) is not int:
                return False
            if type(value.get("pid")) is not int or value["pid"] <= 0:
                return False
            if value.get("managementID") != request["managementID"] or value.get("nonce") != request["nonce"]:
                return False
            if value.get("requestSHA256") != request_sha:
                return False
            if value.get("sourceSetupID") != request["sourceSetupID"]:
                return False
            if value.get("activationSHA256") != request["sourceActivationSHA256"]:
                return False
            if value.get("restoreRootSHA256") != request["sourceRestoreRootSHA256"]:
                return False
            return value.get("app") == request["sourceApp"]
        if set(value) != _ADOPTED_RESPONSE_KEYS:
            return False
        if value.get("version") != 1 or type(value.get("version")) is not int:
            return False
        if value.get("managementID") != request["managementID"] or value.get("nonce") != request["nonce"]:
            return False
        if value.get("requestSHA256") != request_sha:
            return False
        if value.get("sourceSetupID") != request["sourceSetupID"] or value.get("targetSetupID") != request["targetSetupID"]:
            return False
        if value.get("sourceApp") != request["sourceApp"] or value.get("targetApp") != request["targetApp"]:
            return False
        if value.get("expectedDeviceUDID") != request["expectedDeviceUDID"] or value.get("teamID") != request["teamID"]:
            return False
        if value.get("sourceActivationSHA256") != request["sourceActivationSHA256"]:
            return False
        if value.get("sourceRestoreRootSHA256") != request["sourceRestoreRootSHA256"]:
            return False
        source_app = _app(value.get("sourceApp"))
        target_app = _app(value.get("targetApp"))
        if source_app != request["sourceApp"] or target_app != request["targetApp"]:
            return False
        _uuid(value.get("managementID"))
        _uuid(value.get("nonce"))
        _hash(value.get("requestSHA256"))
        _uuid(value.get("sourceSetupID"))
        _uuid(value.get("targetSetupID"))
        _device(value.get("expectedDeviceUDID"))
        team = value.get("teamID")
        if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
            return False
        _hash(value.get("sourceActivationSHA256"))
        _hash(value.get("sourceRestoreRootSHA256"), nullable=True)
        _hash(value.get("targetActivationSHA256"))
        receipt_sha = value.get("receiptSHA256")
        _hash(receipt_sha)
        return receipt_sha == _canonical_adoption_sha256(value)
    except ManagementBridgeError:
        return False


def _source_response_has_phase(raw: bytes, request: Mapping[str, Any], phases: set[str]) -> bool:
    """Validate a non-terminal source receipt against one frozen request."""
    try:
        value = _strict_object(raw, limit=MAX_MANAGEMENT_RESPONSE_BYTES)
        if set(value) != _RELEASED_RESPONSE_KEYS:
            return False
        if value.get("version") != 1 or type(value.get("version")) is not int:
            return False
        phase = value.get("phase")
        if not isinstance(phase, str) or phase not in phases:
            return False
        if type(value.get("pid")) is not int or value["pid"] <= 0:
            return False
        if value.get("managementID") != request["managementID"] or value.get("nonce") != request["nonce"]:
            return False
        if value.get("requestSHA256") != hashlib.sha256(request["_raw"]).hexdigest():
            return False
        if value.get("sourceSetupID") != request["sourceSetupID"]:
            return False
        if value.get("activationSHA256") != request["sourceActivationSHA256"]:
            return False
        if value.get("restoreRootSHA256") != request["sourceRestoreRootSHA256"]:
            return False
        return _app(value.get("app")) == request["sourceApp"]
    except ManagementBridgeError:
        return False


def _validate_control(raw: bytes, request: Mapping[str, Any]) -> dict[str, Any]:
    value = _strict_object(raw, limit=MAX_MANAGEMENT_CONTROL_BYTES)
    if set(value) != _CONTROL_KEYS or value.get("version") != 1 or type(value.get("version")) is not int:
        raise _error("invalid-request")
    management_id = _uuid(value.get("managementID"))
    nonce = _uuid(value.get("nonce"))
    request_sha = _hash(value.get("requestSHA256"))
    action = value.get("action")
    if not isinstance(action, str) or action not in _CONTROL_ACTIONS:
        raise _error("invalid-request")
    if (
        management_id != request["managementID"]
        or nonce != request["nonce"]
        or request_sha != hashlib.sha256(request["_raw"]).hexdigest()
    ):
        raise _error("transaction-conflict")
    return {
        "version": 1,
        "managementID": management_id,
        "nonce": nonce,
        "requestSHA256": request_sha,
        "action": action,
    }


def _release_response_allows_control(response: bytes | None, request: Mapping[str, Any],
                                    previous_request: bytes | None) -> bool:
    # Cancellation need not wait for quiescence. A preparing receipt or the
    # previous operation's retained terminal response is not a new ready
    # claim. The producer still requires its original PID/no-mutation gate.
    if response is None or _source_response_has_phase(response, request, {"preparing", "ready", "released"}):
        return True
    if not isinstance(previous_request, bytes):
        return False
    try:
        previous = _validate_management_request(previous_request)
        previous["_raw"] = previous_request
        return (previous["managementID"] != request["managementID"] and
                previous["expectedDeviceUDID"] == request["expectedDeviceUDID"] and
                _terminal_response_is_bound(response, previous))
    except ManagementBridgeError:
        return False


class _ManagementPymobiledeviceAdapter(PinnedPymobiledeviceAdapter):
    """Private M1 implementation bound to D1's selected transport."""

    def __init__(self, device: PinnedManagementDeviceAdapter, config: Any):
        super().__init__(state_root=Path(config.state_root))
        self._device = device

    def _open(self, serial: str, cache: Path) -> Any:
        return self._device._open_lockdown(serial, cache)

    def transport_serial(self, device_id: str) -> str:
        return self._device._transport_serial(device_id)

    @asynccontextmanager
    async def _process_control(self, device_id: str, transport_serial: str):
        async with self._device._dvt_control(device_id, transport_serial) as (rsd, provider_cls, control_cls):
            async with provider_cls(rsd) as provider:
                async with control_cls(provider) as control:
                    yield control

    def query_cryptex(self, device_id: str) -> Any:
        """Query cryptexd through D1's already selected RSD transport."""
        try:
            serial = self.transport_serial(device_id)
            return _run(self._query_cryptex(device_id, serial, None))
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("support-unavailable") from None

    def query_cryptex_with_restore(self, device_id: str, restore_dir: Path) -> Any:
        """Fresh cryptex query with a caller-selected validated generation."""
        try:
            serial = self.transport_serial(device_id)
            return _run(self._query_cryptex(device_id, serial, Path(restore_dir)))
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("support-unavailable") from None

    async def _query_cryptex(self, device_id: str, serial: str, restore_dir: Path | None) -> Any:
        try:
            from ..Setup.setup_support import PinnedSupportAdapter, _failure
            from ..Setup.setup_adapters import SupportObservation
        except ImportError:
            from Setup.setup_support import PinnedSupportAdapter, _failure
            from Setup.setup_adapters import SupportObservation

        support = PinnedSupportAdapter(self, restore_dir=restore_dir)
        async with self._device._dvt_control(device_id, serial) as (rsd, _provider_cls, _control_cls):
            support._verify_rsd(rsd, normalized_device(device_id))
            module = importlib.import_module("pymobiledevice3.services.cryptexd")
            service_cls = getattr(module, "CryptexdService", None)
            if not callable(service_cls):
                raise _failure("runtime-api-mismatch")
            service = service_cls(rsd)
            try:
                ddi = support._ddi(await service.copy_installed())
                version = str(getattr(rsd, "product_version", ""))
                if ddi is None:
                    return SupportObservation(False, "cryptex", version, None, None, None)
                # A preflight query has no local generation to compare.  When
                # one is supplied, prove both its selected DDI version and
                # its immutable generation identity against this fresh read.
                if restore_dir is None or not restore_dir.is_dir():
                    return SupportObservation(False, "cryptex", version, None, None, None)
                expected_version = support._selected_cryptex_version()
                identifier, installed_version = support._require_matching_ddi(
                    [type("Installed", (), {"identifier": ddi[0], "version": ddi[1]})()],
                    expected_version,
                )
                generation_id = support._observed_generation_id("cryptex")
                if generation_id is None:
                    return SupportObservation(False, "cryptex", version, None, None, None)
                return SupportObservation(True, "cryptex", version, generation_id, identifier, installed_version)
            finally:
                with contextlib.suppress(Exception):
                    await service.close()

    def install_cryptex(self, device_id: str, restore_dir: Path) -> Any:
        """Install cryptex DDI using the exact D1-created RSD context."""
        try:
            serial = self.transport_serial(device_id)
            return _run(self._install_cryptex(device_id, serial, Path(restore_dir)))
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("support-unavailable") from None

    async def _install_cryptex(self, device_id: str, serial: str, restore_dir: Path) -> Any:
        try:
            from ..Setup.setup_support import (
                PinnedSupportAdapter,
                _ensure_fetched_generation,
                _materialize_cryptex_restore,
                _failure,
                validate_generation,
            )
            from ..Setup.setup_adapters import SupportObservation
        except ImportError:
            from Setup.setup_support import (
                PinnedSupportAdapter,
                _ensure_fetched_generation,
                _materialize_cryptex_restore,
                _failure,
                validate_generation,
            )
            from Setup.setup_adapters import SupportObservation

        support = PinnedSupportAdapter(self, restore_dir=restore_dir)
        _ensure_fetched_generation("cryptex", restore_dir)
        generation = validate_generation("cryptex", restore_dir)
        _materialize_cryptex_restore(restore_dir, require_existing=True)
        generation_id = support._generation_id(generation.restore_dir)
        expected_version = support._selected_cryptex_version()
        module = importlib.import_module("pymobiledevice3.services.cryptexd")
        service_cls = getattr(module, "CryptexdService", None)
        if not callable(service_cls):
            raise _failure("runtime-api-mismatch")
        async with self._device._dvt_control(device_id, serial) as (rsd, _provider_cls, _control_cls):
            support._verify_rsd(rsd, normalized_device(device_id))
            service = service_cls(rsd)
            try:
                installed = await service.copy_installed()
                if support._ddi(installed) is None:
                    runtime_restore = _materialize_cryptex_restore(restore_dir, require_existing=True)
                    result = await service.auto_install_ddi(runtime_restore)
                    if result is None:
                        raise _failure()
                identifier, version = support._require_matching_ddi(
                    await service.copy_installed(), expected_version
                )
                return SupportObservation(
                    True,
                    "cryptex",
                    str(getattr(rsd, "product_version", "")),
                    generation_id,
                    identifier,
                    version,
                )
            finally:
                with contextlib.suppress(Exception):
                    await service.close()


class ManagementPreparationAdapter:
    """Actual preparation operations for one immutable M3 transport."""

    def __init__(self, config: Any, transport: str):
        try:
            state_root = getattr(config, "state_root")
            if not isinstance(state_root, (str, Path)) or not str(state_root).startswith("/"):
                raise ValueError()
            self.config = config
            self._device = PinnedManagementDeviceAdapter(config, transport)
            self._pmd = _ManagementPymobiledeviceAdapter(self._device, config)
        except ManagementBridgeError:
            raise
        except Exception:
            raise _error("configuration-invalid") from None

    @property
    def transport(self) -> str:
        return self._device.transport

    @contextmanager
    def _house_arrest(self, device_id: str) -> Iterator[Any]:
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-management-preparation-") as directory:
                client = self._pmd._open(device_id, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise SetupBridgeError("runtime-api-mismatch")
                service = _run(service_cls.create(client, TARGET_BUNDLE_ID, documents_only=False))
                yield service
        except (ManagementBridgeError, SetupBridgeError):
            raise
        except Exception as error:
            raise _map_exception(error) from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    @staticmethod
    def _read_remote(service: Any, path: str, *, max_bytes: int) -> bytes | None:
        try:
            info = PinnedPymobiledeviceAdapter._remote_info(service, path)
        except _RemoteMissing:
            return None
        if info["size"] > max_bytes:
            raise SetupBridgeError("storage-unavailable")

        async def read() -> bytes:
            declared = info["size"]
            handle = await service.fopen(path, "r")
            data = bytearray()
            try:
                remaining = declared
                while remaining:
                    chunk = await service.fread(handle, min(1024 * 1024, remaining))
                    if not isinstance(chunk, bytes) or not chunk or len(chunk) > remaining:
                        raise ValueError("short remote read")
                    data.extend(chunk)
                    remaining -= len(chunk)
                sentinel = await service.fread(handle, 1)
                if not isinstance(sentinel, bytes) or sentinel:
                    raise ValueError("remote grew during read")
                final = await service.stat(path)
                if (not isinstance(final, Mapping) or final.get("st_ifmt") != "S_IFREG" or
                        type(final.get("st_size")) is not int or final.get("st_size") != declared):
                    raise ValueError("remote changed during read")
                return bytes(data)
            finally:
                await service.fclose(handle)

        try:
            return _run(read())
        except OSError as error:
            if _is_remote_missing(error):
                return None
            raise SetupBridgeError("handoff-unknown") from None
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None

    @staticmethod
    def _safe_remote_path(name: str, table: Mapping[str, tuple[str, int]]) -> tuple[str, int]:
        if not isinstance(name, str) or name not in table:
            raise _error("invalid-request")
        return table[name]

    def observe(self, device_id: str) -> Any:
        return self._invoke(self._device.observe, device_id)

    def installed_identity(self, device_id: str) -> Any:
        return self._invoke(self._device.installed_identity, device_id)

    def read_activation(self, device_id: str) -> bytes | None:
        return self._invoke(self._device.read_activation, device_id)

    def source_pid(self, device_id: str) -> int:
        return self._invoke(self._device.source_pid, device_id)

    def stop_owned_process(self, device_id: str, expected_pid: int) -> None:
        self._invoke(self._device.stop_owned_process, device_id, expected_pid)

    def read_file(self, device_id: str, name: str) -> bytes | None:
        path, limit = self._safe_remote_path(name, _LOGICAL_FILES)
        try:
            with self._house_arrest(device_id) as service:
                return self._read_remote(service, path, max_bytes=limit)
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def read_management_root(self, device_id: str) -> bytes | None:
        """Read Core's fixed bounded management root without granting authority."""
        return self.read_file(device_id, "managementRoot")

    def read_management_generation(self, device_id: str, management_id: str) -> "ManagementGeneration | None":
        """Read one UUID-derived generation's fixed three raw files.

        A missing generation is returned as ``None``.  A partially present
        generation is an immutable-storage conflict; callers never receive a
        synthesized or path-selected record.  The second pass prevents a
        concurrent App write from combining bytes from different generations.
        """
        try:
            management_id = _uuid(management_id)
            from .management_lineage import ManagementGeneration
        except (ManagementBridgeError, ImportError):
            raise _error("invalid-request") from None
        base = "Library/Application Support/GoFlyManagement/generations/" + management_id
        files = (
            (base + "/request.json", 32 * 1024),
            (base + "/source-activation.json", 256 * 1024),
            (base + "/source-restore-root.json", 1024 * 1024),
        )

        def read_once(service: Any) -> tuple[bytes | None, bytes | None, bytes | None]:
            return tuple(self._read_remote(service, path, max_bytes=limit) for path, limit in files)  # type: ignore[return-value]

        try:
            with self._house_arrest(device_id) as service:
                first = read_once(service)
                if all(item is None for item in first):
                    # Recheck an honest absence so a generation appearing
                    # during the read is not mistaken for a stable absence.
                    if read_once(service) != first:
                        raise SetupBridgeError("transaction-conflict")
                    return None
                if first[0] is None or first[1] is None:
                    raise SetupBridgeError("transaction-conflict")
                second = read_once(service)
                if second != first:
                    raise SetupBridgeError("transaction-conflict")
                return ManagementGeneration(first[0], first[1], first[2])
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def publish_management_request(self, device_id: str, raw: bytes, previous: bytes | None = None) -> None:
        request = _validate_management_request(raw)
        try:
            selected_device = normalized_device(device_id)
        except Exception:
            raise _error("identity-mismatch") from None
        if request["expectedDeviceUDID"] != selected_device:
            raise _error("identity-mismatch")
        path, _limit = _LOGICAL_FILES["managementRequest"]
        response_path, response_limit = _LOGICAL_FILES["managementResponse"]
        try:
            with self._house_arrest(device_id) as service:
                current = self._read_remote(service, path, max_bytes=MAX_MANAGEMENT_REQUEST_BYTES)
                if current == raw:
                    return
                if current is None:
                    if previous is not None:
                        raise SetupBridgeError("transaction-conflict")
                else:
                    if not isinstance(previous, bytes) or current != previous:
                        raise SetupBridgeError("transaction-conflict")
                    response = self._read_remote(service, response_path, max_bytes=response_limit)
                    old_request = _validate_management_request(current)
                    old_request["_raw"] = current
                    if response is None or not _terminal_response_is_bound(response, old_request):
                        raise SetupBridgeError("transaction-conflict")
                    # Re-read both immutable inputs immediately before the
                    # destructive remove.  A stale response or request must
                    # never authorize deletion of the prior request.
                    fresh_current = self._read_remote(
                        service, path, max_bytes=MAX_MANAGEMENT_REQUEST_BYTES
                    )
                    fresh_response = self._read_remote(
                        service, response_path, max_bytes=response_limit
                    )
                    if fresh_current != current or fresh_response != response:
                        raise SetupBridgeError("transaction-conflict")
                    if fresh_response is None or not _terminal_response_is_bound(fresh_response, old_request):
                        raise SetupBridgeError("transaction-conflict")
                    if old_request["expectedDeviceUDID"] != selected_device:
                        raise SetupBridgeError("identity-mismatch")
                    removed = _run(service.rm_single(path, force=False))
                    if removed is not True or self._read_remote(service, path, max_bytes=MAX_MANAGEMENT_REQUEST_BYTES) is not None:
                        raise SetupBridgeError("removal-unknown")
                if self._read_remote(service, path, max_bytes=MAX_MANAGEMENT_REQUEST_BYTES) not in {None, raw}:
                    raise SetupBridgeError("transaction-conflict")
                _run(service.makedirs(path.rsplit("/", 1)[0]))
                self._pmd._publish_on_service(service, path, raw)
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def remove_legacy(self, device_id: str, name: str, expected: bytes) -> bool:
        path, limit = self._safe_remote_path(name, _LEGACY_FILES)
        if not isinstance(expected, bytes) or len(expected) > limit:
            raise _error("invalid-request")
        try:
            with self._house_arrest(device_id) as service:
                current = self._read_remote(service, path, max_bytes=limit)
                if current is None:
                    return False
                if current != expected:
                    raise SetupBridgeError("transaction-conflict")
                if self._read_remote(service, path, max_bytes=limit) != expected:
                    raise SetupBridgeError("transaction-conflict")
                result = _run(service.rm_single(path, force=False))
                if result is False:
                    raise SetupBridgeError("removal-unknown")
                if self._read_remote(service, path, max_bytes=limit) is not None:
                    raise SetupBridgeError("removal-unknown")
                return True
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def launch(self, device_id: str) -> int:
        return self._invoke(self._pmd.launch, device_id)

    def publish_control(
        self,
        device_id: str,
        raw: bytes,
        previous: bytes | None = None,
        previous_request: bytes | None = None,
    ) -> None:
        """Publish one bounded App control command on the selected transport."""
        try:
            selected_device = normalized_device(device_id)
        except Exception:
            raise _error("identity-mismatch") from None
        control_path, control_limit = _LOGICAL_FILES["managementControl"]
        request_path, request_limit = _LOGICAL_FILES["managementRequest"]
        response_path, response_limit = _LOGICAL_FILES["managementResponse"]
        try:
            # Validate action/type/closed keys before touching the device.
            control_shape = _strict_object(raw, limit=control_limit)
            if (
                set(control_shape) != _CONTROL_KEYS
                or control_shape.get("version") != 1
                or type(control_shape.get("version")) is not int
                or not isinstance(control_shape.get("action"), str)
                or control_shape.get("action") not in _CONTROL_ACTIONS
            ):
                raise _error("invalid-request")
            with self._house_arrest(device_id) as service:
                current_main = self._read_remote(service, request_path, max_bytes=request_limit)
                if current_main is None:
                    raise SetupBridgeError("transaction-conflict")
                current_request = _validate_management_request(current_main)
                current_request["_raw"] = current_main
                if current_request["expectedDeviceUDID"] != selected_device:
                    raise SetupBridgeError("identity-mismatch")
                new_control = _validate_control(raw, current_request)
                current_control = self._read_remote(service, control_path, max_bytes=control_limit)
                response = self._read_remote(service, response_path, max_bytes=response_limit)
                if current_control == raw:
                    self._require_control_request(service, current_main, raw)
                    if self._read_remote(service, control_path, max_bytes=control_limit) != raw:
                        raise SetupBridgeError("transaction-conflict")
                    return

                if current_control is None:
                    # Resume may retry only the same frozen command after an
                    # explicit absence reconciliation.  The journal owns
                    # that decision; this adapter only compares bytes.
                    if previous is not None and (not isinstance(previous, bytes) or previous != raw):
                        raise SetupBridgeError("transaction-conflict")
                    fresh_main = self._read_remote(service, request_path, max_bytes=request_limit)
                    if fresh_main != current_main:
                        raise SetupBridgeError("transaction-conflict")
                    self._publish_control_bytes(service, current_main, raw)
                    return

                if not isinstance(previous, bytes) or current_control != previous:
                    raise SetupBridgeError("transaction-conflict")

                # A command bound to the current request is a same-operation
                # transition.  A command bound to another request requires
                # the caller's actual previous request and terminal receipt.
                same_operation = False
                try:
                    old_control_shape = _strict_object(current_control, limit=control_limit)
                    old_request_sha = old_control_shape.get("requestSHA256")
                    same_operation = old_request_sha == hashlib.sha256(current_main).hexdigest()
                except ManagementBridgeError:
                    raise SetupBridgeError("transaction-conflict") from None
                if same_operation:
                    try:
                        old_control = _validate_control(current_control, current_request)
                    except ManagementBridgeError:
                        raise SetupBridgeError("transaction-conflict") from None
                    old_action = old_control["action"]
                    new_action = new_control["action"]
                    if old_action != "quiesce":
                        raise SetupBridgeError("transaction-conflict")
                    if new_action == "seal":
                        if response is None or not _source_response_has_phase(
                            response, current_request, {"ready", "mutationSealed"}
                        ):
                            raise SetupBridgeError("transaction-conflict")
                    elif new_action == "release":
                        if not _release_response_allows_control(response, current_request, previous_request):
                            raise SetupBridgeError("transaction-conflict")
                    else:
                        raise SetupBridgeError("transaction-conflict")
                    old_request = current_request
                else:
                    if not isinstance(previous_request, bytes):
                        raise SetupBridgeError("transaction-conflict")
                    old_request = _validate_management_request(previous_request)
                    old_request["_raw"] = previous_request
                    if old_request["expectedDeviceUDID"] != selected_device:
                        raise SetupBridgeError("transaction-conflict")
                    try:
                        _validate_control(current_control, old_request)
                    except ManagementBridgeError:
                        raise SetupBridgeError("transaction-conflict") from None
                    if response is None or not _terminal_response_is_bound(response, old_request):
                        raise SetupBridgeError("transaction-conflict")

                # Request, command, and response are re-read as one final
                # immutable snapshot immediately before command removal.
                fresh_main = self._read_remote(service, request_path, max_bytes=request_limit)
                fresh_control = self._read_remote(service, control_path, max_bytes=control_limit)
                fresh_response = self._read_remote(service, response_path, max_bytes=response_limit)
                if fresh_main != current_main or fresh_control != current_control or fresh_response != response:
                    raise SetupBridgeError("transaction-conflict")
                if not same_operation and (
                    fresh_response is None or not _terminal_response_is_bound(fresh_response, old_request)
                ):
                    raise SetupBridgeError("transaction-conflict")
                if same_operation and new_control["action"] == "seal" and (
                    fresh_response is None or not _source_response_has_phase(
                        fresh_response, current_request, {"ready", "mutationSealed"}
                    )
                ):
                    raise SetupBridgeError("transaction-conflict")
                if same_operation and new_control["action"] == "release" and not _release_response_allows_control(
                        fresh_response, current_request, previous_request):
                    raise SetupBridgeError("transaction-conflict")
                removed = _run(service.rm_single(control_path, force=False))
                if removed is not True or self._read_remote(service, control_path, max_bytes=control_limit) is not None:
                    raise SetupBridgeError("removal-unknown")
                if self._read_remote(service, request_path, max_bytes=request_limit) != current_main:
                    raise SetupBridgeError("transaction-conflict")
                self._publish_control_bytes(service, current_main, raw)
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def _require_control_request(self, service: Any, expected_main: bytes, raw: bytes) -> None:
        path, maximum = _LOGICAL_FILES["managementRequest"]
        fresh = self._read_remote(service, path, max_bytes=maximum)
        if fresh != expected_main:
            raise SetupBridgeError("transaction-conflict")
        request = _validate_management_request(fresh)
        request["_raw"] = fresh
        _validate_control(raw, request)

    def _publish_control_bytes(self, service: Any, expected_main: bytes, raw: bytes) -> None:
        """Complete identical nonconsumed metadata; journal owns each call."""
        path, maximum = _LOGICAL_FILES["managementControl"]
        staging = path + ".staging"
        self._require_control_request(service, expected_main, raw)
        _run(service.makedirs(path.rsplit("/", 1)[0]))
        staged = self._read_remote(service, staging, max_bytes=maximum)
        if staged is None:
            _run(service.set_file_contents(staging, raw))
        elif staged != raw:
            raise SetupBridgeError("transaction-conflict")
        if self._read_remote(service, staging, max_bytes=maximum) != raw:
            raise SetupBridgeError("handoff-unknown")
        self._require_control_request(service, expected_main, raw)
        current = self._read_remote(service, path, max_bytes=maximum)
        if current is not None:
            if current != raw:
                raise SetupBridgeError("transaction-conflict")
            return
        _run(service.rename(staging, path))
        if self._read_remote(service, path, max_bytes=maximum) != raw:
            raise SetupBridgeError("handoff-unknown")
        self._require_control_request(service, expected_main, raw)

    def prepare_pairing(self, device_id: str, candidate: str | Path) -> None:
        self._invoke(self._pmd.prepare_pairing, device_id, self._coerce_path(candidate))

    def pair(self, device_id: str, candidate: str | Path) -> Any:
        return self._invoke(self._pmd.pair, device_id, self._coerce_path(candidate))

    def verify_pairing(self, device_id: str, candidate: str | Path) -> Any:
        return self._invoke(self._pmd.verify_pairing, device_id, self._coerce_path(candidate))

    def deliver_pairing(
        self,
        device_id: str,
        candidate: str | Path,
        pairing_transaction_id: str,
        pairing_sha256: str,
    ) -> None:
        try:
            transaction_id = _uuid(pairing_transaction_id)
            if not isinstance(pairing_sha256, str) or _HEX64_RE.fullmatch(pairing_sha256) is None:
                raise _error("invalid-request")
            raw = _read_private_regular(self._coerce_path(candidate), max_bytes=MAX_PAIRING_BYTES)
            if not raw or hashlib.sha256(raw).hexdigest() != pairing_sha256:
                raise SetupBridgeError("pairing-unknown")
            payload = plistlib.dumps(
                {
                    "version": 1,
                    "transactionID": transaction_id,
                    "expectedDeviceUDID": normalized_device(device_id),
                    "pairingFile": raw,
                    "sha256": hashlib.sha256(raw).digest(),
                },
                fmt=plistlib.FMT_BINARY,
            )
            if len(payload) > MAX_PAIRING_ENVELOPE_BYTES:
                raise SetupBridgeError("pairing-unknown")
            self._invoke(
                self._pmd._publish_house_arrest,
                device_id,
                "Library/Application Support/LocalGoSetup/incoming.plist",
                payload,
                conflict_code="handoff-unknown",
            )
        except (ManagementBridgeError, SetupBridgeError) as error:
            raise _map_exception(error) from None
        except Exception as error:
            raise _map_exception(error) from None

    def prepare_readback(self, device_id: str, setup_id: str, nonce: str, identity: PreparationAppIdentity) -> None:
        self._require_identity(identity)
        self._invoke(self._pmd.prepare_readback, device_id, setup_id, nonce, identity)

    def readback(self, device_id: str, setup_id: str, nonce: str) -> Any:
        return self._invoke(self._pmd.readback, device_id, setup_id, nonce)

    def read_activation_receipt(self, device_id: str, setup_id: str, nonce: str) -> Any:
        return self._invoke(self._pmd.read_activation_receipt, device_id, setup_id, nonce)

    def prepare_generation(self, method: str, restore_dir: str | Path) -> Any:
        return self._invoke(self._pmd.prepare_generation, method, self._coerce_path(restore_dir))

    def query_support(self, device_id: str, method: str, restore_dir: str | Path | None = None) -> Any:
        if method == "cryptex":
            if restore_dir is None:
                return self._invoke(self._pmd.query_cryptex, device_id)
            return self._invoke(
                self._pmd.query_cryptex_with_restore,
                device_id,
                self._coerce_path(restore_dir),
            )
        if restore_dir is not None:
            try:
                from ..Setup.setup_support import PinnedSupportAdapter
            except ImportError:
                from Setup.setup_support import PinnedSupportAdapter
            return self._invoke(
                PinnedSupportAdapter(self._pmd, restore_dir=self._coerce_path(restore_dir)).query,
                device_id,
                method,
            )
        return self._invoke(self._pmd.query_support, device_id, method)

    def install_support(self, device_id: str, method: str, restore_dir: str | Path) -> Any:
        if method == "cryptex":
            return self._invoke(self._pmd.install_cryptex, device_id, self._coerce_path(restore_dir))
        return self._invoke(self._pmd.install_support, device_id, method, self._coerce_path(restore_dir))

    def prepare_setup_input(
        self,
        device_id: str,
        setup_id: str,
        nonce: str,
        identity: PreparationAppIdentity,
        pairing_transaction_id: str,
        pairing_sha256: str,
        support: Mapping[str, Any],
        plan: FormalSetupInput,
    ) -> str:
        self._require_identity(identity)
        return self._invoke(
            self._pmd.prepare_setup_input,
            device_id,
            setup_id,
            nonce,
            identity,
            pairing_transaction_id,
            pairing_sha256,
            support,
            plan=plan,
        )

    @staticmethod
    def _require_identity(identity: PreparationAppIdentity) -> None:
        if not isinstance(identity, PreparationAppIdentity):
            raise _error("identity-unverified")
        try:
            _validate_app(identity.app(), code="identity-unverified")
            if (identity.executable != TARGET_NAME or not isinstance(identity.team_id, str) or
                    TEAM_RE.fullmatch(identity.team_id) is None):
                raise _error("identity-unverified")
            _expiry(identity.expires_at, code="identity-unverified")
        except ManagementBridgeError:
            raise _error("identity-unverified") from None

    @staticmethod
    def _coerce_path(value: str | Path) -> Path:
        try:
            path = Path(value)
        except (TypeError, ValueError, OSError):
            raise _error("configuration-invalid") from None
        if not path.is_absolute():
            raise _error("configuration-invalid")
        return path

    @staticmethod
    def _invoke(method: Callable[..., T], *args: Any, **kwargs: Any) -> T:
        try:
            return method(*args, **kwargs)
        except ManagementBridgeError:
            raise
        except SetupBridgeError as error:
            raise ManagementBridgeError(error.code) from None
        except Exception:
            raise ManagementBridgeError("operation-failed") from None

__all__ = ["ManagementPreparationAdapter"]
