"""Controlled device/process and validator seams for the M2 producer.

The protocols in this module describe real operation boundaries.  Test doubles
may implement them to control filesystem and process outcomes, but there is no
boolean "ready" or native-proof callback in the production API.
"""

from __future__ import annotations

import contextlib
import hashlib
import json
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Mapping, Protocol, Sequence

try:
    from ..Setup.setup_adapters import (
        ArtifactIdentity,
        DeviceObservation,
        InstalledAppObservation,
        PinnedPymobiledeviceAdapter,
        PinnedXcodeProcessAdapter,
        _read_private_regular,
        _run,
    )
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device
except ImportError:  # direct execution from packaged Reinstall directory
    from Setup.setup_adapters import ArtifactIdentity, DeviceObservation, InstalledAppObservation, PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, _read_private_regular, _run
    from Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device

try:
    from .reinstall_protocol import ReinstallBridgeError
except ImportError:  # pragma: no cover - direct packaged execution
    from reinstall_protocol import ReinstallBridgeError

# Local validator/copy failures must preserve M2's larger safe-code set.  Keep
# the M1 exception class available for delegated adapter failures.
_SetupBridgeError = SetupBridgeError
SetupBridgeError = ReinstallBridgeError

MAX_EXPORT_MANIFEST_BYTES = 256 * 1024
MAX_BACKUP_BYTES = 160 * 1024 * 1024
MAX_VALIDATOR_STDOUT = 256 * 1024
MAX_VALIDATOR_STDERR = 64 * 1024
MAX_BACKUP_ENTRIES = 512
MAX_BACKUP_DEPTH = 4
COUNT_LIMITS = {"favorites": 100, "importedRoutes": 100, "favoriteRoutes": 100, "draftNodes": 27, "gpxPoints": 2_010_000}
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
TRANSFER_ERROR_CODES = frozenset(
    {
        "invalid-input", "unsupported-version", "unsafe-file", "limit-exceeded",
        "identity-mismatch", "artifact-mismatch", "unavailable", "storage-unavailable",
        "commit-unknown", "receipt-capacity", "busy", "source-busy", "export-conflict",
        "update-required",
    }
)


@dataclass(frozen=True)
class SourceAppIdentity:
    bundle_id: str
    build: str
    profile_sha256: str
    executable_sha256: str

    def as_dict(self) -> dict[str, str]:
        return {
            "bundleID": self.bundle_id,
            "build": self.build,
            "profileSHA256": self.profile_sha256,
            "executableSHA256": self.executable_sha256,
        }


@dataclass(frozen=True)
class ExportReadback:
    """Actual App response observed through the device container."""

    phase: str
    transfer_id: str
    data_set_id: str
    nonce: str
    raw_manifest_sha256: str | None
    source_app: SourceAppIdentity | None
    receipt_sha256: str | None = None
    # These fields are optional for B2-compatible controlled doubles.  A real
    # adapter always fills them from the strict App response and binds them to
    # the current ProcessControl observation.
    command_id: str | None = None
    action: str | None = None
    request_sha256: str | None = None
    pid: int | None = None
    error_code: str | None = None


@dataclass(frozen=True)
class RemovalObservation:
    state: str  # absent, present, unknown


@dataclass(frozen=True)
class InstallObservation:
    state: str  # confirmed, unknown, failed
    app: Mapping[str, Any] | None = None


@dataclass(frozen=True)
class RestoreObservation:
    phase: str
    categories: tuple[Mapping[str, Any], ...] = ()
    counts: Mapping[str, int] | None = None
    receipt_sha256: str | None = None
    intent: Mapping[str, Any] | None = None
    receipt: Mapping[str, Any] | None = None


class ReinstallDeviceAdapter(Protocol):
    """One fixed set of actual device operation seams."""

    def observe(self, device_id: str) -> DeviceObservation: ...

    def installed(self, device_id: str) -> InstalledAppObservation: ...

    def source_request(self, device_id: str, request: Mapping[str, Any], control: Mapping[str, Any]) -> None: ...

    def source_readback(self, device_id: str, transfer_id: str, nonce: str) -> ExportReadback | None: ...

    def source_seal(self, device_id: str, control: Mapping[str, Any]) -> Mapping[str, Any]: ...

    def source_release(self, device_id: str, control: Mapping[str, Any]) -> Mapping[str, Any]: ...

    def source_pid(self, device_id: str) -> int: ...

    def stop_source(self, device_id: str, pid: int) -> None: ...

    def uninstall(self, device_id: str, bundle_id: str) -> None: ...

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstallObservation: ...

    def publish_restore_intent(self, device_id: str, intent: Mapping[str, Any]) -> None: ...

    def deliver_restore(self, device_id: str, transfer_id: str, package_dir: Path) -> None: ...

    def restore_readback(self, device_id: str, transfer_id: str) -> RestoreObservation | None: ...

    def support(self, device_id: str) -> Mapping[str, Any]: ...

    def copy_source_package(self, device_id: str, transfer_id: str, destination: Path) -> None: ...


class ReinstallProcessAdapter(Protocol):
    def build(self, setup_id: str, team_id: str, allow_provisioning_updates: bool = False) -> Path: ...


class TransferValidator(Protocol):
    def validate(self, backup_directory: Path) -> Mapping[str, Any]: ...


def _safe_validator_json(raw: bytes) -> Mapping[str, Any]:
    if len(raw) > MAX_VALIDATOR_STDOUT:
        raise SetupBridgeError("backup-invalid")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()), parse_float=lambda _: (_ for _ in ()).throw(ValueError()))
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError):
        raise SetupBridgeError("backup-invalid") from None
    if not isinstance(value, dict):
        raise SetupBridgeError("backup-invalid")
    expected = {
        "version", "transferID", "dataSetID", "nonce", "sourceDeviceUDID", "destinationDeviceUDID",
        "sourceApp", "targetApp", "setupID", "categories", "rawManifestSHA256", "counts",
    }
    if set(value) != expected or value.get("version") != 1:
        raise SetupBridgeError("backup-invalid")
    for key in ("transferID", "dataSetID", "nonce", "setupID"):
        if not isinstance(value.get(key), str) or UUID.fullmatch(value[key]) is None or value[key] != value[key].lower():
            raise SetupBridgeError("backup-invalid")
    for key in ("sourceDeviceUDID", "destinationDeviceUDID"):
        try:
            if normalized_device(value.get(key)) != value[key]:
                raise SetupBridgeError("backup-invalid")
        except (_SetupBridgeError, SetupBridgeError):
            raise SetupBridgeError("backup-invalid") from None
    for key in ("sourceApp", "targetApp"):
        app = value.get(key)
        if not isinstance(app, Mapping) or set(app) != {"bundleID", "build", "profileSHA256", "executableSHA256"} or app.get("bundleID") != TARGET_BUNDLE_ID:
            raise SetupBridgeError("backup-invalid")
        if not isinstance(app.get("build"), str) or not app["build"] or not HEX64.fullmatch(app.get("profileSHA256", "")) or not HEX64.fullmatch(app.get("executableSHA256", "")):
            raise SetupBridgeError("backup-invalid")
    categories = value.get("categories")
    if not isinstance(categories, list) or any(not isinstance(item, str) for item in categories):
        raise SetupBridgeError("backup-invalid")
    if tuple(categories) != tuple(item for item in ("favorites", "routes", "settings") if item in categories) or len(categories) != len(set(categories)):
        raise SetupBridgeError("backup-invalid")
    if not HEX64.fullmatch(value.get("rawManifestSHA256", "")):
        raise SetupBridgeError("backup-invalid")
    counts = value.get("counts")
    if not isinstance(counts, Mapping) or set(counts) != set(COUNT_LIMITS) or any(type(counts[item]) is not int or counts[item] < 0 or counts[item] > COUNT_LIMITS[item] for item in counts):
        raise SetupBridgeError("backup-invalid")
    if "favorites" not in categories and counts["favorites"] != 0:
        raise SetupBridgeError("backup-invalid")
    if "routes" not in categories and any(counts[item] != 0 for item in ("importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints")):
        raise SetupBridgeError("backup-invalid")
    return value


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate")
        result[key] = value
    return result


