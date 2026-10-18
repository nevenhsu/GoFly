"""Durable local M3 backup catalog and crash-safe deletion manager.

This module is deliberately independent from the device adapters.  The only
source of backup authority is a validated M2 journal and its fixed
``reinstall-transactions/<transferID>/backup`` directory.
"""

from __future__ import annotations

import contextlib
import copy
import datetime as dt
import errno
import fcntl
import hashlib
import json
import os
import re
import stat
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterator, Mapping

try:
    from ..Reinstall.reinstall_adapters import PinnedReinstallDeviceAdapter
    from ..Reinstall.reinstall_adapters import MAX_BACKUP_BYTES
    from ..Reinstall.reinstall_journal import MAX_JOURNAL_BYTES, is_completed_journal, is_terminal_journal, validate_journal
    from ..Setup.setup_protocol import normalized_device
except ImportError:  # direct execution from the packaged Backup directory
    from Reinstall.reinstall_adapters import PinnedReinstallDeviceAdapter
    from Reinstall.reinstall_adapters import MAX_BACKUP_BYTES
    from Reinstall.reinstall_journal import MAX_JOURNAL_BYTES, is_completed_journal, is_terminal_journal, validate_journal
    from Setup.setup_protocol import normalized_device

from .protocol import BackupBridgeError

CATALOG_NAME = "backup-catalog.json"
CATALOG_VERSION = 1
MAX_CATALOG_BYTES = 2 * 1024 * 1024
MAX_ENTRIES = 129
MAX_HISTORY = 128
MAX_MANIFEST_BYTES = 256 * 1024
MAX_BACKUP_ENTRIES = 512
MAX_BACKUP_DEPTH = 4
TRANSACTION_DIRECTORY = "reinstall-transactions"
JOURNAL_NAME = "reinstall-journal.json"
HISTORY_DIRECTORY = "reinstall-history"
PRIVATE_DIRECTORY_MODE = 0o700
PRIVATE_FILE_MODE = 0o600
UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
TIMESTAMP_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
CATEGORIES = ("favorites", "routes", "settings")


class _RootHandle:
    """One retained descriptor for the configured private state root.

    All reads and mutations in a manager operation are anchored to this
    descriptor.  A path replacement after open therefore cannot redirect a
    later catalog/journal/tree operation to another root.
    """

    def __init__(self, path: Path, fd: int):
        self.path = path
        self.fd = fd
        self._closed = False

    @classmethod
    def open(cls, path: Path) -> "_RootHandle":
        if not path.is_absolute() or path.is_symlink():
            raise _error("storage-unavailable")
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0))
            info = os.fstat(fd)
        except OSError:
            raise _error("storage-unavailable") from None
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
            with contextlib.suppress(OSError):
                os.close(fd)
            raise _error("storage-unavailable")
        return cls(path, fd)

    def close(self) -> None:
        if not self._closed:
            self._closed = True
            with contextlib.suppress(OSError):
                os.close(self.fd)

    def __enter__(self) -> "_RootHandle":
        return self

    def __exit__(self, *_args: Any) -> None:
        self.close()


def _error(code: str) -> BackupBridgeError:
    return BackupBridgeError(code)


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def _reject_number(_value: str) -> Any:
    raise ValueError("non-integer number")


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None or value != value.lower():
        raise _error("storage-unavailable")
    return value


def _sha(value: Any) -> str:
    if not isinstance(value, str) or HEX64_RE.fullmatch(value) is None:
        raise _error("storage-unavailable")
    return value


def _timestamp(value: Any) -> dt.datetime:
    if not isinstance(value, str) or TIMESTAMP_RE.fullmatch(value) is None:
        raise _error("storage-unavailable")
    try:
        return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        raise _error("storage-unavailable") from None


def _utc_seconds(value: dt.datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=dt.timezone.utc)
    value = value.astimezone(dt.timezone.utc).replace(microsecond=0)
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def _validate_dir(path: Path, *, allow_missing: bool = False) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        if allow_missing:
            return
        raise _error("storage-unavailable") from None
    except OSError:
        raise _error("storage-unavailable") from None
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise _error("storage-unavailable")
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
        raise _error("storage-unavailable")


def _validate_regular(path: Path, *, maximum: int, allow_missing: bool = False) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        if allow_missing:
            return
        raise _error("storage-unavailable") from None
    except OSError:
        raise _error("storage-unavailable") from None
    if (
        stat.S_ISLNK(info.st_mode)
        or not stat.S_ISREG(info.st_mode)
        or info.st_uid != os.getuid()
        or info.st_nlink != 1
        or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE
        or info.st_size < 0
        or info.st_size > maximum
    ):
        raise _error("storage-unavailable")


