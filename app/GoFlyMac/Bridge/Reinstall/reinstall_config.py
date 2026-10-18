"""Read-only configuration boundary for the protocol-3 reinstall bridge."""

from __future__ import annotations

import errno
import json
import os
import stat
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from ..Setup.setup_config import SetupConfiguration, _pairs, _read_config
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME
except ImportError:  # packaged direct execution from the Bridge directory
    from Setup.setup_config import SetupConfiguration, _pairs, _read_config
    from Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME

_KEYS = {
    "workspaceRoot",
    "pythonPath",
    "developerDirectory",
    "projectPath",
    "targetBundleID",
    "targetName",
    "stateRoot",
    "validatorPath",
}


def _required_absolute(raw: dict[str, Any], key: str) -> Path:
    value = raw.get(key)
    if not isinstance(value, str) or not value or not value.startswith("/") or "\x00" in value:
        raise SetupBridgeError("configuration-invalid")
    path = Path(value)
    if any(part == ".." for part in path.parts):
        raise SetupBridgeError("configuration-invalid")
    return path


def _reject_symlink_components(path: Path) -> None:
    """Reject every existing symlink component without following it."""

    current = Path(path.anchor or "/")
    for part in path.parts:
        if part == current.anchor:
            continue
        current /= part
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            return
        except OSError:
            raise SetupBridgeError("configuration-invalid") from None
        if stat.S_ISLNK(info.st_mode):
            raise SetupBridgeError("configuration-invalid")


def _validate_validator_path_fd(path: Path) -> None:
    """Validate the validator through retained no-follow directory descriptors."""

    if not path.is_absolute():
        raise SetupBridgeError("configuration-invalid")
    flags = (
        os.O_RDONLY
        | getattr(os, "O_NOFOLLOW", 0)
        | getattr(os, "O_NONBLOCK", 0)
        | getattr(os, "O_CLOEXEC", 0)
    )
    directory_flags = flags | getattr(os, "O_DIRECTORY", 0)
    current_fd: int | None = None
    # Absolute paths necessarily begin with trusted system-owned anchors on
    # macOS (for example /private and /private/var).  Once traversal reaches
    # the user's private tree, every following component must remain owned by
    # the current user.  The validator file itself is always user-owned.
    user_tree_started = False
    current_uid = os.getuid()
    try:
        current_fd = os.open(path.anchor or "/", directory_flags)
        components = [part for part in path.parts if part != path.anchor]
        if not components:
            raise SetupBridgeError("configuration-invalid")
        for index, component in enumerate(components):
            leaf = index == len(components) - 1
            try:
                child_fd = os.open(
                    component,
                    flags if leaf else directory_flags,
                    dir_fd=current_fd,
                )
            except OSError as error:
                if error.errno in {errno.EACCES, errno.ELOOP, errno.ENOTDIR, errno.EPERM}:
                    raise SetupBridgeError("configuration-invalid") from None
                if error.errno == errno.ENOENT:
                    raise SetupBridgeError("environment-not-ready") from None
                raise SetupBridgeError("environment-not-ready") from None
            try:
                info = os.fstat(child_fd)
                mode = stat.S_IMODE(info.st_mode)
                if info.st_uid == current_uid:
                    user_tree_started = True
                safe_owner = info.st_uid == current_uid or (
                    not user_tree_started and info.st_uid == 0
                )
                safe_mode = not (mode & 0o7000 or mode & 0o022) and bool(mode & 0o100)
                if leaf:
                    valid = (
                        stat.S_ISREG(info.st_mode)
                        and info.st_uid == current_uid
                        and info.st_nlink == 1
                        and safe_mode
                    )
                else:
                    valid = stat.S_ISDIR(info.st_mode) and safe_owner and info.st_nlink >= 1 and safe_mode
                if not valid:
                    raise SetupBridgeError("configuration-invalid")
            finally:
                os.close(current_fd)
                current_fd = child_fd
    except SetupBridgeError:
        raise
    except OSError as error:
        if error.errno == errno.ENOENT:
            raise SetupBridgeError("environment-not-ready") from None
        raise SetupBridgeError("configuration-invalid") from None
    finally:
        if current_fd is not None:
            try:
                os.close(current_fd)
            except OSError:
                pass