class SwiftTransferValidator:
    """Run the fixed bundled Swift semantic validator as a subprocess."""

    def __init__(self, validator_path: str | Path, *, timeout: float = 30.0):
        self.validator_path = Path(validator_path)
        self.timeout = timeout

    def validate(self, backup_directory: Path) -> Mapping[str, Any]:
        if not self.validator_path.is_absolute() or self.validator_path.name != "GoFlyTransferValidator" or backup_directory.is_symlink() or not backup_directory.is_dir():
            raise SetupBridgeError("backup-invalid")
        process: subprocess.Popen[bytes] | None = None
        stdout = bytearray()
        stderr = bytearray()
        stdout_overflow = False
        stderr_overflow = False

        def drain(stream: Any, output: bytearray, limit: int, marker: list[bool]) -> None:
            """Drain a child pipe concurrently while retaining only its bound."""
            try:
                while True:
                    chunk = stream.read(64 * 1024)
                    if not chunk:
                        return
                    available = max(0, limit - len(output))
                    if available:
                        output.extend(chunk[:available])
                    if len(chunk) > available:
                        marker[0] = True
            except Exception:
                marker[0] = True

        try:
            process = subprocess.Popen(
                [str(self.validator_path), "validate", str(backup_directory)],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                shell=False,
            )
            out_marker = [False]
            err_marker = [False]
            out_thread = threading.Thread(target=drain, args=(process.stdout, stdout, MAX_VALIDATOR_STDOUT, out_marker), daemon=True)
            err_thread = threading.Thread(target=drain, args=(process.stderr, stderr, MAX_VALIDATOR_STDERR, err_marker), daemon=True)
            out_thread.start()
            err_thread.start()
            try:
                process.wait(timeout=self.timeout)
            except subprocess.TimeoutExpired:
                with contextlib.suppress(OSError):
                    process.kill()
                with contextlib.suppress(subprocess.TimeoutExpired):
                    process.wait(timeout=1)
                out_thread.join(timeout=1)
                err_thread.join(timeout=1)
                with contextlib.suppress(Exception):
                    process.stdout.close()
                with contextlib.suppress(Exception):
                    process.stderr.close()
                raise SetupBridgeError("timeout") from None
            out_thread.join(timeout=1)
            err_thread.join(timeout=1)
            stdout_overflow = out_marker[0]
            stderr_overflow = err_marker[0]
            with contextlib.suppress(Exception):
                process.stdout.close()
            with contextlib.suppress(Exception):
                process.stderr.close()
        except OSError:
            raise SetupBridgeError("environment-not-ready") from None
        finally:
            if process is not None and process.poll() is None:
                with contextlib.suppress(OSError):
                    process.kill()
                with contextlib.suppress(Exception):
                    process.wait(timeout=1)
        if stdout_overflow or stderr_overflow or len(stdout) > MAX_VALIDATOR_STDOUT or len(stderr) > MAX_VALIDATOR_STDERR:
            raise SetupBridgeError("backup-invalid")
        if process is None or process.returncode != 0:
            raise SetupBridgeError("backup-invalid")
        return _safe_validator_json(bytes(stdout))


def _copy_regular(source: Path, destination: Path, *, max_bytes: int = MAX_BACKUP_BYTES) -> None:
    """Copy one source file through no-follow descriptors and fsync it."""
    try:
        source_fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
        info = os.fstat(source_fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size < 0 or info.st_size > max_bytes:
            raise SetupBridgeError("backup-invalid")
        destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        destination_fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), 0o600)
        try:
            remaining = info.st_size
            while remaining:
                data = os.read(source_fd, min(1024 * 1024, remaining))
                if not data:
                    raise SetupBridgeError("backup-invalid")
                offset = 0
                while offset < len(data):
                    written = os.write(destination_fd, data[offset:])
                    if written <= 0:
                        raise SetupBridgeError("backup-invalid")
                    offset += written
                remaining -= len(data)
            os.fsync(destination_fd)
        finally:
            os.close(destination_fd)
        if os.fstat(source_fd).st_size != info.st_size:
            raise SetupBridgeError("backup-invalid")
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("backup-invalid") from None
    finally:
        with contextlib.suppress(UnboundLocalError, OSError):
            os.close(source_fd)


def _bounded_tree(
    root: Path,
    *,
    maximum_entries: int = MAX_BACKUP_ENTRIES,
    maximum_depth: int = MAX_BACKUP_DEPTH,
    directory_validator: Callable[[Path, os.stat_result, str], None] | None = None,
) -> list[tuple[Path, os.stat_result, Path]]:
    """Enumerate a regular-file tree through lstat-only bounded steps."""
    try:
        root_info = os.lstat(root)
    except OSError:
        raise SetupBridgeError("backup-invalid") from None
    if stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode):
        raise SetupBridgeError("backup-invalid")
    found: list[tuple[Path, os.stat_result, Path]] = []
    pending: list[tuple[Path, Path, int]] = [(root, Path(), 0)]
    while pending:
        directory, relative_directory, depth = pending.pop()
        if depth > maximum_depth:
            raise SetupBridgeError("backup-invalid")
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    relative = relative_directory / entry.name
                    entry_depth = len(relative.parts)
                    if entry_depth > maximum_depth:
                        raise SetupBridgeError("backup-invalid")
                    if len(found) >= maximum_entries:
                        raise SetupBridgeError("backup-invalid")
                    try:
                        info = entry.stat(follow_symlinks=False)
                    except OSError:
                        raise SetupBridgeError("backup-invalid") from None
                    if stat.S_ISLNK(info.st_mode):
                        raise SetupBridgeError("backup-invalid")
                    path = directory / entry.name
                    found.append((path, info, relative))
                    if stat.S_ISDIR(info.st_mode):
                        if directory_validator is not None:
                            directory_validator(path, info, relative.as_posix())
                        pending.append((path, relative, entry_depth))
                    elif not stat.S_ISREG(info.st_mode):
                        raise SetupBridgeError("backup-invalid")
        except SetupBridgeError:
            raise
        except OSError:
            raise SetupBridgeError("backup-invalid") from None
    return sorted(found, key=lambda item: item[2].as_posix())


