#!/usr/bin/env python3
"""One-request protocol-5 GoFlyMac management bridge."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import sys
from pathlib import Path
from typing import Any, Callable, Mapping

if __package__ in {None, ""}:
    _BRIDGE_ROOT = str(Path(__file__).resolve().parents[1])
    if _BRIDGE_ROOT not in sys.path:
        sys.path.insert(0, _BRIDGE_ROOT)

try:
    from ..Reinstall.reinstall_config import ReinstallConfiguration
    from .management_producer import ManagementProducer
    from .management_protocol import (
        MAX_REQUEST_BYTES,
        SAFE_ERROR_CODES,
        ManagementBridgeError,
        decode_request,
        error_response,
        encode_response,
    )
except ImportError:  # direct execution from packaged Bridge root
    from Reinstall.reinstall_config import ReinstallConfiguration
    from Management.management_producer import ManagementProducer
    from Management.management_protocol import MAX_REQUEST_BYTES, SAFE_ERROR_CODES, ManagementBridgeError, decode_request, error_response, encode_response


def establish_process_group() -> None:
    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise ManagementBridgeError("environment-not-ready")


def _read_request(stream: Any) -> bytes:
    reader = getattr(stream, "buffer", stream)
    try:
        data = reader.read(MAX_REQUEST_BYTES + 1)
    except Exception:
        raise ManagementBridgeError("invalid-request") from None
    if isinstance(data, str):
        data = data.encode("utf-8")
    if not isinstance(data, bytes) or not data or len(data) > MAX_REQUEST_BYTES:
        raise ManagementBridgeError("invalid-request")
    return data


def _raw_object(data: bytes) -> dict[str, Any] | None:
    try:
        value = json.loads(data.decode("utf-8"))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def _default_producer(config: ReinstallConfiguration) -> ManagementProducer:
    return ManagementProducer(config)


def _error_payload(request: Any, config: ReinstallConfiguration | None) -> Mapping[str, Any] | None:
    if config is None:
        return None
    try:
        from .management_journal import ManagementJournal
        from .management_producer import ManagementProducer
        journal = ManagementJournal(config.state_root).read()
        if journal is None:
            return None
        producer = object.__new__(ManagementProducer)
        producer.config = config
        producer.store = ManagementJournal(config.state_root)
        return producer._payload(journal, request).as_dict() if request is not None else None
    except Exception:
        return None


def run_stdio(
    config_path: str | Path,
    *,
    stdin: Any = None,
    producer_factory: Callable[[ReinstallConfiguration], ManagementProducer] | None = None,
) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    try:
        data = _read_request(stream)
    except ManagementBridgeError as error:
        return error_response(None, error.code)
    raw = _raw_object(data)
    try:
        request = decode_request(data)
    except ManagementBridgeError as error:
        return error_response(raw, error.code)
    config: ReinstallConfiguration | None = None
    try:
        config = ReinstallConfiguration.load(config_path)
        config.validate_read_only_paths()
        producer = producer_factory(config) if producer_factory is not None else _default_producer(config)
        payload = producer.handle(request)
        return json.loads(encode_response(request, payload).decode("utf-8"))
    except ManagementBridgeError as error:
        return error_response(request, error.code)
    except Exception as error:
        code = getattr(error, "code", None)
        if not isinstance(code, str) or code not in SAFE_ERROR_CODES:
            code = "operation-failed"
        return error_response(request, code)


def emit(response: Mapping[str, Any], stream: Any = None) -> None:
    output = stream if stream is not None else sys.stdout
    encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
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
    except ManagementBridgeError as error:
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