def _read_regular(path: Path, *, maximum: int) -> bytes:
    _validate_regular(path, maximum=maximum)
    fd: int | None = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
        before = os.fstat(fd)
        data = bytearray()
        while len(data) < before.st_size:
            chunk = os.read(fd, min(64 * 1024, before.st_size - len(data)))
            if not chunk:
                raise OSError("short read")
            data.extend(chunk)
        if os.read(fd, 1):
            raise OSError("file grew")
        after = os.fstat(fd)
        if after.st_size != before.st_size or after.st_nlink != 1:
            raise OSError("file changed")
        return bytes(data)
    except BackupBridgeError:
        raise
    except OSError:
        raise _error("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _fsync_dir(path: Path | int) -> None:
    fd: int | None = None
    try:
        if isinstance(path, int):
            os.fsync(path)
            return
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0))
        os.fsync(fd)
    except OSError:
        raise _error("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _write_atomic(path: Path, value: Mapping[str, Any], root: _RootHandle | None = None) -> None:
    try:
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        raise _error("storage-unavailable") from None
    if len(raw) > MAX_CATALOG_BYTES:
        raise _error("storage-unavailable")
    if root is not None:
        if path.name != CATALOG_NAME:
            raise _error("storage-unavailable")
        try:
            info = os.stat(CATALOG_NAME, dir_fd=root.fd, follow_symlinks=False)
        except FileNotFoundError:
            info = None
        except OSError:
            raise _error("storage-unavailable") from None
        if info is not None and (
            stat.S_ISLNK(info.st_mode)
            or not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE
            or info.st_size > MAX_CATALOG_BYTES
        ):
            raise _error("storage-unavailable")
    else:
        _validate_dir(path.parent)
        _validate_regular(path, maximum=MAX_CATALOG_BYTES, allow_missing=True)
    temporary: Path | None = None
    temporary_name: str | None = None
    fd: int | None = None
    try:
        if root is not None:
            for _attempt in range(8):
                candidate = f".backup-catalog-{uuid.uuid4().hex}"
                try:
                    fd = os.open(
                        candidate,
                        os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
                        PRIVATE_FILE_MODE,
                        dir_fd=root.fd,
                    )
                    temporary_name = candidate
                    break
                except FileExistsError:
                    continue
            if fd is None or temporary_name is None:
                raise OSError("temporary name collision")
        else:
            fd, name = tempfile.mkstemp(prefix=".backup-catalog-", dir=path.parent)
            temporary = Path(name)
            os.fchmod(fd, PRIVATE_FILE_MODE)
        offset = 0
        while offset < len(raw):
            written = os.write(fd, raw[offset:])
            if written <= 0:
                raise OSError("short write")
            offset += written
        os.fsync(fd)
        os.close(fd)
        fd = None
        if root is not None:
            os.replace(temporary_name, CATALOG_NAME, src_dir_fd=root.fd, dst_dir_fd=root.fd)
            temporary_name = None
            _fsync_dir(root.fd)
        else:
            assert temporary is not None
            os.replace(temporary, path)
            temporary = None
            _fsync_dir(path.parent)
    except BackupBridgeError:
        raise
    except OSError:
        raise _error("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
        if temporary is not None:
            with contextlib.suppress(OSError):
                temporary.unlink()
        if temporary_name is not None and root is not None:
            with contextlib.suppress(OSError):
                os.unlink(temporary_name, dir_fd=root.fd)


def _parse_json(raw: bytes, *, maximum: int) -> Mapping[str, Any]:
    if not isinstance(raw, bytes) or len(raw) > maximum:
        raise _error("storage-unavailable")
    try:
        value = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            parse_float=_reject_number,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError):
        raise _error("storage-unavailable") from None
    if not isinstance(value, Mapping):
        raise _error("storage-unavailable")
    return value


def _validate_catalog(value: Any) -> dict[str, Any]:
    if not isinstance(value, Mapping) or set(value) != {"version", "entries", "deletion"}:
        raise _error("storage-unavailable")
    if value.get("version") != CATALOG_VERSION:
        raise _error("storage-unavailable")
    entries = value.get("entries")
    if not isinstance(entries, list) or len(entries) > MAX_ENTRIES:
        raise _error("storage-unavailable")
    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, Mapping) or set(entry) != {
            "transferID", "dataSetID", "deviceID", "journalSHA256", "rawManifestSHA256",
            "completedObservedAt", "deleteAfter", "deleted",
        }:
            raise _error("storage-unavailable")
        transfer = _uuid(entry.get("transferID"))
        data_set = _uuid(entry.get("dataSetID"))
        if transfer in seen:
            raise _error("storage-unavailable")
        seen.add(transfer)
        try:
            device = normalized_device(entry.get("deviceID"))
        except Exception:
            raise _error("storage-unavailable") from None
        journal_sha = _sha(entry.get("journalSHA256"))
        manifest_sha = _sha(entry.get("rawManifestSHA256"))
        observed = entry.get("completedObservedAt")
        expires = entry.get("deleteAfter")
        if (observed is None) != (expires is None):
            raise _error("storage-unavailable")
        if observed is not None:
            observed_at = _timestamp(observed)
            expiry_at = _timestamp(expires)
            if expiry_at != observed_at + dt.timedelta(days=7):
                raise _error("storage-unavailable")
        if type(entry.get("deleted")) is not bool:
            raise _error("storage-unavailable")
        normalized.append({
            "transferID": transfer,
            "dataSetID": data_set,
            "deviceID": device,
            "journalSHA256": journal_sha,
            "rawManifestSHA256": manifest_sha,
            "completedObservedAt": observed,
            "deleteAfter": expires,
            "deleted": entry["deleted"],
        })
    deletion = value.get("deletion")
    if deletion is not None:
        if not isinstance(deletion, Mapping) or set(deletion) != {"transferID", "journalSHA256"}:
            raise _error("storage-unavailable")
        deletion = {
            "transferID": _uuid(deletion.get("transferID")),
            "journalSHA256": _sha(deletion.get("journalSHA256")),
        }
        if deletion["transferID"] not in seen:
            raise _error("storage-unavailable")
        selected = next(item for item in normalized if item["transferID"] == deletion["transferID"])
        if selected["journalSHA256"] != deletion["journalSHA256"] or selected["deleted"]:
            raise _error("storage-unavailable")
    return {"version": CATALOG_VERSION, "entries": normalized, "deletion": deletion}


def validate_catalog(value: Any) -> None:
    """Validate a decoded catalog without performing any filesystem writes."""
    _validate_catalog(value)


class BackupCatalog:
    """Atomic version-1 catalog under the configured private state root."""

    def __init__(self, state_root: str | Path):
        self.state_root = Path(state_root)
        self.path = self.state_root / CATALOG_NAME

    def ensure_root(self) -> None:
        if not self.state_root.is_absolute():
            raise _error("storage-unavailable")
        created = False
        try:
            self.state_root.lstat()
        except FileNotFoundError:
            # The configured root is one fixed directory.  Never create a
            # missing parent chain, which could follow an attacker-controlled
            # path while no operation lease exists.
            parent_fd: int | None = None
            try:
                parent = self.state_root.parent
                parent_fd = os.open(parent, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0))
                parent_info = os.fstat(parent_fd)
                if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != os.getuid():
                    raise OSError("unsafe parent")
                os.mkdir(self.state_root.name, mode=PRIVATE_DIRECTORY_MODE, dir_fd=parent_fd)
                created = True
            except OSError:
                # Another writer may have created this fixed directory; the
                # retained descriptor check below decides whether it is safe.
                if not created and self.state_root.exists():
                    pass
                else:
                    raise _error("storage-unavailable") from None
            finally:
                if parent_fd is not None:
                    with contextlib.suppress(OSError):
                        os.close(parent_fd)
        except OSError:
            raise _error("storage-unavailable") from None
        with _RootHandle.open(self.state_root):
            pass

    def read(self, root: _RootHandle | None = None) -> dict[str, Any]:
        if root is None:
            if not self.state_root.exists():
                return {"version": CATALOG_VERSION, "entries": [], "deletion": None}
            with _RootHandle.open(self.state_root) as retained:
                return self.read(retained)
        try:
            raw = _read_fd_regular_optional(root.fd, CATALOG_NAME, max_bytes=MAX_CATALOG_BYTES)
        except BackupBridgeError:
            raise
        if raw is None:
            return {"version": CATALOG_VERSION, "entries": [], "deletion": None}
        value = _validate_catalog(_parse_json(raw, maximum=MAX_CATALOG_BYTES))
        return copy.deepcopy(value)

    def write(self, value: Mapping[str, Any], root: _RootHandle | None = None) -> None:
        normalized = _validate_catalog(value)
        if root is None:
            self.ensure_root()
            with _RootHandle.open(self.state_root) as retained:
                self.write(normalized, retained)
            return
        _write_atomic(self.path, normalized, root)


