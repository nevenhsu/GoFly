#!/usr/bin/env python3
"""One-request protocol-4 local backup manager bridge."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import sys
from pathlib import Path
from typing import Any, Callable, Mapping

if __package__ in {None, ""}:
    _PACKAGE_DIR = str(Path(__file__).resolve().parent)
    if _PACKAGE_DIR not in sys.path:
        sys.path.insert(0, _PACKAGE_DIR)
    _BRIDGE_ROOT = str(Path(__file__).resolve().parents[1])
    if _BRIDGE_ROOT not in sys.path:
        sys.path.insert(0, _BRIDGE_ROOT)

try:
    from ..Setup.setup_config import SetupConfiguration
except ImportError:  # direct execution from the packaged Backup directory
    from Setup.setup_config import SetupConfiguration

try:
    from .catalog import BackupManager
    from .protocol import MAX_REQUEST_BYTES, BackupBridgeError, decode_request, encode_response, error_response
except ImportError:  # direct execution from the packaged Backup directory
    from Backup.catalog import BackupManager
    from Backup.protocol import MAX_REQUEST_BYTES, BackupBridgeError, decode_request, encode_response, error_response


def establish_process_group() -> None:
    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise BackupBridgeError("operation-failed")


def _read_request(stream: Any) -> bytes:
    reader = getattr(stream, "buffer", stream)
    try:
        data = reader.read(MAX_REQUEST_BYTES + 1)
    except Exception:
        raise BackupBridgeError("invalid-request") from None
    if isinstance(data, str):
        data = data.encode("utf-8")
    if not isinstance(data, bytes) or len(data) > MAX_REQUEST_BYTES:
        raise BackupBridgeError("invalid-request")
    return data


def _raw_object(data: bytes) -> dict[str, Any] | None:
    try:
        value = json.loads(data.decode("utf-8"))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def run_stdio(
    config_path: str | Path,
    *,
    stdin: Any = None,
    manager_factory: Callable[[SetupConfiguration], BackupManager] | None = None,
) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    try:
        data = _read_request(stream)
    except BackupBridgeError as error:
        return error_response(None, error.code)
    raw = _raw_object(data)
    try:
        request = decode_request(data)
    except BackupBridgeError as error:
        return error_response(raw, error.code)
    try:
        config = SetupConfiguration.load(config_path)
        manager = manager_factory(config) if manager_factory is not None else BackupManager(config.state_root)
        payload = manager.handle(request)
        return json.loads(encode_response(request, status="ok", payload=payload).decode("utf-8"))
    except BackupBridgeError as error:
        return error_response(request.as_dict(), error.code)
    except Exception as error:
        code = getattr(error, "code", None)
        if code not in {"configuration-invalid", "storage-unavailable", "busy", "backup-not-complete", "backup-changed", "operation-failed"}:
            code = "operation-failed"
        return error_response(request.as_dict(), code)


def emit(response: Mapping[str, Any], stream: Any = None) -> None:
    output = stream if stream is not None else sys.stdout
    try:
        encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        encoded = b'{"protocol":4,"requestID":null,"status":"error","code":"operation-failed"}'
    writer = getattr(output, "buffer", output)
    try:
        writer.write(encoded + b"\n")
        if hasattr(writer, "flush"):
            writer.flush()
    except TypeError:
        output.write(encoded.decode("utf-8") + "\n")


def main(argv: list[str] | None = None) -> int:
    try:
        establish_process_group()
    except BackupBridgeError as error:
        emit(error_response(None, error.code))
        return 1
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--config", required=True)
    try:
        arguments = parser.parse_args(argv)
    except SystemExit:
        return 2
    emit(run_stdio(arguments.config))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
