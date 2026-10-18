"""Pinned iOS support preparation with query-first proof.

The dependency cache is an untrusted input source.  A fetched generation is
copied into a private, closed inventory before it can be used by a device
service.  Cryptex's private normalized inventory and its ``Restore`` layout
are retained separately because the pinned dependency consumes the latter.
"""

from __future__ import annotations

import contextlib
import hashlib
import importlib
import os
import plistlib
import secrets
import shutil
import stat
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

try:
    from .setup_adapters import MAX_ARTIFACT_BYTES, MAX_MANIFEST_BYTES, SupportObservation, _run
    from .setup_protocol import SetupBridgeError
    from .setup_producer import support_method
except ImportError:  # script execution from the packaged Setup directory
    from setup_adapters import MAX_ARTIFACT_BYTES, MAX_MANIFEST_BYTES, SupportObservation, _run
    from setup_protocol import SetupBridgeError
    from setup_producer import support_method


_PRIVATE_DIR_MODE = 0o700
_PRIVATE_FILE_MODE = 0o600
_MAX_COMPONENTS = 64
_MAX_COMPONENT_LENGTH = 255
_MAX_VERSION_LENGTH = 128
_CRYPTEX_PAYLOADS: tuple[tuple[str, str], ...] = (
    ("Cryptex1,GenericDmg", "Image.dmg"),
    ("Cryptex1,GenericTrustCache", "Image.dmg.trustcache"),
    ("Cryptex1,CryptexInfoPlist", "Image.dmg.cryptex_info"),
    ("Cryptex1,GenericVolume", "Image.dmg.root_hash"),
)


@dataclass(frozen=True)
class SupportGeneration:
    method: str
    restore_dir: Path
    files: Mapping[str, tuple[int, str]]
    manifest_sha256: str


def _failure(code: str = "support-unavailable") -> SetupBridgeError:
    return SetupBridgeError(code)


def _flags(*names: str) -> int:
    return sum(getattr(os, name, 0) for name in names)


def _uid_allowed(uid: int) -> bool:
    return uid in {os.getuid(), 0}


def _check_dir_stat(info: os.stat_result, *, private: bool) -> None:
    owner_ok = info.st_uid == os.getuid() if private else _uid_allowed(info.st_uid)
    if not stat.S_ISDIR(info.st_mode) or not owner_ok:
        raise _failure()
    if private and stat.S_IMODE(info.st_mode) != _PRIVATE_DIR_MODE:
        raise _failure()


def _check_file_stat(
    info: os.stat_result,
    *,
    max_bytes: int,
    private: bool,
    source: bool = False,
) -> None:
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise _failure()
    if info.st_size <= 0 or info.st_size > max_bytes:
        raise _failure()
    owner_ok = info.st_uid == os.getuid() if private else _uid_allowed(info.st_uid)
    if not owner_ok:
        raise _failure()
    if private:
        if stat.S_IMODE(info.st_mode) != _PRIVATE_FILE_MODE:
            raise _failure()
    elif source:
        # Dependency cache files may retain ordinary 0644 permissions, but a
        # group/world writable file is not an acceptable apply-only source.
        if stat.S_IMODE(info.st_mode) & 0o022:
            raise _failure()


def _lexical_absolute(path: Path) -> Path:
    # ``absolute`` is lexical and does not resolve a symlink in any ancestor.
    absolute = Path(os.path.abspath(os.fspath(path)))
    # macOS exposes /var and /tmp as stable system symlinks.  Resolve only
    # those two trusted roots so a normal TemporaryDirectory remains usable;
    # every project/cache descendant is still walked with O_NOFOLLOW.
    if absolute.parts and absolute.parts[0] == "/" and len(absolute.parts) > 1:
        prefix = Path("/") / absolute.parts[1]
        if prefix in {Path("/var"), Path("/tmp")} and prefix.is_symlink():
            target = Path(os.path.realpath(prefix))
            if target in {Path("/private/var"), Path("/private/tmp")}:
                return target.joinpath(*absolute.parts[2:])
    return absolute