@dataclass(frozen=True)
class _Source:
    transfer_id: str
    journal: Mapping[str, Any]
    raw: bytes
    journal_sha256: str
    path: Path
    current: bool


def _read_source(path: Path, *, current: bool) -> _Source:
    raw = _read_regular(path, maximum=MAX_JOURNAL_BYTES)
    return _source_from_raw(path, raw, current=current)


def _source_from_raw(path: Path, raw: bytes, *, current: bool) -> _Source:
    value = _parse_json(raw, maximum=MAX_JOURNAL_BYTES)
    try:
        validate_journal(value)
    except Exception:
        raise _error("storage-unavailable") from None
    transfer = value.get("transferID")
    try:
        transfer = _uuid(transfer)
    except BackupBridgeError:
        raise _error("storage-unavailable") from None
    return _Source(transfer, copy.deepcopy(dict(value)), raw, hashlib.sha256(raw).hexdigest(), path, current)


def _read_fd_regular_optional(parent_fd: int, name: str, *, max_bytes: int) -> bytes | None:
    """Read one private regular child, preserving a genuine missing result."""
    fd: int | None = None
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), dir_fd=parent_fd)
        except FileNotFoundError:
            return None
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE
            or info.st_size < 0
            or info.st_size > max_bytes
        ):
            raise OSError("unsafe file")
        data = bytearray()
        while len(data) < info.st_size:
            chunk = os.read(fd, min(64 * 1024, info.st_size - len(data)))
            if not chunk:
                raise OSError("short read")
            data.extend(chunk)
        if os.read(fd, 1) or os.fstat(fd).st_size != info.st_size:
            raise OSError("changed file")
        return bytes(data)
    except OSError:
        raise _error("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _read_source_at(parent_fd: int, name: str, *, current: bool, path: Path) -> _Source | None:
    raw = _read_fd_regular_optional(parent_fd, name, max_bytes=MAX_JOURNAL_BYTES)
    if raw is None:
        return None
    return _source_from_raw(path, raw, current=current)


def _is_complete(journal: Mapping[str, Any]) -> bool:
    return is_completed_journal(journal)


def _is_terminal(journal: Mapping[str, Any]) -> bool:
    return is_terminal_journal(journal)


def _categories(journal: Mapping[str, Any]) -> list[str]:
    backup = journal.get("backup")
    if backup is None:
        # Early/incomplete M2 records may not have reached the backup stage;
        # the absence of an inventory is represented as an empty selection,
        # never inferred by walking the package directory.
        return []
    inventory = backup.get("inventory") if isinstance(backup, Mapping) else None
    categories = inventory.get("categories") if isinstance(inventory, Mapping) else None
    if not isinstance(categories, list) or any(item not in CATEGORIES for item in categories):
        raise _error("storage-unavailable")
    if tuple(categories) != tuple(item for item in CATEGORIES if item in categories):
        raise _error("storage-unavailable")
    return list(categories)


def _backup_path(root: Path, transfer_id: str) -> Path:
    _uuid(transfer_id)
    transactions = root / TRANSACTION_DIRECTORY
    transaction = transactions / transfer_id
    return transaction / "backup"


def _validate_manifest_binding(source: _Source, raw: bytes) -> Mapping[str, Any]:
    expected_sha = source.journal.get("rawManifestSHA256")
    if not isinstance(expected_sha, str) or hashlib.sha256(raw).hexdigest() != expected_sha:
        raise _error("backup-changed")
    try:
        # _manifest is a pure grammar helper.  object.__new__ avoids invoking
        # the production adapter and therefore never opens a device service.
        adapter = object.__new__(PinnedReinstallDeviceAdapter)
        value = PinnedReinstallDeviceAdapter._manifest(
            adapter,
            raw,
            device_id=source.journal["deviceID"],
            transfer_id=source.transfer_id,
            expected_sha=expected_sha,
        )
        # The adapter grammar validates the manifest's internal shape.  Bind
        # the remaining M2 identity fields to the original journal as well so
        # a valid manifest from another generation cannot become deletion
        # authority merely by being copied into this fixed directory.
        if (
            value.get("dataSetID") != source.journal.get("dataSetID")
            or value.get("nonce") != source.journal.get("nonce")
            or value.get("setupID") != source.journal.get("setupID")
            or value.get("categories") != _categories(source.journal)
        ):
            raise _error("backup-changed")
        source_app = source.journal.get("sourceApp")
        if isinstance(source_app, Mapping) and value.get("sourceApp") != source_app:
            raise _error("backup-changed")
        target_artifact = source.journal.get("targetArtifact")
        target_app = value.get("targetApp")
        if isinstance(target_artifact, Mapping) and isinstance(target_app, Mapping):
            for key in ("bundleID", "build", "profileSHA256", "executableSHA256"):
                if target_app.get(key) != target_artifact.get(key):
                    raise _error("backup-changed")
    except Exception:
        raise _error("backup-changed") from None
    return value


def _manifest_info(source: _Source, root: _RootHandle | Path) -> tuple[bytes, Mapping[str, Any]] | None:
    if not isinstance(root, _RootHandle):
        with _RootHandle.open(Path(root)) as retained:
            return _manifest_info(source, retained)
    transactions_fd = _open_optional_dir(root.fd, TRANSACTION_DIRECTORY)
    if transactions_fd is None:
        return None
    transaction_fd: int | None = None
    backup_fd: int | None = None
    try:
        transaction_fd = _open_optional_dir(transactions_fd, source.transfer_id)
        if transaction_fd is None:
            return None
        backup_fd = _open_optional_dir(transaction_fd, "backup")
        if backup_fd is None:
            return None
        try:
            raw = _read_fd_regular_optional(backup_fd, "manifest.json", max_bytes=MAX_MANIFEST_BYTES)
        except BackupBridgeError:
            raise _error("backup-changed") from None
        if raw is None:
            return None
        value = _validate_manifest_binding(source, raw)
        return raw, value
    finally:
        for fd in (backup_fd, transaction_fd, transactions_fd):
            if fd is not None:
                with contextlib.suppress(OSError):
                    os.close(fd)


def _stat_incomplete_backup(source: _Source, root: _RootHandle | Path) -> bool:
    """Check only the derived package directory for an incomplete record."""
    if not isinstance(root, _RootHandle):
        with _RootHandle.open(Path(root)) as retained:
            return _stat_incomplete_backup(source, retained)
    transactions_fd = _open_optional_dir(root.fd, TRANSACTION_DIRECTORY)
    if transactions_fd is None:
        return False
    transaction_fd: int | None = None
    backup_fd: int | None = None
    try:
        transaction_fd = _open_optional_dir(transactions_fd, source.transfer_id)
        if transaction_fd is None:
            return False
        backup_fd = _open_optional_dir(transaction_fd, "backup")
        return backup_fd is not None
    finally:
        for fd in (backup_fd, transaction_fd, transactions_fd):
            if fd is not None:
                with contextlib.suppress(OSError):
                    os.close(fd)


def _open_dir(parent_fd: int, name: str) -> int:
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0), dir_fd=parent_fd)
        info = os.fstat(fd)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
            os.close(fd)
            raise _error("backup-changed")
        return fd
    except BackupBridgeError:
        raise
    except OSError as error:
        if error.errno in {errno.ENOENT, errno.ENOTDIR, errno.ELOOP}:
            raise _error("backup-changed") from None
        raise _error("storage-unavailable") from None


