"""Validated fixed-name configuration for the formal producer."""

from __future__ import annotations

import json
import os
import stat
import contextlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from .setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME
except ImportError:  # script execution from the packaged Setup directory
    from setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME

_KEYS = {
    "workspaceRoot",
    "pythonPath",
    "developerDirectory",
    "projectPath",
    "targetBundleID",
    "targetName",
    "stateRoot",
}
MAX_CONFIG_BYTES = 32 * 1024


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SetupBridgeError("configuration-invalid")
        result[key] = value
    return result


def _read_config(path: Path) -> bytes:
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_NONBLOCK", 0)
            | getattr(os, "O_CLOEXEC", 0),
        )
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1 or info.st_size < 0 or info.st_size > MAX_CONFIG_BYTES:
            raise SetupBridgeError("configuration-invalid")
        chunks: list[bytes] = []
        remaining = info.st_size
        while remaining:
            try:
                chunk = os.read(fd, min(64 * 1024, remaining))
            except InterruptedError:
                continue
            if not chunk:
                raise SetupBridgeError("configuration-invalid")
            chunks.append(chunk)
            remaining -= len(chunk)
        try:
            extra = os.read(fd, 1)
        except InterruptedError:
            extra = os.read(fd, 1)
        if extra:
            raise SetupBridgeError("configuration-invalid")
        final = os.fstat(fd)
        if final.st_size != info.st_size or final.st_nlink != 1 or final.st_uid != os.getuid():
            raise SetupBridgeError("configuration-invalid")
        return b"".join(chunks)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("configuration-invalid") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


@dataclass(frozen=True)
class SetupConfiguration:
    workspace_root: Path
    python_path: Path
    developer_directory: Path
    project_path: Path
    target_bundle_id: str
    target_name: str
    state_root: Path

    @classmethod
    def load(cls, path: str | Path) -> "SetupConfiguration":
        config_path = Path(path)
        if not config_path.is_absolute() or config_path.is_symlink() or not config_path.is_file():
            raise SetupBridgeError("configuration-invalid")
        try:
            raw = json.loads(
                _read_config(config_path).decode("utf-8"),
                object_pairs_hook=_pairs,
                parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            )
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError, SetupBridgeError):
            raise SetupBridgeError("configuration-invalid") from None
        if not isinstance(raw, dict) or set(raw) != _KEYS:
            raise SetupBridgeError("configuration-invalid")

        def required_path(name: str) -> Path:
            value = raw.get(name)
            if not isinstance(value, str) or not value or not value.startswith("/"):
                raise SetupBridgeError("configuration-invalid")
            return Path(value)

        workspace = required_path("workspaceRoot")
        python = required_path("pythonPath")
        developer = required_path("developerDirectory")
        project = required_path("projectPath")
        state = required_path("stateRoot")
        if raw.get("targetBundleID") != TARGET_BUNDLE_ID or raw.get("targetName") != TARGET_NAME:
            raise SetupBridgeError("configuration-invalid")
        if not isinstance(raw["targetBundleID"], str) or not isinstance(raw["targetName"], str):
            raise SetupBridgeError("configuration-invalid")
        # The approved venv launcher is a fixed symlink (python -> python3.14)
        # and is checked against the frozen workspace layout below.  All other
        # configured path roots must be direct, owner-controlled paths.
        if workspace.is_symlink() or developer.is_symlink() or project.is_symlink() or state.is_symlink():
            raise SetupBridgeError("configuration-invalid")
        expected_project = workspace / "app" / "GoFly" / "GoFly.xcodeproj"
        expected_python = workspace / "work" / "mac-setup-env" / "bin" / "python"
        expected_state = Path.home() / "Library" / "Application Support" / "GoFlySetup"
        if project != expected_project or python != expected_python or developer != Path("/Applications/Xcode.app/Contents/Developer") or state != expected_state:
            raise SetupBridgeError("configuration-invalid")
        return cls(workspace, python, developer, project, TARGET_BUNDLE_ID, TARGET_NAME, state)

    def as_dict(self) -> dict[str, str]:
        return {
            "workspaceRoot": str(self.workspace_root),
            "pythonPath": str(self.python_path),
            "developerDirectory": str(self.developer_directory),
            "projectPath": str(self.project_path),
            "targetBundleID": self.target_bundle_id,
            "targetName": self.target_name,
            "stateRoot": str(self.state_root),
        }

    def validate_read_only_paths(self) -> None:
        """Validate fixed paths without invoking Xcode or a device."""

        if not self.workspace_root.is_dir() or self.workspace_root.is_symlink():
            raise SetupBridgeError("configuration-invalid")
        expected_project = self.workspace_root / "app" / "GoFly" / "GoFly.xcodeproj"
        expected_python = self.workspace_root / "work" / "mac-setup-env" / "bin" / "python"
        if self.project_path != expected_project:
            raise SetupBridgeError("configuration-invalid")
        if not self.project_path.is_dir() or self.project_path.suffix != ".xcodeproj" or self.project_path.is_symlink():
            raise SetupBridgeError("configuration-invalid")
        if self.developer_directory != Path("/Applications/Xcode.app/Contents/Developer"):
            raise SetupBridgeError("configuration-invalid")
        expected_state = Path.home() / "Library" / "Application Support" / "GoFlySetup"
        if self.state_root != expected_state:
            raise SetupBridgeError("configuration-invalid")
        if self.python_path != expected_python or not self.python_path.exists():
            raise SetupBridgeError("configuration-invalid")
        # The approved virtualenv entry is intentionally a symlink on the
        # developer machine (python -> python3.14).  Permit that one fixed
        # link, while rejecting a config-selected interpreter elsewhere.
        if self.python_path.is_symlink():
            target = self.python_path.resolve()
            if target.name != "python3.14" or not target.is_file() or not os.access(target, os.X_OK):
                raise SetupBridgeError("configuration-invalid")
        elif not self.python_path.is_file() or not os.access(self.python_path, os.X_OK):
            raise SetupBridgeError("configuration-invalid")
        if self.developer_directory.is_symlink() or not self.developer_directory.is_dir():
            raise SetupBridgeError("configuration-invalid")

    def ensure_state_root(self) -> Path:
        if self.state_root.exists() and self.state_root.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        try:
            if not self.state_root.exists():
                self.state_root.mkdir(parents=True, exist_ok=False, mode=0o700)
            fd = os.open(
                self.state_root,
                os.O_RDONLY
                | os.O_NOFOLLOW
                | getattr(os, "O_DIRECTORY", 0)
                | getattr(os, "O_NONBLOCK", 0)
                | getattr(os, "O_CLOEXEC", 0),
            )
            try:
                info = os.fstat(fd)
            finally:
                os.close(fd)
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid()
            or stat.S_IMODE(info.st_mode) != 0o700
        ):
            raise SetupBridgeError("storage-unavailable")
        return self.state_root