@dataclass(frozen=True)
class ReinstallConfiguration:
    workspace_root: Path
    python_path: Path
    developer_directory: Path
    project_path: Path
    target_bundle_id: str
    target_name: str
    state_root: Path
    validator_path: Path

    def _setup(self) -> SetupConfiguration:
        return SetupConfiguration(
            self.workspace_root,
            self.python_path,
            self.developer_directory,
            self.project_path,
            self.target_bundle_id,
            self.target_name,
            self.state_root,
        )

    @classmethod
    def load(cls, path: str | Path) -> "ReinstallConfiguration":
        config_path = Path(path)
        if not config_path.is_absolute() or config_path.is_symlink() or not config_path.is_file():
            raise SetupBridgeError("configuration-invalid")
        try:
            raw = json.loads(
                _read_config(config_path).decode("utf-8"),
                object_pairs_hook=_pairs,
                parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
                parse_float=lambda _value: (_ for _ in ()).throw(ValueError()),
            )
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError, RecursionError, SetupBridgeError):
            raise SetupBridgeError("configuration-invalid") from None
        if not isinstance(raw, dict) or set(raw) != _KEYS:
            raise SetupBridgeError("configuration-invalid")
        workspace = _required_absolute(raw, "workspaceRoot")
        python = _required_absolute(raw, "pythonPath")
        developer = _required_absolute(raw, "developerDirectory")
        project = _required_absolute(raw, "projectPath")
        state = _required_absolute(raw, "stateRoot")
        validator = _required_absolute(raw, "validatorPath")
        if raw.get("targetBundleID") != TARGET_BUNDLE_ID or raw.get("targetName") != TARGET_NAME:
            raise SetupBridgeError("configuration-invalid")
        if workspace.is_symlink() or developer.is_symlink() or project.is_symlink() or state.is_symlink():
            raise SetupBridgeError("configuration-invalid")
        expected_project = workspace / "app" / "GoFly" / "GoFly.xcodeproj"
        expected_python = workspace / "work" / "mac-setup-env" / "bin" / "python"
        expected_state = Path.home() / "Library" / "Application Support" / "GoFlySetup"
        if (
            project != expected_project
            or python != expected_python
            or developer != Path("/Applications/Xcode.app/Contents/Developer")
            or state != expected_state
        ):
            raise SetupBridgeError("configuration-invalid")
        if validator.name != "GoFlyTransferValidator" or validator.parent.name != "MacOS":
            raise SetupBridgeError("configuration-invalid")
        _reject_symlink_components(validator)
        return cls(workspace, python, developer, project, TARGET_BUNDLE_ID, TARGET_NAME, state, validator)

    def as_dict(self) -> dict[str, str]:
        return {
            "workspaceRoot": str(self.workspace_root),
            "pythonPath": str(self.python_path),
            "developerDirectory": str(self.developer_directory),
            "projectPath": str(self.project_path),
            "targetBundleID": self.target_bundle_id,
            "targetName": self.target_name,
            "stateRoot": str(self.state_root),
            "validatorPath": str(self.validator_path),
        }

    def validate_read_only_paths(self) -> None:
        """Validate fixed paths and the bundled validator without writing."""

        self._setup().validate_read_only_paths()
        validator = self.validator_path
        if (
            not validator.is_absolute()
            or validator.name != "GoFlyTransferValidator"
            or validator.parent.name != "MacOS"
        ):
            raise SetupBridgeError("configuration-invalid")
        _validate_validator_path_fd(validator)

    def ensure_state_root(self) -> Path:
        """Delegate state-root creation to M1 only at an explicit write boundary."""

        self.validate_read_only_paths()
        return self._setup().ensure_state_root()