def _open_optional_dir(parent_fd: int, name: str) -> int | None:
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_CLOEXEC", 0), dir_fd=parent_fd)
        info = os.fstat(fd)
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
            os.close(fd)
            raise _error("backup-changed")
        return fd
    except FileNotFoundError:
        return None
    except BackupBridgeError:
        raise
    except OSError as error:
        if error.errno in {errno.ENOENT, errno.ENOTDIR}:
            return None
        if error.errno == errno.ELOOP:
            raise _error("backup-changed") from None
        raise _error("storage-unavailable") from None


def _same_directory(fd: int, path: Path) -> bool:
    """Confirm a legacy path points at the already-open directory inode."""
    try:
        expected = os.fstat(fd)
        actual = os.stat(path, follow_symlinks=False)
        return stat.S_ISDIR(actual.st_mode) and (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino)
    except OSError:
        return False


@dataclass
class _TreeHandles:
    state_fd: int
    transactions_fd: int
    transaction_fd: int
    backup_fd: int
    child_dirs: list[tuple[int, str, str, int]]
    files: list[tuple[int, str, str]]

    def close(self) -> None:
        fds = [item[3] for item in self.child_dirs] + [self.backup_fd, self.transaction_fd, self.transactions_fd, self.state_fd]
        for fd in reversed(fds):
            with contextlib.suppress(OSError):
                os.close(fd)


def _open_tree(root: _RootHandle | Path, transfer_id: str) -> _TreeHandles:
    if not isinstance(root, _RootHandle):
        with _RootHandle.open(Path(root)) as retained:
            return _open_tree(retained, transfer_id)
    try:
        state_fd = os.dup(root.fd)
    except OSError:
        raise _error("storage-unavailable") from None
    try:
        transactions_fd = _open_dir(state_fd, TRANSACTION_DIRECTORY)
        transaction_fd = _open_dir(transactions_fd, transfer_id)
        backup_fd = _open_dir(transaction_fd, "backup")
        return _TreeHandles(state_fd, transactions_fd, transaction_fd, backup_fd, [], [])
    except Exception:
        with contextlib.suppress(OSError):
            os.close(state_fd)
        raise


def _open_tree_optional(root: _RootHandle, transfer_id: str) -> _TreeHandles | None:
    try:
        state_fd = os.dup(root.fd)
    except OSError:
        raise _error("storage-unavailable") from None
    transactions_fd: int | None = None
    transaction_fd: int | None = None
    backup_fd: int | None = None
    try:
        transactions_fd = _open_optional_dir(state_fd, TRANSACTION_DIRECTORY)
        if transactions_fd is None:
            return None
        transaction_fd = _open_optional_dir(transactions_fd, transfer_id)
        if transaction_fd is None:
            return None
        backup_fd = _open_optional_dir(transaction_fd, "backup")
        if backup_fd is None:
            return None
        return _TreeHandles(state_fd, transactions_fd, transaction_fd, backup_fd, [], [])
    finally:
        if backup_fd is None:
            for fd in (transaction_fd, transactions_fd, state_fd):
                if fd is not None:
                    with contextlib.suppress(OSError):
                        os.close(fd)