def _open_dir_path(path: Path, *, create: bool = False, private: bool = False) -> int:
    """Open a directory by walking every component with O_NOFOLLOW."""
    absolute = _lexical_absolute(Path(path))
    try:
        fd = os.open(
            absolute.anchor or os.sep,
            _flags("O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
        )
    except OSError:
        raise _failure() from None
    try:
        components = [part for part in absolute.parts if part not in {absolute.anchor, ""}]
        if len(components) > _MAX_COMPONENTS:
            raise _failure()
        for index, component in enumerate(components):
            if component in {".", ".."} or "\x00" in component or len(component) > _MAX_COMPONENT_LENGTH:
                raise _failure()
            next_fd: int | None = None
            try:
                next_fd = os.open(
                    component,
                    _flags("O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
                    dir_fd=fd,
                )
            except FileNotFoundError:
                if not create:
                    raise _failure() from None
                os.mkdir(component, _PRIVATE_DIR_MODE, dir_fd=fd)
                next_fd = os.open(
                    component,
                    _flags("O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
                    dir_fd=fd,
                )
            info = os.fstat(next_fd)
            # The final directory is the private boundary.  Trusted system
            # ancestors such as /private and /private/var retain their normal
            # modes; newly created descendants are always 0700.
            is_last = index == len(components) - 1
            _check_dir_stat(info, private=private if is_last else False)
            os.close(fd)
            fd = next_fd
        _check_dir_stat(os.fstat(fd), private=private)
        return fd
    except OSError:
        with contextlib.suppress(OSError):
            os.close(fd)
        raise _failure() from None
    except SetupBridgeError:
        with contextlib.suppress(OSError):
            os.close(fd)
        raise


def _open_regular_path(path: Path, *, max_bytes: int, private: bool = False, source: bool = False) -> int:
    """Open a file after no-following every ancestor and the leaf."""
    absolute = _lexical_absolute(Path(path))
    name = absolute.name
    if not name or name in {".", ".."} or "\x00" in name or len(name) > _MAX_COMPONENT_LENGTH:
        raise _failure()
    parent_fd = _open_dir_path(absolute.parent, private=private)
    try:
        try:
            fd = os.open(
                name,
                _flags("O_RDONLY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
                dir_fd=parent_fd,
            )
        except OSError:
            raise _failure() from None
        try:
            _check_file_stat(os.fstat(fd), max_bytes=max_bytes, private=private, source=source)
            return fd
        except Exception:
            os.close(fd)
            raise
    finally:
        os.close(parent_fd)


def _read_fd(fd: int, *, max_bytes: int) -> bytes:
    info = os.fstat(fd)
    if info.st_size > max_bytes:
        raise _failure()
    result = bytearray()
    while len(result) < max_bytes:
        try:
            chunk = os.read(fd, min(1024 * 1024, max_bytes - len(result)))
        except InterruptedError:
            continue
        if not chunk:
            break
        result.extend(chunk)
    if len(result) != info.st_size:
        raise _failure()
    after = os.fstat(fd)
    if _file_signature(after) != _file_signature(info):
        raise _failure()
    return bytes(result)


def _read_private(path: Path, *, max_bytes: int) -> bytes:
    fd = _open_regular_path(path, max_bytes=max_bytes, private=True)
    try:
        return _read_fd(fd, max_bytes=max_bytes)
    finally:
        os.close(fd)


def _read_source(path: Path, *, max_bytes: int) -> bytes:
    fd = _open_regular_path(path, max_bytes=max_bytes, source=True)
    try:
        return _read_fd(fd, max_bytes=max_bytes)
    finally:
        os.close(fd)


def _hash_fd(fd: int, *, max_bytes: int) -> tuple[int, str]:
    info = os.fstat(fd)
    if info.st_size <= 0 or info.st_size > max_bytes:
        raise _failure()
    digest = hashlib.sha256()
    total = 0
    while True:
        try:
            chunk = os.read(fd, 1024 * 1024)
        except InterruptedError:
            continue
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise _failure()
        digest.update(chunk)
    after = os.fstat(fd)
    if total != info.st_size or _file_signature(after) != _file_signature(info):
        raise _failure()
    return total, digest.hexdigest()


def _file_signature(info: os.stat_result) -> tuple[int, int, int, int, int, int]:
    return (info.st_dev, info.st_ino, info.st_size, info.st_nlink, info.st_mtime_ns, info.st_ctime_ns)


def _fsync_dir(path: Path) -> None:
    fd = _open_dir_path(path, private=True)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _hash_private_at(directory_fd: int, name: str, *, max_bytes: int) -> tuple[int, str]:
    try:
        fd = os.open(name, _flags("O_RDONLY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"), dir_fd=directory_fd)
    except OSError:
        raise _failure() from None
    try:
        _check_file_stat(os.fstat(fd), max_bytes=max_bytes, private=True)
        return _hash_fd(fd, max_bytes=max_bytes)
    finally:
        os.close(fd)


def _safe_relative(value: Any) -> tuple[str, ...]:
    if not isinstance(value, str) or not value or "\x00" in value or "\\" in value:
        raise _failure()
    if value.startswith("/") or value.endswith("/") or "//" in value or ":" in value:
        raise _failure()
    parsed = PurePosixPath(value)
    parts = parsed.parts
    if not parts or len(parts) > _MAX_COMPONENTS or parsed.as_posix() != value:
        raise _failure()
    if any(part in {"", ".", ".."} or len(part) > _MAX_COMPONENT_LENGTH for part in parts):
        raise _failure()
    return tuple(parts)


def _write_private_at(directory_fd: int, name: str, payload: bytes) -> None:
    if not name or "/" in name or "\x00" in name or len(payload) <= 0:
        raise _failure()
    temporary = f".{name}.{secrets.token_hex(12)}.staging"
    fd: int | None = None
    try:
        fd = os.open(
            temporary,
            _flags("O_WRONLY", "O_CREAT", "O_EXCL", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
            _PRIVATE_FILE_MODE,
            dir_fd=directory_fd,
        )
        os.fchmod(fd, _PRIVATE_FILE_MODE)
        offset = 0
        while offset < len(payload):
            written = os.write(fd, payload[offset:])
            if written <= 0:
                raise _failure()
            offset += written
        os.fsync(fd)
        _check_file_stat(os.fstat(fd), max_bytes=len(payload), private=True)
        os.close(fd)
        fd = None
        os.rename(temporary, name, src_dir_fd=directory_fd, dst_dir_fd=directory_fd)
        os.fsync(directory_fd)
    except FileExistsError:
        raise _failure("transaction-conflict") from None
    except SetupBridgeError:
        raise
    except OSError:
        raise _failure() from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
        with contextlib.suppress(OSError):
            os.unlink(temporary, dir_fd=directory_fd)


def _copy_regular(source: Path, destination: Path, *, max_bytes: int) -> None:
    """Copy one bounded regular source through no-follow directory walks."""
    source_fd: int | None = None
    output_fd: int | None = None
    temporary: str | None = None
    destination_parent: int | None = None
    try:
        source_fd = _open_regular_path(source, max_bytes=max_bytes, source=True)
        source_info = os.fstat(source_fd)
        destination_parent = _open_dir_path(destination.parent, create=True, private=True)
        name = destination.name
        if not name or "/" in name or "\x00" in name or len(name) > _MAX_COMPONENT_LENGTH:
            raise _failure()
        try:
            os.stat(name, dir_fd=destination_parent, follow_symlinks=False)
        except FileNotFoundError:
            pass
        else:
            raise _failure("transaction-conflict")
        temporary = f".{name}.{secrets.token_hex(12)}.staging"
        output_fd = os.open(
            temporary,
            _flags("O_WRONLY", "O_CREAT", "O_EXCL", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"),
            _PRIVATE_FILE_MODE,
            dir_fd=destination_parent,
        )
        os.fchmod(output_fd, _PRIVATE_FILE_MODE)
        total = 0
        while total < source_info.st_size:
            try:
                chunk = os.read(source_fd, min(1024 * 1024, source_info.st_size - total))
            except InterruptedError:
                continue
            if not chunk:
                raise _failure()
            total += len(chunk)
            if total > max_bytes:
                raise _failure()
            offset = 0
            while offset < len(chunk):
                written = os.write(output_fd, chunk[offset:])
                if written <= 0:
                    raise _failure()
                offset += written
        if total != source_info.st_size:
            raise _failure()
        if _file_signature(os.fstat(source_fd)) != _file_signature(source_info):
            raise _failure()
        os.fsync(output_fd)
        _check_file_stat(os.fstat(output_fd), max_bytes=max_bytes, private=True)
        os.close(output_fd)
        output_fd = None
        os.rename(temporary, name, src_dir_fd=destination_parent, dst_dir_fd=destination_parent)
        temporary = None
        os.fsync(destination_parent)
    except SetupBridgeError:
        raise
    except (OSError, ValueError):
        raise _failure() from None
    finally:
        if source_fd is not None:
            with contextlib.suppress(OSError):
                os.close(source_fd)
        if output_fd is not None:
            with contextlib.suppress(OSError):
                os.close(output_fd)
        if destination_parent is not None:
            if temporary is not None:
                with contextlib.suppress(OSError):
                    os.unlink(temporary, dir_fd=destination_parent)
            with contextlib.suppress(OSError):
                os.close(destination_parent)


def _manifest_identity(manifest: Mapping[str, Any]) -> Mapping[str, Any]:
    identities = manifest.get("BuildIdentities")
    if not isinstance(identities, list):
        raise _failure()
    for candidate in identities:
        if not isinstance(candidate, Mapping) or not isinstance(candidate.get("Info"), Mapping):
            continue
        if str(candidate["Info"].get("Variant", "")).endswith("Developer Disk Image Cryptex"):
            version = candidate.get("Cryptex1,Version")
            if not isinstance(version, str) or not version or len(version) > _MAX_VERSION_LENGTH or "\x00" in version:
                raise _failure()
            return candidate
    raise _failure()


def _cryptex_manifest_entries(manifest: Mapping[str, Any]) -> list[tuple[str, str, tuple[str, ...]]]:
    identity = _manifest_identity(manifest)
    payload = identity.get("Manifest")
    if not isinstance(payload, Mapping):
        raise _failure()
    result: list[tuple[str, str, tuple[str, ...]]] = []
    seen: set[tuple[str, ...]] = set()
    for key, normalized in _CRYPTEX_PAYLOADS:
        entry = payload.get(key)
        info = entry.get("Info") if isinstance(entry, Mapping) else None
        relative = info.get("Path") if isinstance(info, Mapping) else None
        parts = _safe_relative(relative)
        if parts in seen:
            raise _failure()
        seen.add(parts)
        result.append((key, normalized, parts))
    return result


def _read_manifest(path: Path, *, private: bool) -> tuple[bytes, Mapping[str, Any]]:
    raw = _read_private(path, max_bytes=MAX_MANIFEST_BYTES) if private else _read_source(path, max_bytes=MAX_MANIFEST_BYTES)
    try:
        value = plistlib.loads(raw)
    except (ValueError, plistlib.InvalidFileException):
        raise _failure() from None
    if not isinstance(value, Mapping):
        raise _failure()
    return raw, value


def _validate_actual(actual: Path, formal: Path, manifest_raw: bytes, entries: list[tuple[str, str, tuple[str, ...]]]) -> None:
    actual_fd = _open_dir_path(actual, private=True)
    formal_fd = _open_dir_path(formal, private=True)
    try:
        expected_files: set[tuple[str, ...]] = {("BuildManifest.plist",)}
        for _, _, parts in entries:
            expected_files.add(parts)
        expected_dirs: set[tuple[str, ...]] = set()
        for file_parts in expected_files:
            for index in range(1, len(file_parts)):
                expected_dirs.add(file_parts[:index])

        def walk(directory_fd: int, prefix: tuple[str, ...]) -> None:
            try:
                names = os.listdir(directory_fd)
            except OSError:
                raise _failure() from None
            for name in names:
                if name.startswith(".") or name in {".", ".."} or len(name) > _MAX_COMPONENT_LENGTH:
                    raise _failure()
                parts = prefix + (name,)
                info = os.stat(name, dir_fd=directory_fd, follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    _check_dir_stat(info, private=True)
                    child_fd = os.open(name, _flags("O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"), dir_fd=directory_fd)
                    try:
                        if parts not in expected_dirs:
                            raise _failure()
                        walk(child_fd, parts)
                    finally:
                        os.close(child_fd)
                elif stat.S_ISREG(info.st_mode):
                    _check_file_stat(info, max_bytes=MAX_ARTIFACT_BYTES, private=True)
                    if parts not in expected_files:
                        raise _failure()
                else:
                    raise _failure()

        walk(actual_fd, ())
        if _read_private(actual / "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES) != manifest_raw:
            raise _failure()
        actual_manifest = _hash_private_at(actual_fd, "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES)
        formal_manifest = _hash_private_at(formal_fd, "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES)
        if actual_manifest != formal_manifest:
            raise _failure()
        for _, normalized, parts in entries:
            normalized_hash = _hash_private_at(formal_fd, normalized, max_bytes=MAX_ARTIFACT_BYTES)
            parent_fd = actual_fd
            opened: list[int] = []
            try:
                for component in parts[:-1]:
                    child = os.open(component, _flags("O_RDONLY", "O_DIRECTORY", "O_NOFOLLOW", "O_CLOEXEC", "O_NONBLOCK"), dir_fd=parent_fd)
                    opened.append(child)
                    parent_fd = child
                actual_hash = _hash_private_at(parent_fd, parts[-1], max_bytes=MAX_ARTIFACT_BYTES)
            finally:
                for child in reversed(opened):
                    os.close(child)
            if actual_hash != normalized_hash:
                raise _failure()
    finally:
        os.close(actual_fd)
        os.close(formal_fd)


def _materialize_cryptex_restore(formal_dir: Path, *, require_existing: bool = False) -> Path:
    """Retain pmd3's original manifest paths in a private ``.actual`` sibling."""
    formal_dir = Path(formal_dir)
    manifest_raw, manifest = _read_manifest(formal_dir / "BuildManifest.plist", private=True)
    entries = _cryptex_manifest_entries(manifest)
    actual = formal_dir.with_name(formal_dir.name + ".actual")
    if actual.is_symlink() or (actual.exists() and not actual.is_dir()):
        raise _failure()
    if actual.exists():
        _validate_actual(actual, formal_dir, manifest_raw, entries)
        return actual
    if require_existing:
        raise _failure()
    parent_fd = _open_dir_path(formal_dir.parent, private=True)
    stage: Path | None = None
    try:
        stage = formal_dir.parent / f".{actual.name}.{secrets.token_hex(12)}.staging"
        stage_fd = _open_dir_path(stage, create=True, private=True)
        os.close(stage_fd)
        _copy_regular(formal_dir / "BuildManifest.plist", stage / "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES)
        for _, normalized, parts in entries:
            _copy_regular(formal_dir / normalized, stage.joinpath(*parts), max_bytes=MAX_ARTIFACT_BYTES)
        _validate_actual(stage, formal_dir, manifest_raw, entries)
        stage_fd = _open_dir_path(stage, private=True)
        try:
            os.fsync(stage_fd)
        finally:
            os.close(stage_fd)
        try:
            os.rename(stage.name, actual.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
        except FileExistsError:
            _validate_actual(actual, formal_dir, manifest_raw, entries)
            return actual
        os.fsync(parent_fd)
        stage = None
        return actual
    except SetupBridgeError:
        raise
    except OSError:
        raise _failure() from None
    finally:
        os.close(parent_fd)
        if stage is not None:
            _remove_staging(stage)


def validate_generation(method: str, restore_dir: str | Path) -> SupportGeneration:
    """Validate the closed private support inventory and stream its hashes."""
    if method not in {"personalized", "cryptex"}:
        raise _failure()
    root = Path(restore_dir)
    root_fd = _open_dir_path(root, private=True)
    try:
        names: dict[str, str] = {
            "MountMethod": "MountMethod",
            "BuildManifest.plist": "manifest",
            "Image.dmg": "image",
            "Image.dmg.trustcache": "trustcache",
        }
        if method == "cryptex":
            names.update({"Image.dmg.cryptex_info": "cryptex_info", "Image.dmg.root_hash": "root_hash"})
        if set(os.listdir(root_fd)) != set(names):
            raise _failure()
        files: dict[str, tuple[int, str]] = {}
        total = 0
        for filename, label in names.items():
            limit = 128 if filename == "MountMethod" else min(MAX_MANIFEST_BYTES if filename == "BuildManifest.plist" else MAX_ARTIFACT_BYTES, MAX_ARTIFACT_BYTES - total)
            size, digest = _hash_private_at(root_fd, filename, max_bytes=limit)
            total += size
            if total > MAX_ARTIFACT_BYTES:
                raise _failure()
            files[label] = (size, digest)
        if _read_private(root / "MountMethod", max_bytes=128) != method.encode("ascii"):
            raise _failure()
        manifest_raw, manifest = _read_manifest(root / "BuildManifest.plist", private=True)
        if len(manifest_raw) > MAX_MANIFEST_BYTES:
            raise _failure()
        if method == "cryptex":
            _cryptex_manifest_entries(manifest)
        return SupportGeneration(method, root, files, files["manifest"][1])
    finally:
        os.close(root_fd)


def _write_method(root: Path, method: str) -> None:
    root_fd = _open_dir_path(root, private=True)
    try:
        _write_private_at(root_fd, "MountMethod", method.encode("ascii"))
    finally:
        os.close(root_fd)


def _remove_staging(path: Path | None) -> None:
    if path is None or ".staging" not in path.name:
        return
    with contextlib.suppress(Exception):
        shutil.rmtree(path)


def _copy_fetched_cryptex(source_root: Path, stage: Path) -> None:
    manifest_raw, manifest = _read_manifest(source_root / "BuildManifest.plist", private=False)
    del manifest_raw
    entries = _cryptex_manifest_entries(manifest)
    _copy_regular(source_root / "BuildManifest.plist", stage / "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES)
    for _, normalized, parts in entries:
        _copy_regular(source_root.joinpath(*parts), stage / normalized, max_bytes=MAX_ARTIFACT_BYTES)


def _copy_fetched_personalized(fetch_result: Any, stage: Path) -> None:
    try:
        image, manifest, trustcache = fetch_result
    except (TypeError, ValueError):
        raise _failure("runtime-api-mismatch") from None
    _copy_regular(Path(manifest), stage / "BuildManifest.plist", max_bytes=MAX_MANIFEST_BYTES)
    _copy_regular(Path(image), stage / "Image.dmg", max_bytes=MAX_ARTIFACT_BYTES)
    _copy_regular(Path(trustcache), stage / "Image.dmg.trustcache", max_bytes=MAX_ARTIFACT_BYTES)


def _ensure_fetched_generation(method: str, restore_dir: Path) -> None:
    """Fetch missing assets into private staging, then publish atomically."""
    if method not in {"personalized", "cryptex"}:
        raise _failure()
    restore_dir = Path(restore_dir)
    actual = restore_dir.with_name(restore_dir.name + ".actual")
    if restore_dir.is_symlink() or (restore_dir.exists() and not restore_dir.is_dir()):
        raise _failure()
    if restore_dir.exists():
        validate_generation(method, restore_dir)
        if method == "cryptex":
            # This copy is derived solely from the validated immutable formal
            # bytes. A crash after formal publication may leave it absent;
            # rebuild only absence, never replace an existing corrupt copy.
            _materialize_cryptex_restore(restore_dir)
        return
    parent_fd = _open_dir_path(restore_dir.parent, create=True, private=True)
    os.close(parent_fd)
    stage: Path | None = None
    actual_stage: Path | None = None
    materialized_actual: Path | None = None
    try:
        stage = restore_dir.parent / f".{restore_dir.name}.{secrets.token_hex(12)}.staging"
        stage_fd = _open_dir_path(stage, create=True, private=True)
        os.close(stage_fd)
        if method == "personalized":
            module = importlib.import_module("pymobiledevice3.services.mobile_image_mounter")
            fetch = getattr(module, "fetch_personalized_ddi", None)
            if not callable(fetch):
                raise _failure("runtime-api-mismatch")
            _copy_fetched_personalized(fetch(), stage)
        else:
            module = importlib.import_module("pymobiledevice3.services.cryptexd")
            fetch = getattr(module, "fetch_cryptex_ddi", None)
            if not callable(fetch):
                raise _failure("runtime-api-mismatch")
            _copy_fetched_cryptex(Path(fetch()), stage)
        _write_method(stage, method)
        validate_generation(method, stage)
        if method == "cryptex":
            _materialize_cryptex_restore(stage)
            source_actual = stage.with_name(stage.name + ".actual")
            materialized_actual = source_actual
            actual_stage = restore_dir.parent / f".{actual.name}.{secrets.token_hex(12)}.staging"
            parent_fd = _open_dir_path(stage.parent, private=True)
            try:
                os.rename(source_actual.name, actual_stage.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            finally:
                os.close(parent_fd)
            materialized_actual = None
            manifest_raw, manifest = _read_manifest(stage / "BuildManifest.plist", private=True)
            _validate_actual(actual_stage, stage, manifest_raw, _cryptex_manifest_entries(manifest))
        _fsync_dir(stage)
        if actual_stage is not None:
            _fsync_dir(actual_stage)
        parent_fd = _open_dir_path(restore_dir.parent, private=True)
        try:
            if restore_dir.exists() or restore_dir.is_symlink():
                raise _failure("transaction-conflict")
            os.rename(stage.name, restore_dir.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            os.fsync(parent_fd)
            if actual_stage is not None:
                if actual.exists() or actual.is_symlink():
                    raise _failure("transaction-conflict")
                os.rename(actual_stage.name, actual.name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
                os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
        stage = None
        actual_stage = None
        validate_generation(method, restore_dir)
        if method == "cryptex":
            _materialize_cryptex_restore(restore_dir, require_existing=True)
    except SetupBridgeError:
        raise
    except Exception:
        raise _failure() from None
    finally:
        _remove_staging(stage)
        _remove_staging(actual_stage)
        _remove_staging(materialized_actual)


class PinnedSupportAdapter:
    """Use one selected support method and one same-device service handle."""

    def __init__(self, device_adapter: Any, *, restore_dir: Path | None = None):
        self.device_adapter = device_adapter
        self.restore_dir = restore_dir

    def _observed_generation_id(self, method: str) -> str | None:
        if self.restore_dir is None:
            return None
        try:
            generation = validate_generation(method, self.restore_dir)
            if method == "cryptex":
                _materialize_cryptex_restore(self.restore_dir, require_existing=True)
            return self._generation_id(generation.restore_dir)
        except SetupBridgeError:
            return None

    def _selected_cryptex_version(self) -> str:
        if self.restore_dir is None:
            raise _failure()
        _, manifest = _read_manifest(Path(self.restore_dir) / "BuildManifest.plist", private=True)
        return str(_manifest_identity(manifest)["Cryptex1,Version"])

    @staticmethod
    def _require_matching_ddi(installed: Any, expected_version: str) -> tuple[str, str]:
        if not isinstance(expected_version, str) or not expected_version or len(expected_version) > _MAX_VERSION_LENGTH or "\x00" in expected_version:
            raise _failure()
        if not isinstance(installed, list):
            raise _failure()
        for item in installed:
            identifier = getattr(item, "identifier", None)
            version = getattr(item, "version", None)
            if identifier != "com.apple.MobileAsset.DDI":
                continue
            if not isinstance(version, str) or not version or len(version) > _MAX_VERSION_LENGTH or "\x00" in version:
                raise _failure()
            if version != expected_version:
                raise _failure()
            return identifier, version
        raise _failure()

    def prepare_generation(self, method: str, restore_dir: Path) -> None:
        _ensure_fetched_generation(method, Path(restore_dir))
        validate_generation(method, Path(restore_dir))
        if method == "cryptex":
            _materialize_cryptex_restore(Path(restore_dir), require_existing=True)

    def _lockdown(self, device_id: str, cache: Path) -> Any:
        opener = getattr(self.device_adapter, "_open", None)
        if not callable(opener):
            raise _failure("runtime-api-mismatch")
        return opener(device_id, cache)

    def query(self, device_id: str, method: str) -> SupportObservation:
        if method not in {"personalized", "cryptex"}:
            raise _failure()
        if method == "personalized":
            return self._query_personalized(device_id)
        return self._query_cryptex(device_id)

    def install(self, device_id: str, method: str, restore_dir: Path) -> SupportObservation:
        self.restore_dir = Path(restore_dir)
        _ensure_fetched_generation(method, self.restore_dir)
        generation = validate_generation(method, self.restore_dir)
        generation_id = self._generation_id(generation.restore_dir)
        if method == "personalized":
            with tempfile.TemporaryDirectory(prefix="gofly-setup-support-") as cache_dir:
                client = self._lockdown(device_id, Path(cache_dir))
                mounter = None
                try:
                    module = importlib.import_module("pymobiledevice3.services.mobile_image_mounter")
                    mounter_cls = getattr(module, "PersonalizedImageMounter", None)
                    if mounter_cls is None:
                        raise _failure("runtime-api-mismatch")
                    mounter = mounter_cls(client)
                    os_version = self._verify_lockdown_identity(client, device_id)
                    _run(mounter.mount(generation.restore_dir / "Image.dmg", generation.restore_dir / "BuildManifest.plist", generation.restore_dir / "Image.dmg.trustcache"))
                    observed = _run(mounter.is_image_mounted("Personalized"))
                    if observed is not True:
                        raise _failure()
                    return SupportObservation(True, method, os_version, generation_id, "Personalized", os_version)
                except SetupBridgeError:
                    raise
                except Exception:
                    raise _failure() from None
                finally:
                    with contextlib.suppress(Exception):
                        if mounter is not None:
                            _run(mounter.close())
                    with contextlib.suppress(Exception):
                        _run(client.close())
        tunnel = None
        service = None
        try:
            userspace = importlib.import_module("pymobiledevice3.remote.userspace_tunnel")
            cryptex_module = importlib.import_module("pymobiledevice3.services.cryptexd")
            tunnel_cls = getattr(userspace, "UserspaceRsdTunnel", None)
            service_cls = getattr(cryptex_module, "CryptexdService", None)
            if tunnel_cls is None or service_cls is None:
                raise _failure("runtime-api-mismatch")
            tunnel = tunnel_cls(serial=device_id, autopair=False, remotepairing_fallback=False)
            rsd = _run(tunnel.aopen())
            self._verify_rsd(rsd, device_id)
            service = service_cls(rsd)
            installed = _run(service.copy_installed())
            if self._ddi(installed) is None:
                runtime_restore = _materialize_cryptex_restore(generation.restore_dir, require_existing=True)
                result = _run(service.auto_install_ddi(runtime_restore))
                if result is None:
                    raise _failure()
            expected_version = self._selected_cryptex_version()
            identifier, version = self._require_matching_ddi(_run(service.copy_installed()), expected_version)
            return SupportObservation(True, method, str(getattr(rsd, "product_version", "")), generation_id, identifier, version)
        except SetupBridgeError:
            raise
        except Exception:
            raise _failure() from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if tunnel is not None:
                    _run(tunnel.aclose())

    def _query_personalized(self, device_id: str) -> SupportObservation:
        with tempfile.TemporaryDirectory(prefix="gofly-setup-support-") as cache_dir:
            client = self._lockdown(device_id, Path(cache_dir))
            mounter = None
            try:
                module = importlib.import_module("pymobiledevice3.services.mobile_image_mounter")
                mounter_cls = getattr(module, "PersonalizedImageMounter", None)
                if mounter_cls is None:
                    raise _failure("runtime-api-mismatch")
                mounter = mounter_cls(client)
                os_version = self._verify_lockdown_identity(client, device_id)
                observed = _run(mounter.is_image_mounted("Personalized"))
                generation_id = self._observed_generation_id("personalized") if observed is True else None
                return SupportObservation(observed is True, "personalized", os_version, generation_id, "Personalized" if observed else None, os_version if observed is True else None)
            except SetupBridgeError:
                raise
            except Exception:
                raise _failure() from None
            finally:
                with contextlib.suppress(Exception):
                    if mounter is not None:
                        _run(mounter.close())
                with contextlib.suppress(Exception):
                    _run(client.close())

    def _query_cryptex(self, device_id: str) -> SupportObservation:
        tunnel = None
        service = None
        try:
            userspace = importlib.import_module("pymobiledevice3.remote.userspace_tunnel")
            cryptex_module = importlib.import_module("pymobiledevice3.services.cryptexd")
            tunnel_cls = getattr(userspace, "UserspaceRsdTunnel", None)
            service_cls = getattr(cryptex_module, "CryptexdService", None)
            if tunnel_cls is None or service_cls is None:
                raise _failure("runtime-api-mismatch")
            tunnel = tunnel_cls(serial=device_id, autopair=False, remotepairing_fallback=False)
            rsd = _run(tunnel.aopen())
            self._verify_rsd(rsd, device_id)
            service = service_cls(rsd)
            ddi = self._ddi(_run(service.copy_installed()))
            version = str(getattr(rsd, "product_version", ""))
            if ddi is None:
                return SupportObservation(False, "cryptex", version, None, None, None)
            # A query may precede apply-only cache preparation.  Without a
            # selected local BuildIdentity there is no safe version wildcard;
            # defer the comparison until prepare_generation/install.
            if self.restore_dir is None or not Path(self.restore_dir).is_dir():
                return SupportObservation(False, "cryptex", version, None, None, None)
            expected_version = self._selected_cryptex_version()
            identifier, installed_version = self._require_matching_ddi([type("Installed", (), {"identifier": ddi[0], "version": ddi[1]})()], expected_version)
            generation_id = self._observed_generation_id("cryptex")
            if generation_id is None:
                return SupportObservation(False, "cryptex", version, None, None, None)
            return SupportObservation(True, "cryptex", version, generation_id, identifier, installed_version)
        except SetupBridgeError:
            raise
        except Exception:
            raise _failure() from None
        finally:
            with contextlib.suppress(Exception):
                if service is not None:
                    _run(service.close())
            with contextlib.suppress(Exception):
                if tunnel is not None:
                    _run(tunnel.aclose())

    @staticmethod
    def _verify_rsd(rsd: Any, device_id: str) -> None:
        if str(getattr(rsd, "udid", "")).lower() != device_id.lower():
            raise _failure("identity-mismatch")
        if not str(getattr(rsd, "product_version", "")):
            raise _failure()

    @staticmethod
    def _generation_id(restore_dir: Path) -> str:
        value = Path(restore_dir).parent.name
        try:
            parsed = uuid.UUID(value)
        except (ValueError, AttributeError):
            raise _failure() from None
        if str(parsed) != value.lower():
            raise _failure()
        return str(parsed)

    @staticmethod
    def _verify_lockdown_identity(client: Any, device_id: str) -> str:
        getter = getattr(client, "get_value", None)
        if not callable(getter):
            raise _failure("runtime-api-mismatch")
        try:
            values = _run(getter())
        except Exception:
            raise _failure("trust-required") from None
        if not isinstance(values, Mapping):
            raise _failure("identity-mismatch")
        if str(values.get("UniqueDeviceID", "")).lower() != device_id.lower():
            raise _failure("identity-mismatch")
        version = values.get("ProductVersion")
        if not isinstance(version, str) or not version or len(version) > 64 or "\x00" in version:
            raise _failure("unsupported-os")
        return version

    @staticmethod
    def _ddi(installed: Any) -> tuple[str, str] | None:
        if not isinstance(installed, list):
            raise _failure()
        for item in installed:
            identifier = getattr(item, "identifier", None)
            version = getattr(item, "version", None)
            if identifier != "com.apple.MobileAsset.DDI":
                continue
            if not isinstance(version, str) or not version or len(version) > _MAX_VERSION_LENGTH or "\x00" in version:
                raise _failure()
            return identifier, version
        return None
