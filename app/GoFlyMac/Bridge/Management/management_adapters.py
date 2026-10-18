"""Actual transport-bound device operations for the M3 management bridge.

This module owns device observations only.  It does not journal a management
operation, publish an App request, or claim that a later Core readback adopted
an update.  All calls into pymobiledevice3 are opened with the selected UDID
and transport; no library default may select a different visible device.
"""

from __future__ import annotations

import contextlib
import importlib
import importlib.metadata
import re
import tempfile
from contextlib import AsyncExitStack
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

try:
    from ..Setup.setup_adapters import (
        ArtifactIdentity,
        FormalArtifactValidator,
        PinnedPymobiledeviceAdapter,
        PMD3_VERSION,
        _RemoteMissing,
        _is_remote_missing,
        _run,
    )
    from ..Setup.setup_protocol import TARGET_BUNDLE_ID, normalized_device
    from .management_protocol import ManagementBridgeError, TEAM_RE
except ImportError:  # direct execution from the packaged Bridge root
    from Setup.setup_adapters import (
        ArtifactIdentity,
        FormalArtifactValidator,
        PinnedPymobiledeviceAdapter,
        PMD3_VERSION,
        _RemoteMissing,
        _is_remote_missing,
        _run,
    )
    from Setup.setup_protocol import TARGET_BUNDLE_ID, normalized_device
    from Management.management_protocol import ManagementBridgeError, TEAM_RE

MAX_ACTIVATION_BYTES = 256 * 1024
ACTIVATION_PATH = "Library/Application Support/GoFlySetup/activation.json"
OS_RE = re.compile(r"(?:26|27)\.\d+(?:\.\d+)?\Z")
TRANSPORTS = frozenset({"USB", "Network"})


@dataclass(frozen=True)
class ManagementDeviceObservation:
    device_id: str
    os_version: str
    transport: str
    trust: bool
    developer_mode: bool


@dataclass(frozen=True)
class ManagementInstalledIdentity:
    exists: bool
    bundle_id: str = TARGET_BUNDLE_ID
    build: str | None = None
    team_id: str | None = None


@dataclass(frozen=True)
class ManagementUpgradeObservation:
    confirmed: bool
    device_id: str
    bundle_id: str = TARGET_BUNDLE_ID
    build: str | None = None
    team_id: str | None = None

    @property
    def outcome(self) -> str:
        return "confirmed" if self.confirmed else "unknown"


# Short aliases keep the boundary convenient for callers without duplicating
# a second mutable model or exposing the Setup adapter's broader schema.
DeviceObservation = ManagementDeviceObservation
InstalledIdentity = ManagementInstalledIdentity
UpgradeObservation = ManagementUpgradeObservation


def _management_error(code: str) -> ManagementBridgeError:
    return ManagementBridgeError(code)