def _verify_payload_fd(
    parent_fd: int,
    name: str,
    expected_size: int,
    expected_sha: str,
    *,
    allow_missing: bool = False,
) -> bool:
    """Stream one listed payload through its retained parent descriptor."""
    if type(expected_size) is not int or expected_size <= 0 or expected_size > MAX_BACKUP_BYTES or HEX64_RE.fullmatch(expected_sha) is None:
        raise _error("backup-changed")
    fd: int | None = None
    try:
        try:
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), dir_fd=parent_fd)
        except FileNotFoundError:
            if allow_missing:
                return False
            raise
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE
            or info.st_size != expected_size
        ):
            raise OSError("unsafe payload")
        digest = hashlib.sha256()
        remaining = expected_size
        while remaining:
            chunk = os.read(fd, min(64 * 1024, remaining))
            if not chunk:
                raise OSError("short payload")
            digest.update(chunk)
            remaining -= len(chunk)
        if os.read(fd, 1):
            raise OSError("payload grew")
        final = os.fstat(fd)
        if final.st_size != expected_size or final.st_nlink != 1 or digest.hexdigest() != expected_sha:
            raise OSError("payload changed")
        return True
    except OSError:
        raise _error("backup-changed") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _scan_tree(
    handles: _TreeHandles,
    expected_files: set[str],
    categories: list[str],
    *,
    expected_artifacts: Mapping[str, tuple[int, str]] | None = None,
    require_complete: bool = False,
) -> bytes | None:
    """Scan through retained FDs before deleting anything.

    The returned manifest is the exact original bytes.  Every unexpected
    directory/file is rejected before any unlink operation is attempted.
    """
    expected_dirs: set[str] = set(categories)
    if "routes" in categories:
        expected_dirs.update({"routes/imported", "routes/favorites"})
    for path in expected_files:
        parts = path.split("/")
        for index in range(1, len(parts)):
            expected_dirs.add("/".join(parts[:index]))
    actual_count = 0
    manifest_raw: bytes | None = None
    seen_files: set[str] = set()

    def visit(fd: int, prefix: str, depth: int) -> None:
        nonlocal actual_count, manifest_raw
        try:
            names = list(os.scandir(fd))
        except OSError:
            raise _error("backup-changed") from None
        for entry in names:
            name = entry.name
            if not name or name in {".", ".."} or "/" in name or "\x00" in name:
                raise _error("backup-changed")
            relative = f"{prefix}/{name}" if prefix else name
            try:
                info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            except OSError:
                raise _error("backup-changed") from None
            actual_count += 1
            if actual_count > MAX_BACKUP_ENTRIES or depth > MAX_BACKUP_DEPTH:
                raise _error("backup-changed")
            if stat.S_ISLNK(info.st_mode) or info.st_uid != os.getuid():
                raise _error("backup-changed")
            if stat.S_ISDIR(info.st_mode):
                if relative not in expected_dirs or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
                    raise _error("backup-changed")
                child = _open_dir(fd, name)
                handles.child_dirs.append((fd, name, relative, child))
                visit(child, relative, depth + 1)
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE:
                raise _error("backup-changed")
            if relative == "manifest.json":
                manifest_raw = _read_fd_regular(fd, name, max_bytes=MAX_MANIFEST_BYTES)
                continue
            if relative not in expected_files:
                raise _error("backup-changed")
            if expected_artifacts is not None:
                expected = expected_artifacts.get(relative)
                if expected is None:
                    raise _error("backup-changed")
                present = _verify_payload_fd(fd, name, expected[0], expected[1], allow_missing=not require_complete)
                if not present:
                    continue
            handles.files.append((fd, name, relative))
            seen_files.add(relative)

    visit(handles.backup_fd, "", 0)
    if require_complete and seen_files != expected_files:
        raise _error("backup-changed")
    return manifest_raw


def _read_fd_regular(parent_fd: int, name: str, *, max_bytes: int) -> bytes:
    fd: int | None = None
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0), dir_fd=parent_fd)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE or info.st_size > max_bytes:
            raise OSError("unsafe file")
        data = bytearray()
        while len(data) < info.st_size:
            chunk = os.read(fd, min(64 * 1024, info.st_size - len(data)))
            if not chunk:
                raise OSError("short read")
            data.extend(chunk)
        if os.read(fd, 1) or os.fstat(fd).st_size != info.st_size:
            raise OSError("changed file")
        return bytes(data)
    except OSError:
        raise _error("backup-changed") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _fsync_fd(fd: int) -> None:
    try:
        os.fsync(fd)
    except OSError:
        raise _error("operation-failed") from None


def _artifact_expectations(manifest: Mapping[str, Any]) -> dict[str, tuple[int, str]]:
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise _error("backup-changed")
    result: dict[str, tuple[int, str]] = {}
    for item in artifacts:
        if not isinstance(item, Mapping):
            raise _error("backup-changed")
        path = item.get("path")
        size = item.get("byteCount")
        digest = item.get("sha256")
        if not isinstance(path, str) or type(size) is not int or not isinstance(digest, str) or path in result:
            raise _error("backup-changed")
        result[path] = (size, digest)
    return result


def _remove_empty_recovery(root: _RootHandle | Path, transfer_id: str, categories: list[str]) -> None:
    """Recover only an empty, manifest-less tree after a deletion crash."""
    if not isinstance(root, _RootHandle):
        with _RootHandle.open(Path(root)) as retained:
            return _remove_empty_recovery(retained, transfer_id, categories)
    handles = _open_tree_optional(root, transfer_id)
    if handles is None:
        return
    try:
        allowed: set[str] = set(categories)
        if "routes" in categories:
            allowed.update({"routes/imported", "routes/favorites"})
        count = 0
        dirs: list[tuple[int, str, str, int]] = []

        def visit(fd: int, prefix: str, depth: int) -> None:
            nonlocal count
            try:
                names = list(os.scandir(fd))
            except OSError:
                raise _error("backup-changed") from None
            for entry in names:
                name = entry.name
                relative = f"{prefix}/{name}" if prefix else name
                count += 1
                if count > MAX_BACKUP_ENTRIES or depth > MAX_BACKUP_DEPTH:
                    raise _error("backup-changed")
                try:
                    info = os.stat(name, dir_fd=fd, follow_symlinks=False)
                except OSError:
                    raise _error("backup-changed") from None
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE or relative not in allowed:
                    raise _error("backup-changed")
                child = _open_dir(fd, name)
                dirs.append((fd, name, relative, child))
                visit(child, relative, depth + 1)

        visit(handles.backup_fd, "", 0)
        for parent_fd, name, _relative, _child in sorted(dirs, key=lambda item: item[2].count("/"), reverse=True):
            try:
                os.rmdir(name, dir_fd=parent_fd)
            except OSError:
                raise _error("backup-changed") from None
            _fsync_fd(parent_fd)
        try:
            os.rmdir("backup", dir_fd=handles.transaction_fd)
        except OSError:
            raise _error("backup-changed") from None
        _fsync_fd(handles.transaction_fd)
        _fsync_fd(handles.transactions_fd)
    finally:
        handles.close()


