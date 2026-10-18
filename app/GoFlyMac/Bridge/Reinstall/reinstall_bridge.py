#!/usr/bin/env python3
"""One-request protocol-3 GoFlyMac reinstall bridge."""

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

try:
    from .reinstall_adapters import PinnedReinstallDeviceAdapter
    from .reinstall_config import ReinstallConfiguration
    from .reinstall_producer import ReinstallProducer
    from .reinstall_protocol import MAX_REQUEST_BYTES, ReinstallBridgeError, decode_request, error_response, encode_response
except ImportError:  # direct execution from packaged Reinstall directory
    from reinstall_adapters import PinnedReinstallDeviceAdapter
    from reinstall_config import ReinstallConfiguration
    from reinstall_producer import ReinstallProducer
    from reinstall_protocol import MAX_REQUEST_BYTES, ReinstallBridgeError, decode_request, error_response, encode_response


def establish_process_group() -> None:
    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise ReinstallBridgeError("environment-not-ready")


def _read_request(stream: Any) -> bytes:
    reader = getattr(stream, "buffer", stream)
    try:
        data = reader.read(MAX_REQUEST_BYTES + 1)
    except Exception:
        raise ReinstallBridgeError("invalid-request") from None
    if isinstance(data, str):
        data = data.encode("utf-8")
    if not isinstance(data, bytes) or len(data) > MAX_REQUEST_BYTES:
        raise ReinstallBridgeError("invalid-request")
    return data


def _raw_object(data: bytes) -> dict[str, Any] | None:
    try:
        value = json.loads(data.decode("utf-8"))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def _default_producer(config: ReinstallConfiguration) -> ReinstallProducer:
    return ReinstallProducer(config, device=PinnedReinstallDeviceAdapter(config))


def _error_payload(request: Any, config: ReinstallConfiguration | None) -> dict[str, Any] | None:
    if config is None:
        return None
    try:
        try:
            from .reinstall_journal import ReinstallJournalStore
            from .reinstall_producer import ReinstallProducer
        except ImportError:  # direct packaged execution
            from reinstall_journal import ReinstallJournalStore
            from reinstall_producer import ReinstallProducer
        journal = ReinstallJournalStore(config.state_root).read()
        if journal is None:
            return None
        # Constructing the payload is pure; no adapter is contacted and no
        # journal reconciliation is attempted on an error response.
        producer = object.__new__(ReinstallProducer)
        return producer._payload_from_journal(journal).as_dict()
    except Exception:
        return None


def run_stdio(
    config_path: str | Path,
    *,
    stdin: Any = None,
    producer_factory: Callable[[ReinstallConfiguration], ReinstallProducer] | None = None,
) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    try:
        data = _read_request(stream)
    except ReinstallBridgeError as error:
        return error_response(None, error.code)
    raw = _raw_object(data)
    try:
        request = decode_request(data)
    except ReinstallBridgeError as error:
        return error_response(raw, error.code)
    config: ReinstallConfiguration | None = None
    try:
        config = ReinstallConfiguration.load(config_path)
        config.validate_read_only_paths()
        producer = producer_factory(config) if producer_factory is not None else _default_producer(config)
        payload = producer.handle(request)
        return json.loads(encode_response(request, status="ok", payload=payload.as_dict()).decode("utf-8"))
    except ReinstallBridgeError as error:
        return error_response(request.as_dict(), error.code, _error_payload(request, config))
    except Exception:
        return error_response(request.as_dict(), "operation-failed", _error_payload(request, config))


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
    except ReinstallBridgeError as error:
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