def copy_validated_package(source: Path, destination: Path) -> None:
    """Copy a bounded regular-file tree while preserving fixed relative paths."""
    if source.is_symlink() or not source.is_dir() or destination.is_symlink():
        raise SetupBridgeError("backup-invalid")
    if destination.exists():
        if not destination.is_dir() or any(destination.iterdir()):
            raise SetupBridgeError("backup-invalid")
    else:
        destination.mkdir(parents=True, mode=0o700)
    total = 0
    try:
        for path, info, relative in _bounded_tree(source):
            if any(part in {"", ".", ".."} for part in relative.parts):
                raise SetupBridgeError("backup-invalid")
            target = destination / relative
            if stat.S_ISDIR(info.st_mode):
                target.mkdir(mode=0o700)
                continue
            if not stat.S_ISREG(info.st_mode):
                raise SetupBridgeError("backup-invalid")
            total += info.st_size
            if total > MAX_BACKUP_BYTES:
                raise SetupBridgeError("backup-invalid")
            _copy_regular(path, target)
        directory_fd = os.open(destination, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("backup-invalid") from None


class PinnedReinstallDeviceAdapter:
    """Pinned production M2 boundary.

    Every path below is fixed by the transfer protocol.  The adapter owns no
    generic container or callback API: it opens the selected USB device, vends
    only GoFly's container, and verifies each response against the immutable
    local transaction identity before returning to the producer.
    """

    _TRANSFER_ROOT = "Library/Application Support/GoFlyTransfer"
    _EXPORT_REQUEST = _TRANSFER_ROOT + "/export-request.json"
    _CONTROL_REQUEST = _TRANSFER_ROOT + "/control-request.json"
    _CONTROL_RESPONSE = _TRANSFER_ROOT + "/control-response.json"
    _RESTORE_INTENT = _TRANSFER_ROOT + "/restore-intent.json"
    _RESTORE_RESPONSE = _TRANSFER_ROOT + "/restore-response.json"
    _MAX_RESPONSE_BYTES = 256 * 1024

    def __init__(self, config: Any):
        self.config = config
        self._base = PinnedPymobiledeviceAdapter(state_root=config.state_root)
        self._source_apps: dict[tuple[str, str], SourceAppIdentity] = {}
        self._request_hashes: dict[tuple[str, str], str] = {}
        self._installed_artifacts: dict[str, ArtifactIdentity] = {}

    def observe(self, device_id: str) -> DeviceObservation:
        return self._base.observe(device_id)

    def installed(self, device_id: str) -> InstalledAppObservation:
        # M1's lookup establishes presence; M2 additionally needs the actual
        # installed build before it freezes the export header.  Read the
        # installation-proxy record directly so a missing build is preserved
        # as unknown instead of being replaced by a local journal value.
        client = None
        service = None
        try:
            self.observe(device_id)
            module = __import__("pymobiledevice3.services.installation_proxy", fromlist=["InstallationProxyService"])
            service_cls = getattr(module, "InstallationProxyService", None)
            if service_cls is None:
                raise _SetupBridgeError("runtime-api-mismatch")
            with tempfile.TemporaryDirectory(prefix="gofly-reinstall-installed-") as directory:
                client = self._base._open(device_id, Path(directory))
                service = service_cls(client)
                apps = _run(service.get_apps(bundle_identifiers=[TARGET_BUNDLE_ID]))
                if not isinstance(apps, Mapping):
                    raise _SetupBridgeError("runtime-api-mismatch")
                value = apps.get(TARGET_BUNDLE_ID)
                if value is None:
                    self.observe(device_id)
                    return InstalledAppObservation(False)
                if not isinstance(value, Mapping):
                    raise _SetupBridgeError("runtime-api-mismatch")
                if "CFBundleVersion" in value:
                    build = value.get("CFBundleVersion")
                    if not isinstance(build, str) or not build:
                        raise _SetupBridgeError("runtime-api-mismatch")
                else:
                    build = value.get("CFBundleShortVersionString")
                    if build is not None and (not isinstance(build, str) or not build):
                        raise _SetupBridgeError("runtime-api-mismatch")
                if build is None:
                    # Presence is real, but build authority is unavailable;
                    # callers must keep the operation unresolved.
                    self.observe(device_id)
                    return InstalledAppObservation(True, TARGET_BUNDLE_ID, build=None)
                self.observe(device_id)
                return InstalledAppObservation(True, TARGET_BUNDLE_ID, build=build)
        except _SetupBridgeError:
            raise
        except Exception:
            raise _SetupBridgeError("trust-required") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def install(self, device_id: str, artifact: ArtifactIdentity) -> InstallObservation:
        self.observe(device_id)
        try:
            observed = self._base.install(device_id, artifact)
        except _SetupBridgeError:
            raise
        if not observed.present:
            return InstallObservation("unknown")
        # InstallationProxy's first response is followed by the same strict
        # precedence lookup used by the public installed-build boundary.  A
        # malformed primary build key can therefore never be replaced by a
        # short-version fallback and a mismatched build cannot become a
        # confirmed install.
        confirmed = self.installed(device_id)
        if not confirmed.present or confirmed.build != artifact.build:
            raise SetupBridgeError("artifact-mismatch")
        self._installed_artifacts[device_id.lower()] = artifact
        return InstallObservation(
            "confirmed",
            {
                "bundleID": observed.bundle_id,
                "build": confirmed.build,
                "profileSHA256": artifact.profile_sha256,
                "executableSHA256": artifact.executable_sha256,
            },
        )

    # ---- embedded M1 setup boundaries -----------------------------------

    # The embedded producer reuses M1's private stage code while retaining
    # this adapter as its only device boundary.  These are deliberately
    # narrow compositions over the pinned M1 implementation; no new generic
    # container or native-proof seam is exposed here.
    def pair(self, device_id: str, candidate: Path) -> Any:
        return self._base.pair(device_id, candidate)

    def verify_pairing(self, device_id: str, candidate: Path) -> Any:
        return self._base.verify_pairing(device_id, candidate)

    def prepare_readback(self, device_id: str, setup_id: str, nonce: str, artifact: ArtifactIdentity) -> None:
        self._base.prepare_readback(device_id, setup_id, nonce, artifact)

    def deliver_pairing(self, device_id: str, setup_id: str) -> None:
        # Standalone M1 keeps its pairing envelope in the M1 journal.  The
        # embedded M1 port deliberately has no second journal, so consume the
        # parent-owned nested setup record when that is the active transaction.
        try:
            from ..Setup.setup_journal import JournalStore
            from .reinstall_journal import ReinstallJournalStore
        except ImportError:  # direct packaged execution
            from Setup.setup_journal import JournalStore
            from reinstall_journal import ReinstallJournalStore
        m1_journal = JournalStore(self.config.state_root).read()
        if isinstance(m1_journal, Mapping) and m1_journal.get("setupID") == self._uuid(setup_id, error="transaction-conflict"):
            self._base.deliver_pairing(device_id, setup_id)
            return
        parent = ReinstallJournalStore(self.config.state_root).read()
        nested = parent.get("setup") if isinstance(parent, Mapping) else None
        if not isinstance(parent, Mapping) or parent.get("setupID") != self._uuid(setup_id, error="transaction-conflict") or not isinstance(nested, Mapping):
            raise SetupBridgeError("transaction-conflict")
        try:
            if normalized_device(parent.get("deviceID")) != normalized_device(device_id):
                raise SetupBridgeError("identity-mismatch")
            intent = nested.get("intent")
            pairing = nested.get("pairing")
            transaction_id = intent.get("pairingTransactionID") if isinstance(intent, Mapping) else None
            expected_sha = pairing.get("sha256") if isinstance(pairing, Mapping) else None
            transaction_id = self._uuid(transaction_id, error="pairing-unknown")
            if not isinstance(expected_sha, str) or not HEX64.fullmatch(expected_sha):
                raise SetupBridgeError("pairing-unknown")
            candidate = self._transaction_root(setup_id) / "pairing.candidate"
            raw = _read_private_regular(candidate, max_bytes=1024 * 1024)
            if hashlib.sha256(raw).hexdigest() != expected_sha:
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
            if len(payload) > 1 * 1024 * 1024 + 64 * 1024:
                raise SetupBridgeError("pairing-unknown")
            self._base._publish_house_arrest(
                device_id,
                "Library/Application Support/LocalGoSetup/incoming.plist",
                payload,
                conflict_code="handoff-unknown",
            )
        except (_SetupBridgeError, SetupBridgeError):
            raise
        except Exception:
            raise SetupBridgeError("pairing-unknown") from None

    def prepare_setup_input(
        self,
        device_id: str,
        setup_id: str,
        nonce: str,
        artifact: ArtifactIdentity,
        pairing_transaction_id: str,
        pairing_sha256: str,
        support: Mapping[str, Any],
        *,
        plan: Any,
    ) -> str:
        return self._base.prepare_setup_input(
            device_id,
            setup_id,
            nonce,
            artifact,
            pairing_transaction_id,
            pairing_sha256,
            support,
            plan=plan,
        )

    def formal_inventory(self, setup_id: str, nonce: str) -> tuple[tuple[str, str, int, str], ...]:
        return self._base.formal_inventory(setup_id, nonce)

    def readback(self, device_id: str, setup_id: str, nonce: str) -> Any:
        return self._base.readback(device_id, setup_id, nonce)

    def read_activation_receipt(self, device_id: str, setup_id: str, nonce: str) -> Any:
        return self._base.read_activation_receipt(device_id, setup_id, nonce)

    def query_support(self, device_id: str, method: str) -> Any:
        return self._base.query_support(device_id, method)

    def install_support(self, device_id: str, method: str, restore_dir: Path) -> Any:
        return self._base.install_support(device_id, method, restore_dir)

    def prepare_generation(self, method: str, restore_dir: Path) -> Any:
        return self._base.prepare_generation(method, restore_dir)

    def launch(self, device_id: str) -> int:
        return self._base.launch(device_id)

    def stop(self, device_id: str, expected_pid: int | None = None) -> None:
        self._base.stop(device_id, expected_pid)

    # ---- fixed local and JSON boundaries ---------------------------------

    @staticmethod
    def _json_bytes(value: Mapping[str, Any], *, maximum: int) -> bytes:
        try:
            raw = json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        except (TypeError, ValueError, UnicodeError):
            raise SetupBridgeError("invalid-request") from None
        if len(raw) > maximum:
            raise SetupBridgeError("backup-invalid")
        return raw

    @staticmethod
    def _decode_json(data: bytes, *, maximum: int) -> Mapping[str, Any]:
        if not isinstance(data, bytes) or len(data) > maximum:
            raise SetupBridgeError("backup-invalid")
        try:
            value = json.loads(
                data.decode("utf-8"),
                object_pairs_hook=_pairs,
                parse_constant=lambda _: (_ for _ in ()).throw(ValueError()),
                parse_float=lambda _: (_ for _ in ()).throw(ValueError()),
            )
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError):
            raise SetupBridgeError("backup-invalid") from None
        if not isinstance(value, Mapping):
            raise SetupBridgeError("backup-invalid")
        return value

    @staticmethod
    def _uuid(value: Any, *, error: str = "transaction-conflict") -> str:
        if not isinstance(value, str) or UUID.fullmatch(value) is None or value != value.lower():
            raise SetupBridgeError(error)
        return value

    @staticmethod
    def _hash(value: Any, *, nullable: bool = False, error: str = "backup-invalid") -> str | None:
        if nullable and value is None:
            return None
        if not isinstance(value, str) or not HEX64.fullmatch(value):
            raise SetupBridgeError(error)
        return value

    @staticmethod
    def _app(value: Any, *, error: str = "export-conflict") -> SourceAppIdentity:
        if not isinstance(value, Mapping) or set(value) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
            raise SetupBridgeError(error)
        if value.get("bundleID") != TARGET_BUNDLE_ID:
            raise SetupBridgeError(error)
        build = value.get("build")
        if not isinstance(build, str) or not build or len(build.encode("utf-8")) > 128 or any(ord(char) < 0x20 for char in build):
            raise SetupBridgeError(error)
        profile = PinnedReinstallDeviceAdapter._hash(value.get("profileSHA256"), error=error)
        executable = PinnedReinstallDeviceAdapter._hash(value.get("executableSHA256"), error=error)
        assert isinstance(profile, str) and isinstance(executable, str)
        return SourceAppIdentity(TARGET_BUNDLE_ID, build, profile, executable)

    def _transaction_root(self, transfer_id: str) -> Path:
        transfer = self._uuid(transfer_id)
        root = Path(self.config.state_root) / "transactions" / transfer
        if root.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        return root

    @staticmethod
    def _ensure_private_directory(path: Path) -> None:
        parts = path.parts
        current = Path(path.anchor or "/")
        for part in parts[1:] if path.is_absolute() else parts:
            current = current / part
            if current.exists() or current.is_symlink():
                if current.is_symlink() or not current.is_dir():
                    raise SetupBridgeError("storage-unavailable")
            else:
                try:
                    current.mkdir(mode=0o700)
                except OSError:
                    raise SetupBridgeError("storage-unavailable") from None

    @staticmethod
    def _validate_private_inventory(root: Path, expected_paths: set[str], *, require_complete: bool) -> None:
        """Validate a private backup tree before or after AFC transfer."""
        try:
            root_info = os.lstat(root)
            owner = os.getuid()
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        if stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode):
            raise SetupBridgeError("storage-unavailable")
        if root_info.st_uid != owner or stat.S_IMODE(root_info.st_mode) != 0o700:
            raise SetupBridgeError("storage-unavailable")
        expected = set(expected_paths)
        seen: set[str] = set()

        def validate_directory(_path: Path, info: os.stat_result, name: str) -> None:
            if info.st_uid != owner or stat.S_IMODE(info.st_mode) != 0o700:
                raise SetupBridgeError("storage-unavailable")
            prefix = name + "/"
            if not any(item.startswith(prefix) for item in expected):
                raise SetupBridgeError("backup-invalid")

        for path, info, relative in _bounded_tree(root, directory_validator=validate_directory):
            name = relative.as_posix()
            if stat.S_ISDIR(info.st_mode):
                continue
            if not stat.S_ISREG(info.st_mode):
                raise SetupBridgeError("backup-invalid")
            if info.st_uid != owner or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != 0o600:
                raise SetupBridgeError("storage-unavailable")
            if name not in expected:
                raise SetupBridgeError("backup-invalid")
            seen.add(name)
        if require_complete and seen != expected:
            raise SetupBridgeError("backup-invalid")

    @staticmethod
    def _write_private_file(path: Path, data: bytes, *, maximum: int) -> None:
        if len(data) > maximum or path.is_symlink():
            raise SetupBridgeError("backup-invalid")
        PinnedReinstallDeviceAdapter._ensure_private_directory(path.parent)
        if path.exists():
            try:
                existing = _read_private_regular(path, max_bytes=maximum)
            except _SetupBridgeError:
                raise SetupBridgeError("storage-unavailable") from None
            if existing != data:
                raise SetupBridgeError("transaction-conflict")
            return
        temporary: Path | None = None
        fd: int | None = None
        try:
            fd, name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
            temporary = Path(name)
            os.fchmod(fd, 0o600)
            offset = 0
            while offset < len(data):
                written = os.write(fd, data[offset:])
                if written <= 0:
                    raise OSError("short write")
                offset += written
            os.fsync(fd)
            os.close(fd)
            fd = None
            os.rename(temporary, path)
            temporary = None
            directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        except SetupBridgeError:
            raise
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        finally:
            if fd is not None:
                with contextlib.suppress(OSError):
                    os.close(fd)
            if temporary is not None:
                with contextlib.suppress(OSError):
                    temporary.unlink()

    def _expected_backup(self, transfer_id: str) -> Path:
        return self._transaction_root(transfer_id) / "backup"

    # ---- pmd3 service and process boundaries -----------------------------

    @contextlib.contextmanager
    def _house_arrest(self, device_id: str):
        client = None
        service = None
        try:
            module = __import__("pymobiledevice3.services.house_arrest", fromlist=["HouseArrestService"])
            service_cls = getattr(module, "HouseArrestService", None)
            if service_cls is None or not callable(getattr(service_cls, "create", None)):
                raise SetupBridgeError("runtime-api-mismatch")
            with tempfile.TemporaryDirectory(prefix="gofly-reinstall-afc-") as directory:
                self.observe(device_id)
                client = self._base._open(device_id, Path(directory))
                service = _run(service_cls.create(client, TARGET_BUNDLE_ID, documents_only=False))
                yield service
                self.observe(device_id)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def _process_call(self, device_id: str, callback: Any) -> Any:
        client = None
        try:
            module = __import__("pymobiledevice3.services.dvt.instruments.process_control", fromlist=["ProcessControl"])
            provider_module = __import__("pymobiledevice3.services.dvt.instruments.dvt_provider", fromlist=["DvtProvider"])
            control_cls = getattr(module, "ProcessControl", None)
            provider_cls = getattr(provider_module, "DvtProvider", None)
            if control_cls is None or provider_cls is None:
                raise SetupBridgeError("runtime-api-mismatch")
            with tempfile.TemporaryDirectory(prefix="gofly-reinstall-process-") as directory:
                self.observe(device_id)
                client = self._base._open(device_id, Path(directory))

                async def run() -> Any:
                    async with provider_cls(client) as provider:
                        async with control_cls(provider) as control:
                            return await callback(control)

                return _run(run())
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("handoff-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    def _current_pid(self, device_id: str) -> int:
        async def read(control: Any) -> int:
            value = await control.process_identifier_for_bundle_identifier(TARGET_BUNDLE_ID)
            if type(value) is not int or value < 0:
                raise SetupBridgeError("handoff-unknown")
            return value

        return self._process_call(device_id, read)

    def _signal_source(self, device_id: str, transfer_id: str, nonce: str) -> int:
        """Deliver the closed export URL through the fixed Xcode devicectl.

        The command result is only transport evidence.  USB and live PID
        observations immediately before and after the subprocess are the
        boundary checks; the App response remains the delivery authority.
        """
        try:
            before_usb = self.observe(device_id)
            before_pid = self._current_pid(device_id)
            transfer = self._uuid(transfer_id, error="invalid-request")
            nonce_value = self._uuid(nonce, error="invalid-request")
            developer = getattr(self.config, "developer_directory", None)
            if not isinstance(developer, (str, Path)) or not str(developer).startswith("/"):
                raise SetupBridgeError("configuration-invalid")
            argv = [
                "/usr/bin/xcrun",
                "devicectl",
                "device",
                "process",
                "launch",
                "--device",
                before_usb.device_id,
                "--payload-url",
                f"gofly://transfer/export?id={transfer}&nonce={nonce_value}",
                TARGET_BUNDLE_ID,
            ]
            environment = os.environ.copy()
            environment["DEVELOPER_DIR"] = str(developer)
            result: subprocess.CompletedProcess[bytes] | None = None
            command_error: str | None = None
            try:
                result = subprocess.run(
                    argv,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=environment,
                    timeout=30,
                    check=False,
                )
            except subprocess.TimeoutExpired:
                command_error = "update-required"
            except OSError:
                command_error = "update-required"
            after_usb = self.observe(device_id)
            after_pid = self._current_pid(device_id)
            if before_usb != after_usb:
                raise SetupBridgeError("device-disconnected")
            if before_pid != 0 and after_pid != before_pid:
                raise SetupBridgeError("source-busy")
            if command_error is not None:
                raise SetupBridgeError(command_error)
            if result is None or result.returncode != 0:
                raise SetupBridgeError("update-required")
            return after_pid
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("update-required") from None

    # ---- strict transfer records -----------------------------------------

    def _export_request(self, request: Mapping[str, Any], device_id: str) -> tuple[bytes, str]:
        required = {
            "version", "transferID", "dataSetID", "nonce", "sourceDeviceUDID", "destinationDeviceUDID",
            "sourceBundleID", "sourceBuild", "targetApp", "setupID", "categories",
        }
        if set(request) != required or request.get("version") != 1:
            raise SetupBridgeError("invalid-request")
        transfer = self._uuid(request.get("transferID"), error="invalid-request")
        self._uuid(request.get("dataSetID"), error="invalid-request")
        self._uuid(request.get("nonce"), error="invalid-request")
        self._uuid(request.get("setupID"), error="invalid-request")
        try:
            selected = normalized_device(device_id)
            if normalized_device(request.get("sourceDeviceUDID")) != selected or normalized_device(request.get("destinationDeviceUDID")) != selected:
                raise SetupBridgeError("identity-mismatch")
        except (_SetupBridgeError, SetupBridgeError):
            raise SetupBridgeError("identity-mismatch") from None
        if request.get("sourceBundleID") != TARGET_BUNDLE_ID:
            raise SetupBridgeError("identity-mismatch")
        source_build = request.get("sourceBuild")
        if not isinstance(source_build, str) or not source_build or len(source_build.encode("utf-8")) > 128 or any(ord(char) < 0x20 for char in source_build):
            raise SetupBridgeError("invalid-request")
        self._app(request.get("targetApp"), error="identity-mismatch")
        categories = request.get("categories")
        if not isinstance(categories, list) or tuple(categories) != tuple(item for item in ("favorites", "routes", "settings") if item in categories) or len(categories) != len(set(categories)):
            raise SetupBridgeError("invalid-request")
        if any(item not in {"favorites", "routes", "settings"} for item in categories):
            raise SetupBridgeError("invalid-request")
        raw = self._json_bytes(request, maximum=MAX_EXPORT_MANIFEST_BYTES)
        return raw, hashlib.sha256(raw).hexdigest()

    @staticmethod
    def _allowed_artifact(path: Any) -> bool:
        if not isinstance(path, str) or not path or "\\" in path or "%" in path or path.startswith("/") or "//" in path:
            return False
        parts = path.split("/")
        if any(part in {"", ".", ".."} for part in parts):
            return False
        if path in {"favorites/archive.json", "routes/imported/manifest.json", "routes/favorites/manifest.json", "routes/draft.json", "settings/preferences.json"}:
            return True
        if len(parts) != 3 or parts[0] != "routes" or parts[1] not in {"imported", "favorites"}:
            return False
        suffix = ".gpx" if parts[1] == "imported" else ".route"
        if not parts[2].endswith(suffix):
            return False
        stem = parts[2][:-len(suffix)]
        try:
            return str(uuid.UUID(stem)).upper() == stem
        except (ValueError, AttributeError, TypeError):
            return False

    def _manifest(self, raw: bytes, *, device_id: str, transfer_id: str, expected_sha: str | None = None) -> Mapping[str, Any]:
        if expected_sha is not None and hashlib.sha256(raw).hexdigest() != expected_sha:
            raise SetupBridgeError("export-conflict")
        value = self._decode_json(raw, maximum=MAX_EXPORT_MANIFEST_BYTES)
        required = {"version", "transferID", "dataSetID", "nonce", "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp", "targetApp", "setupID", "categories", "schemas", "artifacts"}
        if set(value) != required or value.get("version") != 1:
            raise SetupBridgeError("backup-invalid")
        transfer = self._uuid(value.get("transferID"))
        if transfer != transfer_id:
            raise SetupBridgeError("export-conflict")
        data_set = self._uuid(value.get("dataSetID"))
        nonce = self._uuid(value.get("nonce"))
        setup = self._uuid(value.get("setupID"))
        try:
            selected = normalized_device(device_id)
            if normalized_device(value.get("sourceDeviceUDID")) != selected or normalized_device(value.get("destinationDeviceUDID")) != selected:
                raise SetupBridgeError("identity-mismatch")
        except (_SetupBridgeError, SetupBridgeError):
            raise SetupBridgeError("identity-mismatch") from None
        self._app(value.get("sourceApp"), error="backup-invalid")
        self._app(value.get("targetApp"), error="backup-invalid")
        categories = value.get("categories")
        if not isinstance(categories, list) or tuple(categories) != tuple(item for item in ("favorites", "routes", "settings") if item in categories) or len(categories) != len(set(categories)) or any(item not in {"favorites", "routes", "settings"} for item in categories):
            raise SetupBridgeError("backup-invalid")
        schemas = value.get("schemas")
        if not isinstance(schemas, Mapping) or set(schemas) != set(categories) or any(type(schemas[name]) is not int or schemas[name] != 1 for name in categories):
            raise SetupBridgeError("backup-invalid")
        artifacts = value.get("artifacts")
        if not isinstance(artifacts, list) or len(artifacts) > 210:
            raise SetupBridgeError("backup-invalid")
        seen_ids: set[str] = set()
        seen_paths: set[str] = set()
        total = 0
        for item in artifacts:
            if not isinstance(item, Mapping) or set(item) != {"id", "path", "byteCount", "sha256"}:
                raise SetupBridgeError("backup-invalid")
            item_id = self._uuid(item.get("id"), error="backup-invalid")
            path = item.get("path")
            size = item.get("byteCount")
            digest = item.get("sha256")
            if item_id in seen_ids or path in seen_paths or not self._allowed_artifact(path) or type(size) is not int or size <= 0 or size > MAX_BACKUP_BYTES or not HEX64.fullmatch(digest or ""):
                raise SetupBridgeError("backup-invalid")
            if path.startswith("favorites/") and "favorites" not in categories:
                raise SetupBridgeError("backup-invalid")
            if path.startswith("routes/") and "routes" not in categories:
                raise SetupBridgeError("backup-invalid")
            if path.startswith("settings/") and "settings" not in categories:
                raise SetupBridgeError("backup-invalid")
            seen_ids.add(item_id)
            seen_paths.add(path)
            total += size
            if total > MAX_BACKUP_BYTES:
                raise SetupBridgeError("backup-invalid")
        if total + len(raw) > MAX_BACKUP_BYTES:
            raise SetupBridgeError("backup-invalid")
        # Return a tiny normalized tuple only for local iteration; the raw
        # manifest remains the durable authority and is never re-encoded.
        _ = (data_set, nonce, setup)
        return value

    def _read_private_request_hash(self, transfer_id: str) -> str:
        key = (transfer_id, str(Path(self.config.state_root)).lower())
        if key in self._request_hashes:
            return self._request_hashes[key]
        path = self._transaction_root(transfer_id) / "export-request.json"
        try:
            raw = _read_private_regular(path, max_bytes=MAX_EXPORT_MANIFEST_BYTES)
        except _SetupBridgeError:
            raise SetupBridgeError("source-busy") from None
        digest = hashlib.sha256(raw).hexdigest()
        self._request_hashes[key] = digest
        return digest

    def _response(self, service: Any, path: str) -> Mapping[str, Any] | None:
        if not self._base._remote_exists(service, path):
            return None
        return self._decode_json(self._base._read_remote_bounded(service, path, max_bytes=self._MAX_RESPONSE_BYTES), maximum=self._MAX_RESPONSE_BYTES)

    @staticmethod
    def _allowed_response_phases(command: Mapping[str, Any]) -> set[str] | None:
        action = command.get("action")
        if action == "export":
            return {"waiting", "preparing", "ready", "failed"}
        if action == "seal":
            return {"waiting", "preparing", "ready", "removalSealed", "failed"}
        if action == "release":
            if command.get("manifestSHA256") is None:
                return {"waiting", "preparing", "ready", "releasedNoSnapshot", "failed"}
            return {"waiting", "preparing", "ready", "released", "failed"}
        return None

    def _source_response(self, device_id: str, transfer_id: str, nonce: str) -> ExportReadback | None:
        transfer = self._uuid(transfer_id)
        nonce_value = self._uuid(nonce)
        request_sha = self._read_private_request_hash(transfer)
        response_value: Mapping[str, Any] | None
        control_value: Mapping[str, Any] | None
        control_raw: bytes
        with self._house_arrest(device_id) as service:
            response_value = self._response(service, self._CONTROL_RESPONSE)
            if not self._base._remote_exists(service, self._CONTROL_REQUEST):
                raise SetupBridgeError("source-busy")
            control_raw = self._base._read_remote_bounded(service, self._CONTROL_REQUEST, max_bytes=self._MAX_RESPONSE_BYTES)
            control_value = self._decode_json(control_raw, maximum=self._MAX_RESPONSE_BYTES)
        if response_value is None or control_value is None:
            return None
        command, canonical_control, _ = self._control_value(control_value, device_id=device_id)
        if canonical_control != control_raw:
            raise SetupBridgeError("export-conflict")
        required = {"version", "commandID", "action", "transferID", "nonce", "requestSHA256", "manifestSHA256", "sourceApp", "pid", "phase", "receiptSHA256", "errorCode"}
        if set(response_value) != required or response_value.get("version") != 1:
            raise SetupBridgeError("source-busy")
        command_id = self._uuid(response_value.get("commandID"), error="source-busy")
        if response_value.get("commandID") != command.get("commandID") or response_value.get("action") != command.get("action") or response_value.get("transferID") != transfer or response_value.get("nonce") != nonce_value or response_value.get("requestSHA256") != request_sha:
            raise SetupBridgeError("export-conflict")
        source = self._app(response_value.get("sourceApp"), error="source-busy")
        pid = response_value.get("pid")
        if type(pid) is not int or pid <= 0:
            raise SetupBridgeError("source-busy")
        phase = response_value.get("phase")
        if not isinstance(phase, str) or phase not in {"waiting", "preparing", "ready", "removalSealed", "released", "releasedNoSnapshot", "failed"}:
            raise SetupBridgeError("source-busy")
        allowed_phases = self._allowed_response_phases(command)
        if allowed_phases is None or phase not in allowed_phases:
            raise SetupBridgeError("export-conflict")
        manifest = self._hash(response_value.get("manifestSHA256"), nullable=True, error="source-busy")
        command_manifest = command.get("manifestSHA256")
        observed_ready = (
            command.get("action") in {"export", "release"}
            and command_manifest is None
            and phase == "ready"
            and manifest is not None
        )
        if observed_ready and command.get("action") == "release" and response_value.get("errorCode") != "export-conflict":
            raise SetupBridgeError("export-conflict")
        if phase in {"ready", "removalSealed", "released"} and manifest is None:
            raise SetupBridgeError("source-busy")
        if phase in {"preparing", "waiting", "releasedNoSnapshot", "failed"} and manifest is not None:
            raise SetupBridgeError("export-conflict")
        # Waiting/failed responses describe an unsuccessful current command;
        # their observed manifest is intentionally null even when the command
        # carried a previously bound full manifest.
        if not observed_ready and phase not in {"waiting", "failed"} and manifest != command_manifest:
            raise SetupBridgeError("export-conflict")
        expected_source = command.get("sourceApp")
        if expected_source is not None and source.as_dict() != expected_source:
            raise SetupBridgeError("export-conflict")
        receipt = self._hash(response_value.get("receiptSHA256"), nullable=True, error="source-busy")
        if phase not in {"waiting", "failed"} and receipt is None:
            raise SetupBridgeError("source-busy")
        error_code = response_value.get("errorCode")
        if error_code is not None and (not isinstance(error_code, str) or error_code not in TRANSFER_ERROR_CODES):
            raise SetupBridgeError("source-busy")
        prior = self._source_apps.get((device_id.lower(), transfer))
        if prior is not None and prior != source:
            raise SetupBridgeError("export-conflict")
        self._source_apps[(device_id.lower(), transfer)] = source
        try:
            current_pid = self._current_pid(device_id)
        except SetupBridgeError:
            raise SetupBridgeError("source-busy") from None
        if current_pid != pid:
            raise SetupBridgeError("source-busy")
        request = self._read_local_request(transfer)
        data_set = self._uuid(request.get("dataSetID"), error="source-busy")
        return ExportReadback(
            phase,
            transfer,
            data_set,
            nonce_value,
            manifest,
            source,
            receipt,
            command_id,
            str(response_value["action"]),
            request_sha,
            pid,
            error_code,
        )

    # ---- export and destructive source controls -------------------------

    def source_request(self, device_id: str, request: Mapping[str, Any], control: Mapping[str, Any]) -> None:
        raw, digest = self._export_request(request, device_id)
        command, control_raw, control_sha = self._control_value(
            control,
            device_id=device_id,
            expected_action="export",
            expected_request_sha=digest,
        )
        transfer = str(request["transferID"])
        with self._house_arrest(device_id) as service:
            existing = None
            if self._base._remote_exists(service, self._EXPORT_REQUEST):
                existing = self._base._read_remote_bounded(service, self._EXPORT_REQUEST, max_bytes=MAX_EXPORT_MANIFEST_BYTES)
            if existing is not None and existing != raw:
                # A prior request may be replaced only after the App has
                # durably released it; an active or ambiguous generation is a
                # conflict and must never be overwritten.
                prior_response = self._response(service, self._CONTROL_RESPONSE)
                replaceable = False
                if prior_response is not None and prior_response.get("transferID") != transfer:
                    replaceable = prior_response.get("phase") in {"released", "releasedNoSnapshot"}
                if not replaceable:
                    raise SetupBridgeError("transaction-conflict")
                with contextlib.suppress(Exception):
                    _run(service.rm_single(self._EXPORT_REQUEST, force=True))
                with contextlib.suppress(Exception):
                    _run(service.rm_single(self._CONTROL_REQUEST, force=True))
                with contextlib.suppress(Exception):
                    _run(service.rm_single(self._CONTROL_RESPONSE, force=True))
            self._base._publish_on_service(service, self._EXPORT_REQUEST, raw, conflict_code="source-busy")
            # The producer has already journaled this exact command ID and
            # control-byte digest.  Re-encoding the validated mapping with
            # the fixed canonical codec preserves those bytes without
            # allowing the adapter to mint command authority.
            self._base._publish_on_service(service, self._CONTROL_REQUEST, control_raw, conflict_code="source-busy")
        key = (transfer, str(Path(self.config.state_root)).lower())
        self._request_hashes[key] = digest
        self._signal_source(device_id, transfer, str(request["nonce"]))
        _ = (command, control_sha)

    def source_readback(self, device_id: str, transfer_id: str, nonce: str) -> ExportReadback | None:
        return self._source_response(device_id, transfer_id, nonce)

    def _control_value(
        self,
        control: Mapping[str, Any],
        *,
        device_id: str,
        expected_action: str | None = None,
        expected_request_sha: str | None = None,
    ) -> tuple[Mapping[str, Any], bytes, str]:
        """Validate and canonically encode a producer-owned control request.

        Command IDs and nullable identity fields are part of the frozen
        producer request.  This method only validates those fields against the
        original export request and returns the bytes that the fixed AFC path
        will receive; it never creates a command ID or substitutes a local
        digest.
        """
        required = {
            "version", "action", "commandID", "transferID", "nonce",
            "requestSHA256", "manifestSHA256", "sourceApp",
        }
        if not isinstance(control, Mapping) or set(control) != required or control.get("version") != 1:
            raise SetupBridgeError("invalid-request")
        action = control.get("action")
        if action not in {"export", "seal", "release"} or (expected_action is not None and action != expected_action):
            raise SetupBridgeError("invalid-request")
        command_id = self._uuid(control.get("commandID"), error="invalid-request")
        transfer = self._uuid(control.get("transferID"), error="invalid-request")
        nonce = self._uuid(control.get("nonce"), error="invalid-request")
        request_sha = self._hash(control.get("requestSHA256"), error="invalid-request")
        original_sha = expected_request_sha or self._read_private_request_hash(transfer)
        if request_sha != original_sha:
            raise SetupBridgeError("export-conflict")
        request = self._read_local_request(transfer)
        if self._uuid(request.get("nonce"), error="export-conflict") != nonce:
            raise SetupBridgeError("export-conflict")
        try:
            selected = normalized_device(device_id)
            if normalized_device(request.get("sourceDeviceUDID")) != selected or normalized_device(request.get("destinationDeviceUDID")) != selected:
                raise SetupBridgeError("identity-mismatch")
        except (_SetupBridgeError, SetupBridgeError):
            raise SetupBridgeError("identity-mismatch") from None
        manifest = control.get("manifestSHA256")
        if manifest is not None:
            self._hash(manifest, error="invalid-request")
        source = control.get("sourceApp")
        source_value: Mapping[str, Any] | None
        if source is None:
            source_value = None
        else:
            source_value = self._app(source, error="invalid-request").as_dict()
        if action == "export" and (manifest is not None or source_value is not None):
            raise SetupBridgeError("invalid-request")
        if action == "seal" and (manifest is None or source_value is None):
            raise SetupBridgeError("invalid-request")
        if action == "release" and ((manifest is None) != (source_value is None)):
            raise SetupBridgeError("invalid-request")
        value: dict[str, Any] = {
            "version": 1,
            "action": action,
            "commandID": command_id,
            "transferID": transfer,
            "nonce": nonce,
            "requestSHA256": request_sha,
            "manifestSHA256": manifest,
            "sourceApp": source_value,
        }
        raw = self._json_bytes(value, maximum=MAX_EXPORT_MANIFEST_BYTES)
        return value, raw, hashlib.sha256(raw).hexdigest()

    def _publish_control(self, device_id: str, value: Mapping[str, Any], raw: bytes) -> None:
        with self._house_arrest(device_id) as service:
            existing = None
            if self._base._remote_exists(service, self._CONTROL_REQUEST):
                existing = self._base._read_remote_bounded(service, self._CONTROL_REQUEST, max_bytes=self._MAX_RESPONSE_BYTES)
            if existing is not None and existing != raw:
                prior_response = self._response(service, self._CONTROL_RESPONSE)
                replaceable = prior_response is not None and prior_response.get("transferID") == value.get("transferID") and prior_response.get("nonce") == value.get("nonce") and prior_response.get("phase") in {"preparing", "ready", "released", "releasedNoSnapshot"}
                if not replaceable:
                    raise SetupBridgeError("export-conflict")
                _run(service.rm_single(self._CONTROL_REQUEST, force=True))
                with contextlib.suppress(Exception):
                    _run(service.rm_single(self._CONTROL_RESPONSE, force=True))
            self._base._publish_on_service(service, self._CONTROL_REQUEST, raw, conflict_code="removal-unknown")

    def _control_response(self, device_id: str, transfer_id: str, nonce: str, command: Mapping[str, Any]) -> Mapping[str, Any]:
        with self._house_arrest(device_id) as service:
            response = self._response(service, self._CONTROL_RESPONSE)
        if response is None:
            raise SetupBridgeError("removal-unknown")
        required = {"version", "commandID", "action", "transferID", "nonce", "requestSHA256", "manifestSHA256", "sourceApp", "pid", "phase", "receiptSHA256", "errorCode"}
        if set(response) != required or response.get("version") != 1:
            raise SetupBridgeError("removal-unknown")
        if response.get("commandID") != command.get("commandID") or response.get("action") != command.get("action") or response.get("transferID") != transfer_id or response.get("nonce") != nonce:
            raise SetupBridgeError("removal-unknown")
        if response.get("requestSHA256") != command.get("requestSHA256"):
            raise SetupBridgeError("export-conflict")
        response_manifest = self._hash(response.get("manifestSHA256"), nullable=True, error="removal-unknown")
        command_manifest = command.get("manifestSHA256")
        response_phase = response.get("phase")
        if not isinstance(response_phase, str):
            raise SetupBridgeError("removal-unknown")
        ready_wins = (
            command.get("action") == "release"
            and command_manifest is None
            and response_phase == "ready"
            and response_manifest is not None
            and response.get("errorCode") == "export-conflict"
        )
        if not ready_wins and response_phase not in {"waiting", "failed"} and response_manifest != command_manifest:
            raise SetupBridgeError("export-conflict")
        actual_source = self._app(response.get("sourceApp"), error="removal-unknown").as_dict()
        expected_source = command.get("sourceApp")
        if expected_source is not None and actual_source != expected_source:
            raise SetupBridgeError("export-conflict")
        pid = response.get("pid")
        if type(pid) is not int or pid <= 0:
            raise SetupBridgeError("removal-unknown")
        phase = response_phase
        if phase not in {"waiting", "preparing", "ready", "removalSealed", "released", "releasedNoSnapshot", "failed"}:
            raise SetupBridgeError("removal-unknown")
        allowed_phases = self._allowed_response_phases(command)
        if allowed_phases is None or phase not in allowed_phases:
            raise SetupBridgeError("removal-unknown")
        receipt = self._hash(response.get("receiptSHA256"), nullable=True, error="removal-unknown")
        if phase not in {"waiting", "failed"} and receipt is None:
            raise SetupBridgeError("removal-unknown")
        error_code = response.get("errorCode")
        if error_code is not None and (not isinstance(error_code, str) or error_code not in TRANSFER_ERROR_CODES):
            raise SetupBridgeError("removal-unknown")
        try:
            if self._current_pid(device_id) != pid:
                raise SetupBridgeError("removal-unknown")
        except SetupBridgeError:
            raise SetupBridgeError("removal-unknown") from None
        return response

    def source_seal(self, device_id: str, control: Mapping[str, Any]) -> Mapping[str, Any]:
        command, raw, _ = self._control_value(control, device_id=device_id, expected_action="seal")
        transfer = str(command["transferID"])
        nonce = str(command["nonce"])
        self._publish_control(device_id, command, raw)
        response = self._control_response(device_id, transfer, nonce, command)
        return response

    def source_release(self, device_id: str, control: Mapping[str, Any]) -> Mapping[str, Any]:
        command, raw, _ = self._control_value(control, device_id=device_id, expected_action="release")
        transfer = str(command["transferID"])
        nonce = str(command["nonce"])
        self._publish_control(device_id, command, raw)
        response = self._control_response(device_id, transfer, nonce, command)
        return response

    def source_pid(self, device_id: str) -> int:
        return self._current_pid(device_id)

    def stop_source(self, device_id: str, pid: int) -> None:
        if type(pid) is not int or pid <= 0:
            raise SetupBridgeError("removal-unknown")

        async def stop(control: Any) -> None:
            current = await control.process_identifier_for_bundle_identifier(TARGET_BUNDLE_ID)
            if current != pid:
                raise SetupBridgeError("removal-unknown")
            await control.kill(pid)

        self._process_call(device_id, stop)
        try:
            remaining = self._current_pid(device_id)
        except SetupBridgeError:
            raise SetupBridgeError("removal-unknown") from None
        if remaining != 0:
            raise SetupBridgeError("removal-unknown")

    def uninstall(self, device_id: str, bundle_id: str) -> None:
        if bundle_id != TARGET_BUNDLE_ID:
            raise SetupBridgeError("identity-mismatch")
        client = None
        service = None
        try:
            module = __import__("pymobiledevice3.services.installation_proxy", fromlist=["InstallationProxyService"])
            service_cls = getattr(module, "InstallationProxyService", None)
            if service_cls is None:
                raise SetupBridgeError("runtime-api-mismatch")
            with tempfile.TemporaryDirectory(prefix="gofly-reinstall-uninstall-") as directory:
                self.observe(device_id)
                client = self._base._open(device_id, Path(directory))
                service = service_cls(client)
                _run(service.uninstall(TARGET_BUNDLE_ID))
                self.observe(device_id)
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("removal-unknown") from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if client is not None:
                    _run(client.close())

    # ---- AFC source package and target restore ---------------------------

    def _source_package_context(self, device_id: str, transfer_id: str) -> tuple[ExportReadback, Mapping[str, Any], bytes]:
        readback = self._source_response(device_id, transfer_id, self._nonce_from_request(transfer_id))
        if readback is None or readback.phase != "ready" or readback.raw_manifest_sha256 is None:
            raise SetupBridgeError("backup-invalid")
        # The dataset ID is part of the request and therefore is authoritative
        # for the fixed remote generation path.
        request = self._read_local_request(transfer_id)
        data_set = self._uuid(request.get("dataSetID"), error="backup-invalid")
        with self._house_arrest(device_id) as service:
            remote = f"{self._TRANSFER_ROOT}/exports/{data_set}/package/manifest.json"
            raw = self._base._read_remote_bounded(service, remote, max_bytes=MAX_EXPORT_MANIFEST_BYTES)
        manifest = self._manifest(raw, device_id=device_id, transfer_id=transfer_id, expected_sha=readback.raw_manifest_sha256)
        if readback.source_app is None or manifest.get("sourceApp") != readback.source_app.as_dict() or manifest.get("sourceApp", {}).get("build") != request.get("sourceBuild") or manifest.get("targetApp") != request.get("targetApp") or manifest.get("categories") != request.get("categories") or manifest.get("dataSetID") != data_set or manifest.get("nonce") != request.get("nonce") or manifest.get("setupID") != request.get("setupID"):
            raise SetupBridgeError("identity-mismatch")
        return readback, manifest, raw

    def _read_local_request(self, transfer_id: str) -> Mapping[str, Any]:
        path = self._transaction_root(transfer_id) / "export-request.json"
        try:
            return self._decode_json(_read_private_regular(path, max_bytes=MAX_EXPORT_MANIFEST_BYTES), maximum=MAX_EXPORT_MANIFEST_BYTES)
        except _SetupBridgeError:
            raise SetupBridgeError("source-busy") from None

    def _nonce_from_request(self, transfer_id: str) -> str:
        nonce = self._read_local_request(transfer_id).get("nonce")
        return self._uuid(nonce, error="source-busy")

    def copy_source_package(self, device_id: str, transfer_id: str, destination: Path) -> None:
        expected_destination = self._expected_backup(transfer_id)
        if Path(destination) != expected_destination:
            raise SetupBridgeError("storage-unavailable")
        readback, manifest, manifest_raw = self._source_package_context(device_id, transfer_id)
        data_set = self._uuid(manifest.get("dataSetID"), error="backup-invalid")
        artifacts = manifest.get("artifacts")
        assert isinstance(artifacts, list)
        if expected_destination.exists() and expected_destination.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        expected_paths = {str(item["path"]) for item in artifacts}
        expected_paths.add("manifest.json")
        if expected_destination.exists():
            self._validate_private_inventory(expected_destination, expected_paths, require_complete=False)
        else:
            self._ensure_private_directory(expected_destination)
            self._validate_private_inventory(expected_destination, expected_paths, require_complete=False)
        total = len(manifest_raw)
        with self._house_arrest(device_id) as service:
            for item in sorted(artifacts, key=lambda value: value["path"]):
                relative = str(item["path"])
                size = int(item["byteCount"])
                digest = str(item["sha256"])
                remote = f"{self._TRANSFER_ROOT}/exports/{data_set}/package/{relative}"
                data = self._base._read_remote_bounded(service, remote, max_bytes=size)
                if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
                    raise SetupBridgeError("backup-invalid")
                total += len(data)
                if total > MAX_BACKUP_BYTES:
                    raise SetupBridgeError("backup-invalid")
                self._write_private_file(expected_destination / relative, data, maximum=size)
        self._write_private_file(expected_destination / "manifest.json", manifest_raw, maximum=MAX_EXPORT_MANIFEST_BYTES)
        self._validate_private_inventory(expected_destination, expected_paths, require_complete=True)

    def _restore_intent(self, raw: bytes, *, device_id: str, transfer_id: str | None = None) -> Mapping[str, Any]:
        value = self._decode_json(raw, maximum=MAX_EXPORT_MANIFEST_BYTES)
        required = {"version", "transferID", "dataSetID", "nonce", "rawManifestSHA256", "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp", "targetApp", "setupID", "categories"}
        if set(value) != required or value.get("version") != 1:
            raise SetupBridgeError("restore-unknown")
        transfer = self._uuid(value.get("transferID"), error="restore-unknown")
        self._uuid(value.get("dataSetID"), error="restore-unknown")
        self._uuid(value.get("nonce"), error="restore-unknown")
        self._uuid(value.get("setupID"), error="restore-unknown")
        self._hash(value.get("rawManifestSHA256"), error="restore-unknown")
        try:
            selected = normalized_device(device_id)
            if normalized_device(value.get("sourceDeviceUDID")) != selected or normalized_device(value.get("destinationDeviceUDID")) != selected:
                raise SetupBridgeError("identity-mismatch")
        except (_SetupBridgeError, SetupBridgeError):
            raise SetupBridgeError("restore-unknown") from None
        self._app(value.get("sourceApp"), error="restore-unknown")
        self._app(value.get("targetApp"), error="restore-unknown")
        categories = value.get("categories")
        if not isinstance(categories, list) or tuple(categories) != tuple(item for item in ("favorites", "routes", "settings") if item in categories) or len(categories) != len(set(categories)) or any(item not in {"favorites", "routes", "settings"} for item in categories):
            raise SetupBridgeError("restore-unknown")
        if transfer_id is not None and transfer != self._uuid(transfer_id, error="restore-unknown"):
            raise SetupBridgeError("restore-unknown")
        return value

    def publish_restore_intent(self, device_id: str, intent: Mapping[str, Any]) -> None:
        raw = self._json_bytes(intent, maximum=MAX_EXPORT_MANIFEST_BYTES)
        self._restore_intent(raw, device_id=device_id)
        with self._house_arrest(device_id) as service:
            self._base._publish_on_service(service, self._RESTORE_INTENT, raw, conflict_code="restore-unknown")

    def deliver_restore(self, device_id: str, transfer_id: str, package_dir: Path) -> None:
        expected = self._expected_backup(transfer_id)
        if Path(package_dir) != expected or expected.is_symlink() or not expected.is_dir():
            raise SetupBridgeError("storage-unavailable")
        try:
            manifest_raw = _read_private_regular(expected / "manifest.json", max_bytes=MAX_EXPORT_MANIFEST_BYTES)
        except _SetupBridgeError:
            raise SetupBridgeError("backup-invalid") from None
        # The device intent supplies the destination identity and data-set ID;
        # no caller path can select a remote generation.
        with self._house_arrest(device_id) as service:
            intent_raw = self._base._read_remote_bounded(service, self._RESTORE_INTENT, max_bytes=MAX_EXPORT_MANIFEST_BYTES)
            intent = self._restore_intent(intent_raw, device_id=device_id, transfer_id=transfer_id)
            manifest = self._manifest(manifest_raw, device_id=device_id, transfer_id=transfer_id, expected_sha=intent.get("rawManifestSHA256"))
            if manifest.get("dataSetID") != intent.get("dataSetID") or manifest.get("nonce") != intent.get("nonce") or manifest.get("setupID") != intent.get("setupID") or manifest.get("sourceApp") != intent.get("sourceApp") or manifest.get("targetApp") != intent.get("targetApp") or manifest.get("categories") != intent.get("categories"):
                raise SetupBridgeError("identity-mismatch")
            data_set = self._uuid(intent.get("dataSetID"), error="restore-unknown")
            artifacts = manifest.get("artifacts")
            assert isinstance(artifacts, list)
            expected_files = {"manifest.json"} | {str(item["path"]) for item in artifacts}
            self._validate_private_inventory(expected, expected_files, require_complete=True)
            _run(service.makedirs(f"{self._TRANSFER_ROOT}/incoming/{data_set}/package"))
            for item in sorted(artifacts, key=lambda value: value["path"]):
                relative = str(item["path"])
                local = expected / relative
                if local.is_symlink() or not local.is_file():
                    raise SetupBridgeError("backup-invalid")
                try:
                    payload = _read_private_regular(local, max_bytes=int(item["byteCount"]))
                except _SetupBridgeError:
                    raise SetupBridgeError("backup-invalid") from None
                if len(payload) != int(item["byteCount"]) or hashlib.sha256(payload).hexdigest() != item["sha256"]:
                    raise SetupBridgeError("backup-invalid")
                remote = f"{self._TRANSFER_ROOT}/incoming/{data_set}/package/{relative}"
                self._base._upload_remote_file(service, local, remote)
            # Manifest is published last, after each payload's remote stat and
            # SHA-256 readback has succeeded.
            self._base._publish_on_service(service, f"{self._TRANSFER_ROOT}/incoming/{data_set}/package/manifest.json", manifest_raw, conflict_code="restore-unknown")

    def restore_readback(self, device_id: str, transfer_id: str) -> RestoreObservation | None:
        with self._house_arrest(device_id) as service:
            raw = None
            if self._base._remote_exists(service, self._RESTORE_RESPONSE):
                raw = self._base._read_remote_bounded(service, self._RESTORE_RESPONSE, max_bytes=self._MAX_RESPONSE_BYTES)
        if raw is None:
            return None
        value = self._decode_json(raw, maximum=self._MAX_RESPONSE_BYTES)
        required = {"version", "intent", "pid", "app", "phase", "categories", "counts", "receipt"}
        if set(value) != required or value.get("version") != 1:
            raise SetupBridgeError("restore-unknown")
        if not isinstance(value.get("intent"), Mapping):
            raise SetupBridgeError("restore-unknown")
        intent = self._restore_intent(self._json_bytes(value["intent"], maximum=MAX_EXPORT_MANIFEST_BYTES), device_id=device_id, transfer_id=transfer_id)
        app = self._app(value.get("app"), error="restore-unknown")
        if app.as_dict() != intent.get("targetApp"):
            raise SetupBridgeError("restore-unknown")
        known = self._installed_artifacts.get(device_id.lower())
        if known is not None and app.as_dict() != {"bundleID": known.bundle_id, "build": known.build, "profileSHA256": known.profile_sha256, "executableSHA256": known.executable_sha256}:
            raise SetupBridgeError("restore-unknown")
        pid = value.get("pid")
        if type(pid) is not int or pid <= 0:
            raise SetupBridgeError("restore-unknown")
        try:
            if self._current_pid(device_id) != pid:
                raise SetupBridgeError("restore-unknown")
        except SetupBridgeError:
            raise SetupBridgeError("restore-unknown") from None
        phase = value.get("phase")
        if not isinstance(phase, str) or phase not in {"waiting", "validating", "committed", "failed"}:
            raise SetupBridgeError("restore-unknown")
        selected = tuple(intent["categories"])
        categories = value.get("categories")
        if not isinstance(categories, list) or len(categories) != len(selected):
            raise SetupBridgeError("restore-unknown")
        seen: set[str] = set()
        category_values: list[Mapping[str, Any]] = []
        for item in categories:
            if not isinstance(item, Mapping) or set(item) != {"category", "state", "receiptSHA256"}:
                raise SetupBridgeError("restore-unknown")
            category = item.get("category")
            state = item.get("state")
            if category not in selected or category in seen or state not in {"waiting", "validating", "committed", "failed"}:
                raise SetupBridgeError("restore-unknown")
            receipt = self._hash(item.get("receiptSHA256"), nullable=True, error="restore-unknown")
            if state == "committed" and receipt is None:
                raise SetupBridgeError("restore-unknown")
            if state != "committed" and receipt is not None:
                raise SetupBridgeError("restore-unknown")
            seen.add(category)
            category_values.append({"category": category, "state": state, "receiptSHA256": receipt})
        if seen != set(selected):
            raise SetupBridgeError("restore-unknown")
        if [item["category"] for item in category_values] != list(selected):
            raise SetupBridgeError("restore-unknown")
        counts = value.get("counts")
        count_values: Mapping[str, int] | None = None
        if counts is not None:
            if not isinstance(counts, Mapping) or set(counts) != set(COUNT_LIMITS) or any(type(counts[key]) is not int or counts[key] < 0 or counts[key] > COUNT_LIMITS[key] for key in counts):
                raise SetupBridgeError("restore-unknown")
            count_values = {key: int(counts[key]) for key in COUNT_LIMITS}
        full_receipt: Mapping[str, Any] | None = None
        receipt_sha: str | None = None
        receipt_value = value.get("receipt")
        if phase == "committed":
            if not isinstance(receipt_value, Mapping) or set(receipt_value) != {"version", "intent", "categoryReceipts", "sessionSeedSHA256", "counts", "receiptSHA256"} or receipt_value.get("version") != 1:
                raise SetupBridgeError("restore-unknown")
            if receipt_value.get("intent") != intent:
                raise SetupBridgeError("restore-unknown")
            receipt_sha = self._hash(receipt_value.get("receiptSHA256"), error="restore-unknown")
            session_seed = self._hash(receipt_value.get("sessionSeedSHA256"), error="restore-unknown")
            assert isinstance(receipt_sha, str) and isinstance(session_seed, str)
            canonical_receipt = {key: receipt_value[key] for key in receipt_value if key != "receiptSHA256"}
            if hashlib.sha256(self._json_bytes(canonical_receipt, maximum=self._MAX_RESPONSE_BYTES)).hexdigest() != receipt_sha:
                raise SetupBridgeError("restore-unknown")
            receipt_categories = receipt_value.get("categoryReceipts")
            if not isinstance(receipt_categories, list) or len(receipt_categories) != len(selected):
                raise SetupBridgeError("restore-unknown")
            if [item.get("category") for item in receipt_categories if isinstance(item, Mapping)] != list(selected):
                raise SetupBridgeError("restore-unknown")
            for category, item in zip(selected, receipt_categories):
                if not isinstance(item, Mapping) or set(item) != {"category", "receiptSHA256"} or item.get("category") != category or not self._hash(item.get("receiptSHA256"), error="restore-unknown"):
                    raise SetupBridgeError("restore-unknown")
            receipt_counts = receipt_value.get("counts")
            if not isinstance(receipt_counts, Mapping) or set(receipt_counts) != set(COUNT_LIMITS) or any(type(receipt_counts[key]) is not int or receipt_counts[key] < 0 or receipt_counts[key] > COUNT_LIMITS[key] for key in COUNT_LIMITS):
                raise SetupBridgeError("restore-unknown")
            if count_values is None or dict(receipt_counts) != dict(count_values):
                raise SetupBridgeError("restore-unknown")
            for category_value, receipt_category in zip(category_values, receipt_categories):
                if category_value["state"] != "committed" or category_value["receiptSHA256"] != receipt_category.get("receiptSHA256"):
                    raise SetupBridgeError("restore-unknown")
            full_receipt = dict(receipt_value)
        elif receipt_value is not None:
            raise SetupBridgeError("restore-unknown")
        if phase == "committed":
            if count_values is None or full_receipt is None or any(item["state"] != "committed" for item in category_values):
                raise SetupBridgeError("restore-unknown")
        elif phase in {"waiting", "validating"} and count_values is not None:
            raise SetupBridgeError("restore-unknown")
        return RestoreObservation(phase, tuple(category_values), count_values, receipt_sha, dict(intent), full_receipt)

    def support(self, device_id: str) -> Mapping[str, Any]:
        observed = self.observe(device_id)
        parts = [int(item) for item in observed.os_version.split(".")]
        method = "personalized" if parts[0] == 26 and len(parts) > 1 and parts[1] <= 3 else "cryptex"
        current = self._base.query_support(device_id, method)
        if current.method != method or current.os_version != observed.os_version or current.observed is not True or not isinstance(current.generation_id, str) or not current.generation_id or not isinstance(current.identifier, str) or not current.identifier or not isinstance(current.version, str) or not current.version:
            raise SetupBridgeError("support-unavailable")
        after = self.observe(device_id)
        if after != observed:
            raise SetupBridgeError("support-unavailable")
        return {
            "observed": True,
            "method": current.method,
            "osVersion": current.os_version,
            "generationID": current.generation_id,
            "identifier": current.identifier,
            "version": current.version,
        }


__all__ = [
    "ArtifactIdentity", "DeviceObservation", "InstalledAppObservation", "ExportReadback", "InstallObservation",
    "RemovalObservation", "RestoreObservation", "SourceAppIdentity", "ReinstallDeviceAdapter", "ReinstallProcessAdapter",
    "SwiftTransferValidator", "TransferValidator", "PinnedReinstallDeviceAdapter", "copy_validated_package",
]