def _delete_payload(
    root: _RootHandle | Path,
    source: _Source,
    manifest_raw: bytes,
    manifest: Mapping[str, Any],
    *,
    require_complete: bool = True,
) -> None:
    if not isinstance(root, _RootHandle):
        with _RootHandle.open(Path(root)) as retained:
            return _delete_payload(retained, source, manifest_raw, manifest, require_complete=require_complete)
    expected_artifacts = _artifact_expectations(manifest)
    expected_files = set(expected_artifacts)
    categories = _categories(source.journal)
    handles = _open_tree(root, source.transfer_id)
    try:
        scanned_manifest = _scan_tree(
            handles,
            expected_files,
            categories,
            expected_artifacts=expected_artifacts,
            require_complete=require_complete,
        )
        if scanned_manifest is None or scanned_manifest != manifest_raw:
            raise _error("backup-changed")
        if hashlib.sha256(scanned_manifest).hexdigest() != source.journal.get("rawManifestSHA256"):
            raise _error("backup-changed")
        # The scan completed before mutation.  Remove payload files and flush
        # each containing directory, retaining manifest.json until the end.
        for parent_fd, name, relative in handles.files:
            try:
                expected = expected_artifacts.get(relative)
                if expected is None:
                    raise _error("backup-changed")
                # Revalidate immediately before unlink so a payload changed
                # after the initial inventory scan is never removed.
                present = _verify_payload_fd(
                    parent_fd,
                    name,
                    expected[0],
                    expected[1],
                    allow_missing=not require_complete,
                )
                if not present:
                    continue
                info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE:
                    raise _error("backup-changed")
                os.unlink(name, dir_fd=parent_fd)
            except FileNotFoundError:
                if require_complete:
                    raise _error("backup-changed") from None
                continue
            except BackupBridgeError:
                raise
            except OSError:
                raise _error("operation-failed") from None
            _fsync_fd(parent_fd)
        for parent_fd, name, _relative, _child in sorted(handles.child_dirs, key=lambda item: item[2].count("/"), reverse=True):
            try:
                info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
                    raise _error("backup-changed")
                os.rmdir(name, dir_fd=parent_fd)
            except FileNotFoundError:
                continue
            except BackupBridgeError:
                raise
            except OSError:
                raise _error("operation-failed") from None
            _fsync_fd(parent_fd)
        # Reopen and compare the original manifest immediately before the
        # final unlink.  A changed generation is never adopted.
        fresh = _read_fd_regular(handles.backup_fd, "manifest.json", max_bytes=MAX_MANIFEST_BYTES)
        if fresh != manifest_raw or hashlib.sha256(fresh).hexdigest() != source.journal.get("rawManifestSHA256"):
            raise _error("backup-changed")
        try:
            os.unlink("manifest.json", dir_fd=handles.backup_fd)
        except OSError:
            raise _error("operation-failed") from None
        _fsync_fd(handles.backup_fd)
        try:
            os.rmdir("backup", dir_fd=handles.transaction_fd)
        except OSError:
            raise _error("operation-failed") from None
        _fsync_fd(handles.transaction_fd)
        _fsync_fd(handles.transactions_fd)
    finally:
        handles.close()


def _validate_payload_inventory(root: _RootHandle, source: _Source, manifest_raw: bytes, manifest: Mapping[str, Any]) -> None:
    """Close the manifest inventory before admitting a new deletion intent."""
    expected_artifacts = _artifact_expectations(manifest)
    expected_files = set(expected_artifacts)
    handles = _open_tree(root, source.transfer_id)
    try:
        scanned_manifest = _scan_tree(
            handles,
            expected_files,
            _categories(source.journal),
            expected_artifacts=expected_artifacts,
            require_complete=True,
        )
        if scanned_manifest != manifest_raw or hashlib.sha256(scanned_manifest or b"").hexdigest() != source.journal.get("rawManifestSHA256"):
            raise _error("backup-changed")
    finally:
        handles.close()


def _lock(root: _RootHandle | Path) -> Iterator[None]:
    """The actual shared M1/M2 operation.lock lease."""
    @contextlib.contextmanager
    def lease() -> Iterator[None]:
        if not isinstance(root, _RootHandle):
            with _RootHandle.open(Path(root)) as retained:
                with _lock(retained):
                    yield
            return
        fd: int | None = None
        try:
            fd = os.open(
                "operation.lock",
                os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0),
                PRIVATE_FILE_MODE,
                dir_fd=root.fd,
            )
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE or info.st_size > 64:
                raise _error("storage-unavailable")
            _fsync_dir(root.fd)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError as error:
                if error.errno in {errno.EACCES, errno.EAGAIN}:
                    raise _error("busy") from None
                raise _error("storage-unavailable") from None
            yield
        except BackupBridgeError:
            raise
        except OSError:
            raise _error("storage-unavailable") from None
        finally:
            if fd is not None:
                with contextlib.suppress(OSError):
                    fcntl.flock(fd, fcntl.LOCK_UN)
                with contextlib.suppress(OSError):
                    os.close(fd)
    return lease()