class PinnedManagementDeviceAdapter:
    """A management adapter pinned to one exact USB or Network transport."""

    def __init__(self, config: Any, transport: str):
        if transport not in TRANSPORTS:
            raise ManagementBridgeError("configuration-invalid")
        self.config = config
        self._transport = transport
        self._modules: tuple[Any, Any] | None = None

    @property
    def transport(self) -> str:
        return self._transport

    def _load(self) -> tuple[Any, Any]:
        if self._modules is not None:
            return self._modules
        try:
            if importlib.metadata.version("pymobiledevice3") != PMD3_VERSION:
                raise ValueError()
            usbmux = importlib.import_module("pymobiledevice3.usbmux")
            lockdown = importlib.import_module("pymobiledevice3.lockdown")
        except Exception:
            raise _management_error("dependency-mismatch") from None
        if not callable(getattr(usbmux, "list_devices", None)) or not callable(
            getattr(lockdown, "create_using_usbmux", None)
        ):
            raise _management_error("runtime-api-mismatch")
        self._modules = usbmux, lockdown
        return self._modules

    @staticmethod
    def _device_id(value: str) -> str:
        try:
            return normalized_device(value)
        except Exception:
            raise _management_error("identity-mismatch") from None

    def _transport_serial(self, device_id: str) -> str:
        target = self._device_id(device_id)
        usbmux, _ = self._load()
        try:
            rows = _run(usbmux.list_devices())
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("device-disconnected") from None
        for row in rows if isinstance(rows, list) else []:
            serial = getattr(row, "serial", None) or getattr(row, "udid", None)
            row_transport = getattr(row, "connection_type", None) or getattr(row, "transport", None)
            if (
                isinstance(serial, str)
                and serial.strip().lower() == target
                and isinstance(row_transport, str)
                and row_transport.upper() == self._transport.upper()
            ):
                return serial
        raise _management_error("device-disconnected")

    def _open_lockdown(self, device_id: str, cache: Path) -> Any:
        """Open authenticated Lockdown with an explicit UDID and transport."""
        _, lockdown = self._load()
        target = self._device_id(device_id)
        serial = self._transport_serial(target)
        client = None
        try:
            client = _run(
                lockdown.create_using_usbmux(
                    serial=serial,
                    label="GoFlyMac Management",
                    autopair=False,
                    connection_type=self._transport,
                    pair_timeout=60,
                    pairing_records_cache_folder=cache,
                )
            )
            getter = getattr(client, "get_value", None)
            if not callable(getter):
                raise _management_error("runtime-api-mismatch")
            values = _run(getter())
            if not isinstance(values, Mapping) or str(values.get("UniqueDeviceID", "")).lower() != target:
                raise _management_error("identity-mismatch")
            return client
        except ManagementBridgeError:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())
            raise
        except Exception:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())
            raise _management_error("trust-required") from None

    @staticmethod
    def _close(value: Any) -> None:
        with contextlib.suppress(Exception):
            if value is not None:
                _run(value.close())

    def observe(self, device_id: str) -> ManagementDeviceObservation:
        target = self._device_id(device_id)
        client = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-management-observe-") as directory:
                client = self._open_lockdown(target, Path(directory))
                getter = getattr(client, "get_value", None)
                values = _run(getter()) if callable(getter) else None
                if not isinstance(values, Mapping):
                    raise _management_error("identity-mismatch")
                version = values.get("ProductVersion")
                if not isinstance(version, str) or OS_RE.fullmatch(version) is None:
                    raise _management_error("unsupported-os")
                try:
                    developer = _run(
                        getter(domain="com.apple.security.mac.amfi", key="DeveloperModeStatus")
                    )
                except Exception:
                    raise _management_error("developer-mode-required") from None
                if type(developer) is not bool:
                    raise _management_error("developer-mode-required")
                trust = values.get("TrustedHostAttached")
                if type(trust) is not bool:
                    raise _management_error("trust-required")
                return ManagementDeviceObservation(target, version, self._transport, trust, developer)
        finally:
            self._close(client)

    @staticmethod
    def _team_from_application_identifier(value: Any) -> str:
        if not isinstance(value, str) or "." not in value:
            raise _management_error("identity-mismatch")
        team, bundle = value.split(".", 1)
        if TEAM_RE.fullmatch(team) is None or bundle != TARGET_BUNDLE_ID:
            raise _management_error("identity-mismatch")
        return team

    @classmethod
    def _installed_identity(cls, value: Mapping[str, Any]) -> ManagementInstalledIdentity:
        if value.get("CFBundleIdentifier") not in (None, TARGET_BUNDLE_ID):
            raise _management_error("identity-mismatch")
        build = value.get("CFBundleVersion")
        if not isinstance(build, str) or not build:
            raise _management_error("identity-mismatch")

        teams: list[str] = []
        if "ApplicationIdentifier" in value:
            teams.append(cls._team_from_application_identifier(value["ApplicationIdentifier"]))
        if "TeamIdentifier" in value:
            team = value["TeamIdentifier"]
            if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
                raise _management_error("identity-mismatch")
            teams.append(team)
        entitlements = value.get("Entitlements")
        if entitlements is not None:
            if not isinstance(entitlements, Mapping):
                raise _management_error("identity-mismatch")
            if "application-identifier" in entitlements:
                teams.append(cls._team_from_application_identifier(entitlements["application-identifier"]))
            if "com.apple.application-identifier" in entitlements:
                teams.append(cls._team_from_application_identifier(entitlements["com.apple.application-identifier"]))
            if "com.apple.developer.team-identifier" in entitlements:
                team = entitlements["com.apple.developer.team-identifier"]
                if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
                    raise _management_error("identity-mismatch")
                teams.append(team)
        if len(set(teams)) > 1:
            raise _management_error("identity-mismatch")
        return ManagementInstalledIdentity(True, TARGET_BUNDLE_ID, build, teams[0] if teams else None)

    def installed_identity(self, device_id: str) -> ManagementInstalledIdentity:
        target = self._device_id(device_id)
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-management-installed-") as directory:
                client = self._open_lockdown(target, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.installation_proxy")
                service_cls = getattr(module, "InstallationProxyService", None)
                if service_cls is None:
                    raise _management_error("runtime-api-mismatch")
                service = service_cls(client)
                apps = _run(service.get_apps(bundle_identifiers=[TARGET_BUNDLE_ID]))
                if not isinstance(apps, Mapping):
                    raise _management_error("runtime-api-mismatch")
                value = apps.get(TARGET_BUNDLE_ID)
                if value is None:
                    return ManagementInstalledIdentity(False)
                if not isinstance(value, Mapping):
                    raise _management_error("runtime-api-mismatch")
                return self._installed_identity(value)
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("trust-required") from None
        finally:
            self._close(service)
            self._close(client)

    @staticmethod
    def _read_activation_bounded(service: Any) -> bytes | None:
        """Read activation.json while preserving AFC missing vs. unknown."""
        try:
            info = PinnedPymobiledeviceAdapter._remote_info(service, ACTIVATION_PATH)
        except _RemoteMissing:
            return None
        if info["size"] > MAX_ACTIVATION_BYTES:
            raise _management_error("storage-unavailable")

        async def read_remote() -> bytes:
            declared = info["size"]
            handle = await service.fopen(ACTIVATION_PATH, "r")
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
                final = await service.stat(ACTIVATION_PATH)
                if (
                    not isinstance(final, Mapping)
                    or final.get("st_ifmt") != "S_IFREG"
                    or type(final.get("st_size")) is not int
                    or final.get("st_size") != declared
                ):
                    raise ValueError("remote changed during read")
                return bytes(data)
            finally:
                await service.fclose(handle)

        try:
            data = _run(read_remote())
        except OSError as error:
            if _is_remote_missing(error):
                return None
            raise _management_error("handoff-unknown") from None
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("handoff-unknown") from None
        if not isinstance(data, bytes) or len(data) != info["size"] or len(data) > MAX_ACTIVATION_BYTES:
            raise _management_error("handoff-unknown")
        return data

    def read_activation(self, device_id: str) -> bytes | None:
        target = self._device_id(device_id)
        client = None
        service = None
        try:
            with tempfile.TemporaryDirectory(prefix="gofly-management-activation-") as directory:
                client = self._open_lockdown(target, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.house_arrest")
                service_cls = getattr(module, "HouseArrestService", None)
                if service_cls is None or not callable(getattr(service_cls, "create", None)):
                    raise _management_error("runtime-api-mismatch")
                service = _run(service_cls.create(client, TARGET_BUNDLE_ID, documents_only=False))
                return self._read_activation_bounded(service)
        except ManagementBridgeError:
            raise
        except Exception as error:
            if error.__class__.__name__ == "AppNotInstalledError":
                return None
            raise _management_error("operation-failed") from None
        finally:
            self._close(service)
            self._close(client)

    def explicit_upgrade(self, device_id: str, artifact: ArtifactIdentity) -> ManagementUpgradeObservation:
        """Upgrade an already installed app and report only the call confirmation."""
        target = self._device_id(device_id)
        if not isinstance(artifact, ArtifactIdentity):
            raise _management_error("identity-unverified")
        if not isinstance(artifact.team_id, str) or TEAM_RE.fullmatch(artifact.team_id) is None:
            raise _management_error("identity-unverified")
        try:
            current = FormalArtifactValidator().inspect(
                artifact.path, device_id=target, team_id=artifact.team_id
            )
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("artifact-mismatch") from None
        if current != artifact:
            raise _management_error("artifact-mismatch")

        client = None
        service = None
        try:
            observed = self.observe(target)
            if not observed.trust:
                raise _management_error("trust-required")
            if not observed.developer_mode:
                raise _management_error("developer-mode-required")
            with tempfile.TemporaryDirectory(prefix="gofly-management-upgrade-") as directory:
                client = self._open_lockdown(target, Path(directory))
                module = importlib.import_module("pymobiledevice3.services.installation_proxy")
                service_cls = getattr(module, "InstallationProxyService", None)
                if service_cls is None:
                    raise _management_error("runtime-api-mismatch")
                service = service_cls(client)
                try:
                    apps = _run(service.get_apps(bundle_identifiers=[TARGET_BUNDLE_ID]))
                    value = apps.get(TARGET_BUNDLE_ID) if isinstance(apps, Mapping) else None
                    if not isinstance(value, Mapping):
                        raise _management_error("identity-unverified")
                    installed = self._installed_identity(value)
                    if not installed.exists or installed.team_id is None:
                        raise _management_error("identity-unverified")
                    if installed.team_id != artifact.team_id:
                        raise _management_error("identity-mismatch")
                    try:
                        immediate = FormalArtifactValidator().inspect(
                            artifact.path, device_id=target, team_id=artifact.team_id)
                    except Exception:
                        raise _management_error("artifact-mismatch") from None
                    if immediate != artifact:
                        raise _management_error("artifact-mismatch")
                    _run(service.install_from_local(Path(artifact.path), cmd="Upgrade", developer=True))
                except ManagementBridgeError:
                    raise
                except Exception:
                    raise _management_error("update-unknown") from None
                try:
                    apps = _run(service.get_apps(bundle_identifiers=[TARGET_BUNDLE_ID]))
                    value = apps.get(TARGET_BUNDLE_ID) if isinstance(apps, Mapping) else None
                    if not isinstance(value, Mapping):
                        raise ValueError()
                    identity = self._installed_identity(value)
                    if identity.build != artifact.build or identity.team_id != artifact.team_id:
                        raise ValueError()
                    return ManagementUpgradeObservation(
                        True, target, TARGET_BUNDLE_ID, identity.build, identity.team_id
                    )
                except Exception:
                    raise _management_error("update-unknown") from None
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("update-unknown") from None
        finally:
            self._close(service)
            self._close(client)

    @contextlib.asynccontextmanager
    async def _dvt_control(self, device_id: str, serial: str):
        """Build a transport-bound userspace RSD/DVT context from real pmd3 APIs."""
        try:
            tunnel_service = importlib.import_module("pymobiledevice3.remote.tunnel_service")
            userspace = importlib.import_module("pymobiledevice3.remote.userspace_tunnel")
            rsd_module = importlib.import_module("pymobiledevice3.remote.remote_service_discovery")
            process_module = importlib.import_module("pymobiledevice3.services.dvt.instruments.process_control")
            provider_module = importlib.import_module("pymobiledevice3.services.dvt.instruments.dvt_provider")
            _, lockdown = self._load()
            proxy_cls = getattr(tunnel_service, "CoreDeviceTunnelProxy", None)
            dial_cls = getattr(userspace, "UserspaceDialPlane", None)
            rsd_cls = getattr(rsd_module, "RemoteServiceDiscoveryService", None)
            control_cls = getattr(process_module, "ProcessControl", None)
            provider_cls = getattr(provider_module, "DvtProvider", None)
            create = getattr(lockdown, "create_using_usbmux", None)
            if not all(callable(item) for item in (proxy_cls, dial_cls, rsd_cls, control_cls, provider_cls, create)):
                raise _management_error("runtime-api-mismatch")
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("runtime-api-mismatch") from None

        previous_flag = getattr(tunnel_service, "USE_USERSPACE_TUNNEL", False)
        stack = AsyncExitStack()
        try:
            tunnel_service.USE_USERSPACE_TUNNEL = True
            with tempfile.TemporaryDirectory(prefix="gofly-management-dvt-") as directory:
                lockdown_client = await create(
                    serial=serial,
                    label="GoFlyMac Management DVT",
                    autopair=False,
                    connection_type=self._transport,
                    pair_timeout=60,
                    pairing_records_cache_folder=Path(directory),
                )
                stack.push_async_callback(lockdown_client.close)
                if str(getattr(lockdown_client, "udid", "")).lower() != device_id.lower():
                    raise _management_error("identity-mismatch")
                proxy = await proxy_cls.create(lockdown_client)
                stack.push_async_callback(proxy.close)
                tunnel_result = await stack.enter_async_context(proxy.start_tcp_tunnel())
                tun = getattr(getattr(tunnel_result, "client", None), "tun", None)
                address = getattr(tunnel_result, "address", None)
                port = getattr(tunnel_result, "port", None)
                if tun is None or not callable(getattr(tun, "set_peer", None)) or not isinstance(address, str) or type(port) is not int:
                    raise _management_error("runtime-api-mismatch")
                tun.set_peer(address)
                dial_plane = await stack.enter_async_context(dial_cls(tun, address))
                rsd = rsd_cls(
                    (address, port),
                    open_connection=dial_plane.dial,
                    auxiliary_metadata=getattr(tunnel_result, "auxiliary_metadata", None),
                )
                stack.push_async_callback(rsd.close)
                await rsd.connect()
                if str(getattr(rsd, "udid", "")).lower() != device_id.lower():
                    raise _management_error("identity-mismatch")
                version = getattr(rsd, "product_version", None)
                if not isinstance(version, str) or OS_RE.fullmatch(version) is None:
                    raise _management_error("unsupported-os")
                yield rsd, provider_cls, control_cls
        finally:
            try:
                with contextlib.suppress(Exception):
                    await stack.aclose()
            finally:
                tunnel_service.USE_USERSPACE_TUNNEL = previous_flag

    def source_pid(self, device_id: str) -> int:
        target = self._device_id(device_id)
        serial = self._transport_serial(target)

        async def read_pid() -> int:
            async with self._dvt_control(target, serial) as (rsd, provider_cls, control_cls):
                async with provider_cls(rsd) as provider:
                    async with control_cls(provider) as control:
                        pid = await control.process_identifier_for_bundle_identifier(TARGET_BUNDLE_ID)
                        if type(pid) is not int or pid < 0:
                            raise _management_error("handoff-unknown")
                        return pid

        try:
            return _run(read_pid())
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("handoff-unknown") from None

    def stop_owned_process(self, device_id: str, expected_pid: int) -> None:
        target = self._device_id(device_id)
        if type(expected_pid) is not int or expected_pid <= 0:
            raise _management_error("identity-mismatch")
        serial = self._transport_serial(target)

        async def stop_pid() -> None:
            async with self._dvt_control(target, serial) as (rsd, provider_cls, control_cls):
                async with provider_cls(rsd) as provider:
                    async with control_cls(provider) as control:
                        current = await control.process_identifier_for_bundle_identifier(TARGET_BUNDLE_ID)
                        if type(current) is not int or current < 0:
                            raise _management_error("handoff-unknown")
                        if current == 0:
                            return
                        if current != expected_pid:
                            raise _management_error("source-busy")
                        await control.kill(expected_pid)

        try:
            _run(stop_pid())
        except ManagementBridgeError:
            raise
        except Exception:
            raise _management_error("handoff-unknown") from None


__all__ = [
    "DeviceObservation",
    "InstalledIdentity",
    "ManagementDeviceObservation",
    "ManagementInstalledIdentity",
    "ManagementUpgradeObservation",
    "PinnedManagementDeviceAdapter",
    "UpgradeObservation",
]