class BackupManager:
    """List, maintain and explicitly delete local M2 backup generations."""

    def __init__(self, state_root: str | Path, *, clock: Callable[[], dt.datetime] | None = None):
        self.state_root = Path(state_root)
        self.catalog = BackupCatalog(self.state_root)
        self.clock = clock or (lambda: dt.datetime.now(dt.timezone.utc))

    def _now(self) -> dt.datetime:
        value = self.clock()
        if not isinstance(value, dt.datetime):
            raise _error("operation-failed")
        return value.astimezone(dt.timezone.utc).replace(microsecond=0) if value.tzinfo else value.replace(tzinfo=dt.timezone.utc, microsecond=0)

    def _sources(self, root: _RootHandle) -> dict[str, _Source]:
        result: dict[str, _Source] = {}
        current_path = root.path / JOURNAL_NAME
        source = _read_source_at(root.fd, JOURNAL_NAME, current=True, path=current_path)
        if source is not None:
            result[source.transfer_id] = source
        history_fd = _open_optional_dir(root.fd, HISTORY_DIRECTORY)
        if history_fd is not None:
            try:
                try:
                    names = list(os.scandir(history_fd))
                except OSError:
                    raise _error("storage-unavailable") from None
                if len(names) > MAX_HISTORY:
                    raise _error("storage-unavailable")
                for entry in names:
                    name = entry.name
                    if not name.endswith(".json") or not UUID_RE.fullmatch(name[:-5]):
                        raise _error("storage-unavailable")
                    source = _read_source_at(history_fd, name, current=False, path=root.path / HISTORY_DIRECTORY / name)
                    if source is None or source.transfer_id != name[:-5]:
                        raise _error("storage-unavailable")
                    existing = result.get(source.transfer_id)
                    if existing is not None:
                        if existing.journal_sha256 != source.journal_sha256 or existing.raw != source.raw:
                            raise _error("backup-changed")
                    else:
                        result[source.transfer_id] = source
            finally:
                with contextlib.suppress(OSError):
                    os.close(history_fd)
        if len(result) > MAX_ENTRIES:
            raise _error("storage-unavailable")
        return result

    def _guard_mutation(self, root: _RootHandle, sources: Mapping[str, _Source]) -> None:
        try:
            from ..Management.management_journal import reject_unresolved_management
        except ImportError:
            from Management.management_journal import reject_unresolved_management
        try:
            if not _same_directory(root.fd, self.state_root):
                raise _error("storage-unavailable")
            reject_unresolved_management(self.state_root)
            if not _same_directory(root.fd, self.state_root):
                raise _error("storage-unavailable")
        except Exception as error:
            code = getattr(error, "code", "storage-unavailable")
            raise _error("busy" if code == "transaction-conflict" else "storage-unavailable") from None
        # Read M1's actual current journal.  A completed receipt may be
        # released; every other current record keeps this manager read-only.
        setup_raw = _read_fd_regular_optional(root.fd, "journal.json", max_bytes=MAX_JOURNAL_BYTES)
        if setup_raw is not None:
            try:
                from ..Setup.setup_journal import JournalStore
            except ImportError:
                from Setup.setup_journal import JournalStore
            try:
                setup = _parse_json(setup_raw, maximum=MAX_JOURNAL_BYTES)
                JournalStore._validate(setup)
            except Exception:
                raise _error("storage-unavailable") from None
            if setup is not None:
                complete = False
                transactions_fd: int | None = None
                transaction_fd: int | None = None
                try:
                    transactions_fd = _open_optional_dir(root.fd, "transactions")
                    if transactions_fd is not None:
                        transaction_fd = _open_optional_dir(transactions_fd, setup["setupID"])
                    transaction = self.state_root / "transactions" / setup["setupID"]
                    if transaction_fd is not None and _same_directory(transaction_fd, transaction):
                        complete = JournalStore._completed_eligible(setup, transaction)
                        # The existing predicate uses Path APIs internally;
                        # reject a root replacement observed across that
                        # read rather than trusting a different transaction.
                        complete = complete and _same_directory(transaction_fd, transaction)
                except Exception:
                    complete = False
                finally:
                    for fd in (transaction_fd, transactions_fd):
                        if fd is not None:
                            with contextlib.suppress(OSError):
                                os.close(fd)
                if not complete:
                    raise _error("busy")
        current = next((source for source in sources.values() if source.current), None)
        if current is not None and not _is_terminal(current.journal):
            raise _error("busy")

    @staticmethod
    def _entry_map(catalog: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
        return {item["transferID"]: item for item in catalog["entries"]}

    @staticmethod
    def _verify_binding(source: _Source, entry: Mapping[str, Any]) -> None:
        expected = {
            "transferID": source.transfer_id,
            "dataSetID": source.journal.get("dataSetID"),
            "deviceID": source.journal.get("deviceID"),
            "journalSHA256": source.journal_sha256,
            "rawManifestSHA256": source.journal.get("rawManifestSHA256"),
        }
        if any(entry.get(key) != value for key, value in expected.items()):
            raise _error("backup-changed")

    def _entry_for_source(self, source: _Source, entries: Mapping[str, dict[str, Any]]) -> dict[str, Any] | None:
        entry = entries.get(source.transfer_id)
        if entry is not None:
            if not _is_complete(source.journal):
                raise _error("backup-changed")
            self._verify_binding(source, entry)
        return entry

    def _row(self, root: _RootHandle, source: _Source | None, entry: Mapping[str, Any] | None, *, pending: bool) -> dict[str, Any]:
        if source is None:
            assert entry is not None
            return {
                "transferID": entry["transferID"],
                "dataSetID": entry["dataSetID"],
                "deviceID": entry["deviceID"],
                "categories": [],
                "counts": None,
                "kind": "deleted" if entry["deleted"] else "missing",
                "completedObservedAt": entry["completedObservedAt"],
                "deleteAfter": entry["deleteAfter"],
                "canDelete": False,
                "canContinue": False,
            }
        complete = _is_complete(source.journal)
        categories = _categories(source.journal)
        entry_deleted = bool(entry and entry.get("deleted"))
        kind = "incomplete"
        if not complete:
            _stat_incomplete_backup(source, root)
        elif entry_deleted and _stat_incomplete_backup(source, root):
            # A tombstone is committed only after the fixed package root has
            # been removed.  Seeing it again means an unbound generation has
            # appeared and must never be silently adopted.
            raise _error("backup-changed")
        if entry_deleted:
            kind = "deleted"
        elif complete:
            kind = "completed" if _manifest_info(source, root) is not None else "missing"
        counts = source.journal.get("counts") if complete and isinstance(source.journal.get("counts"), Mapping) else None
        if counts is not None:
            counts = dict(counts)
        observed = entry.get("completedObservedAt") if entry else None
        expires = entry.get("deleteAfter") if entry else None
        current_active = source.current and not _is_terminal(source.journal)
        return {
            "transferID": source.transfer_id,
            "dataSetID": source.journal["dataSetID"],
            "deviceID": source.journal["deviceID"],
            "categories": categories,
            "counts": counts,
            "kind": kind,
            "completedObservedAt": observed,
            "deleteAfter": expires,
            "canDelete": kind == "completed" and entry is not None and not entry_deleted and not pending,
            "canContinue": kind == "incomplete" and current_active,
        }

    def _list_payload(self, root: _RootHandle) -> dict[str, Any]:
        catalog = self.catalog.read(root)
        sources = self._sources(root)
        entries = self._entry_map(catalog)
        rows: list[dict[str, Any]] = []
        for source in sources.values():
            entry = self._entry_for_source(source, entries)
            rows.append(self._row(root, source, entry, pending=catalog["deletion"] is not None))
        for transfer, entry in entries.items():
            if transfer not in sources:
                rows.append(self._row(root, None, entry, pending=catalog["deletion"] is not None))
        rows.sort(key=lambda row: row["transferID"])
        return {"entries": rows, "pendingDeletion": catalog["deletion"] is not None}

    def list_payload(self) -> dict[str, Any]:
        if not self.state_root.exists():
            return {"entries": [], "pendingDeletion": False}
        with _RootHandle.open(self.state_root) as root:
            return self._list_payload(root)

    def list(self) -> dict[str, Any]:
        """Public manager spelling used by direct Mac-side callers."""
        return self.list_payload()

    def _delete_bound(self, root: _RootHandle, source: _Source, *, recovery: bool) -> None:
        fresh_sources = self._sources(root)
        fresh = fresh_sources.get(source.transfer_id)
        if fresh is None or fresh.journal_sha256 != source.journal_sha256 or not _is_complete(fresh.journal):
            raise _error("backup-changed")
        source = fresh
        manifest = _manifest_info(source, root)
        if manifest is None:
            if not recovery:
                raise _error("backup-changed")
            _remove_empty_recovery(root, source.transfer_id, _categories(source.journal))
            return
        raw, value = manifest
        _delete_payload(root, source, raw, value, require_complete=not recovery)

    def _commit_delete(self, root: _RootHandle, catalog: dict[str, Any], source: _Source, *, recovery: bool) -> None:
        entries = self._entry_map(catalog)
        entry = entries.get(source.transfer_id)
        if entry is None:
            raise _error("backup-not-complete")
        self._verify_binding(source, entry)
        if not recovery:
            manifest = _manifest_info(source, root)
            if manifest is None:
                raise _error("backup-changed")
            _validate_payload_inventory(root, source, *manifest)
        catalog["deletion"] = {"transferID": source.transfer_id, "journalSHA256": source.journal_sha256}
        self.catalog.write(catalog, root)
        self._delete_bound(root, source, recovery=recovery)
        entry["deleted"] = True
        catalog["deletion"] = None
        self.catalog.write(catalog, root)

    def maintain(self) -> dict[str, Any]:
        self.catalog.ensure_root()
        with _RootHandle.open(self.state_root) as root, _lock(root):
            catalog = self.catalog.read(root)
            sources = self._sources(root)
            self._guard_mutation(root, sources)
            entries = self._entry_map(catalog)
            # Resume a durable delete intent before making any new decision.
            deletion = catalog.get("deletion")
            if deletion is not None:
                source = sources.get(deletion["transferID"])
                entry = entries.get(deletion["transferID"])
                if source is None or entry is None or source.journal_sha256 != deletion["journalSHA256"]:
                    raise _error("backup-changed")
                self._verify_binding(source, entry)
                self._delete_bound(root, source, recovery=True)
                entry["deleted"] = True
                catalog["deletion"] = None
                self.catalog.write(catalog, root)
                sources = self._sources(root)
                entries = self._entry_map(catalog)
            now = self._now()
            for source in sources.values():
                if not _is_complete(source.journal):
                    continue
                entry = entries.get(source.transfer_id)
                if entry is not None:
                    self._verify_binding(source, entry)
                    if entry["deleted"]:
                        continue
                else:
                    # A complete source without a readable bound package is
                    # retained as a missing row and never becomes authority.
                    if _manifest_info(source, root) is None:
                        continue
                    entry = {
                        "transferID": source.transfer_id,
                        "dataSetID": source.journal["dataSetID"],
                        "deviceID": source.journal["deviceID"],
                        "journalSHA256": source.journal_sha256,
                        "rawManifestSHA256": source.journal["rawManifestSHA256"],
                        "completedObservedAt": _utc_seconds(now),
                        "deleteAfter": _utc_seconds(now + dt.timedelta(days=7)),
                        "deleted": False,
                    }
                    catalog["entries"].append(entry)
                    entries[source.transfer_id] = entry
            self.catalog.write(catalog, root)
            # A due row is deleted only after the exact source binding and
            # manifest have been re-opened under the same global lease.
            for source in list(sources.values()):
                entry = entries.get(source.transfer_id)
                if entry is None or entry["deleted"] or not _is_complete(source.journal):
                    continue
                if entry["deleteAfter"] is None or _timestamp(entry["deleteAfter"]) > now:
                    continue
                # This is a new automatic deletion admission.  It must close
                # the complete manifest inventory before writing the intent;
                # only the earlier durable-intent branch uses recovery=True.
                self._commit_delete(root, catalog, source, recovery=False)
            return self._list_payload(root)

    def delete(self, transfer_id: str) -> dict[str, Any]:
        transfer_id = _uuid(transfer_id)
        self.catalog.ensure_root()
        with _RootHandle.open(self.state_root) as root, _lock(root):
            catalog = self.catalog.read(root)
            if catalog.get("deletion") is not None and catalog["deletion"]["transferID"] != transfer_id:
                raise _error("busy")
            sources = self._sources(root)
            self._guard_mutation(root, sources)
            source = sources.get(transfer_id)
            if source is None or not _is_complete(source.journal):
                raise _error("backup-not-complete")
            entries = self._entry_map(catalog)
            entry = entries.get(transfer_id)
            if entry is None:
                if _manifest_info(source, root) is None:
                    raise _error("backup-not-complete")
                now = self._now()
                entry = {
                    "transferID": transfer_id,
                    "dataSetID": source.journal["dataSetID"],
                    "deviceID": source.journal["deviceID"],
                    "journalSHA256": source.journal_sha256,
                    "rawManifestSHA256": source.journal["rawManifestSHA256"],
                    "completedObservedAt": _utc_seconds(now),
                    "deleteAfter": _utc_seconds(now + dt.timedelta(days=7)),
                    "deleted": False,
                }
                catalog["entries"].append(entry)
                entries[transfer_id] = entry
                self.catalog.write(catalog, root)
            self._verify_binding(source, entry)
            if entry["deleted"]:
                raise _error("backup-not-complete")
            self._commit_delete(root, catalog, source, recovery=False)
            return self._list_payload(root)

    def handle(self, request: Any) -> dict[str, Any]:
        action = getattr(request, "action", None)
        if action == "list":
            return self.list_payload()
        if action == "maintain":
            return self.maintain()
        if action == "delete" and isinstance(getattr(request, "transfer_id", None), str) and getattr(request, "confirmed", None) is True:
            return self.delete(request.transfer_id)
        raise _error("invalid-request")


__all__ = ["BackupCatalog", "BackupManager", "CATALOG_NAME", "MAX_ENTRIES", "validate_catalog"]
