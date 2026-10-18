#!/usr/bin/env python3
"""The one-request protocol-2 GoFlyMac setup process."""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Callable

# ``python -I`` intentionally removes the script directory from sys.path.
# The bridge is a fixed packaged entry point, so restore only this trusted
# sibling directory before importing its modules; no config-selected module
# or arbitrary user path is ever added.
if __package__ in {None, ""}:
    _PACKAGE_DIR = str(Path(__file__).resolve().parent)
    if _PACKAGE_DIR not in sys.path:
        sys.path.insert(0, _PACKAGE_DIR)

try:
    from .setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
    from .setup_config import SetupConfiguration
    from .setup_journal import JournalStore
    from .setup_producer import SetupProducer
    from .setup_support import PinnedSupportAdapter
    from .setup_protocol import (
        MAX_REQUEST_BYTES,
        PROTOCOL,
        SetupBridgeError,
        decode_request,
        encode_response,
        error_response,
    )
except ImportError:  # direct execution from the packaged Setup directory
    from setup_adapters import PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, close_async_runtime
    from setup_config import SetupConfiguration
    from setup_journal import JournalStore
    from setup_producer import SetupProducer
    from setup_support import PinnedSupportAdapter
    from setup_protocol import (
        MAX_REQUEST_BYTES,
        PROTOCOL,
        SetupBridgeError,
        decode_request,
        encode_response,
        error_response,
    )


def establish_process_group() -> None:
    """Own a process group before loading a request or invoking adapters."""

    try:
        if os.getpgrp() != os.getpid():
            os.setsid()
    except OSError:
        with contextlib.suppress(OSError):
            os.setpgrp()
    if os.getpgrp() != os.getpid():
        raise SetupBridgeError("environment-not-ready")


def _read_request(stream: Any) -> bytes:
    reader = getattr(stream, "buffer", stream)
    try:
        data = reader.read(MAX_REQUEST_BYTES + 1)
    except Exception:
        raise SetupBridgeError("invalid-request") from None
    if isinstance(data, str):
        data = data.encode("utf-8")
    if not isinstance(data, bytes) or len(data) > MAX_REQUEST_BYTES:
        raise SetupBridgeError("invalid-request")
    return data


def _default_producer(config: SetupConfiguration) -> SetupProducer:
    # Dependency loading is lazy inside PinnedPymobiledeviceAdapter; status
    # remains available for a journal that exists even when pmd3 is absent.
    device = PinnedPymobiledeviceAdapter(state_root=config.state_root)
    return SetupProducer(
        config,
        device=device,
        process=PinnedXcodeProcessAdapter(config),
        support=PinnedSupportAdapter(device),
    )


def _decode_json_for_error(data: bytes) -> dict[str, Any] | None:
    try:
        value = json.loads(data.decode("utf-8"))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def _error_payload(request: Any, config: SetupConfiguration | None = None) -> dict[str, Any]:
    if config is not None:
        try:
            journal = JournalStore(config.state_root).read()
            if isinstance(journal, dict) and (
                getattr(request, "setup_id", None) is None or journal.get("setupID") == request.setup_id
            ) and (
                getattr(request, "device_id", None) is None or journal.get("deviceID") == request.device_id
            ):
                stages = journal.get("stages", {})
                current = "complete"
                outcome = "confirmed"
                for stage in ("artifact", "pairing", "install", "support", "handoff", "complete"):
                    state = stages.get(stage, {}).get("state")
                    if state in {"unknown", "inflight"}:
                        current, outcome = stage, "unknown"
                        break
                    if state != "confirmed":
                        current, outcome = stage, "inProgress"
                        break
                proof = journal.get("proof", {})
                if (
                    current == "complete"
                    and outcome == "confirmed"
                    and not (
                        all(proof.get(key) is True for key in (
                            "installationConfirmed", "pairingImported", "supportObserved"
                        ))
                        and isinstance(journal.get("receiptSHA256"), str)
                        and re.fullmatch(r"[0-9a-f]{64}", journal["receiptSHA256"]) is not None
                    )
                ):
                    outcome = "unknown"
                delivery_state = journal.get("delivery", {}).get("state")
                payload: dict[str, Any] = {
                    "stage": current,
                    "outcome": outcome,
                    "canResume": outcome != "confirmed" and delivery_state not in {"inflight", "unknown"},
                    "proof": {
                        "installationConfirmed": proof.get("installationConfirmed") is True,
                        "pairingImported": proof.get("pairingImported") is True,
                        "supportObserved": proof.get("supportObserved") is True,
                    },
                }
                artifact = journal.get("intent", {}).get("artifact")
                if isinstance(artifact, dict):
                    payload["app"] = {
                        "bundleID": artifact.get("bundleID"),
                        "build": artifact.get("build"),
                        "profileSHA256": artifact.get("profileSHA256"),
                        "executableSHA256": artifact.get("executableSHA256"),
                    }
                    payload["teamID"] = journal.get("intent", {}).get("teamID")
                    payload["expiresAt"] = artifact.get("expiresAt")
                receipt = journal.get("receiptSHA256")
                if isinstance(receipt, str) and re.fullmatch(r"[0-9a-f]{64}", receipt) is not None:
                    payload["receiptSHA256"] = receipt
                return payload
        except SetupBridgeError:
            pass
    action = getattr(request, "action", None)
    stage = action if action in {"preflight", "artifact", "pairing", "install", "support", "handoff"} else "preflight"
    return {
        "stage": stage,
        "outcome": "unknown",
        "canResume": stage != "preflight" and action not in {"status", "resume"},
        "proof": {
            "installationConfirmed": False,
            "pairingImported": False,
            "supportObserved": False,
        },
    }


def run_stdio(
    config_path: str | Path,
    *,
    stdin: Any = None,
    producer_factory: Callable[[SetupConfiguration], SetupProducer] | None = None,
) -> dict[str, Any]:
    stream = stdin if stdin is not None else sys.stdin
    try:
        data = _read_request(stream)
    except SetupBridgeError as error:
        return error_response(None, error.code)
    raw_request = _decode_json_for_error(data)
    try:
        request = decode_request(data)
    except SetupBridgeError as error:
        return error_response(raw_request, error.code)
    config: SetupConfiguration | None = None
    try:
        config = SetupConfiguration.load(config_path)
        # All CLI actions use the fixed, read-only project/interpreter/
        # developer paths.  State-root creation is reserved for apply inside
        # SetupProducer, so status and resume remain read-only here.
        config.validate_read_only_paths()
        producer = producer_factory(config) if producer_factory is not None else _default_producer(config)
        payload = producer.handle(request)
        encoded = encode_response(request, status="ok", payload=payload.as_dict())
        return json.loads(encoded.decode("utf-8"))
    except SetupBridgeError as error:
        return error_response(request.as_dict(), error.code, _error_payload(request, config))
    except Exception:
        return error_response(request.as_dict(), "operation-failed", _error_payload(request, config))
    finally:
        # The production adapters share one event loop for all async calls in
        # this request; close it only after every service/client has returned.
        close_async_runtime()


def emit(response: dict[str, Any], stream: Any = None) -> None:
    output = stream if stream is not None else sys.stdout
    encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) > 256 * 1024:
        encoded = json.dumps(error_response(None, "operation-failed"), separators=(",", ":")).encode("utf-8")
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
    except SetupBridgeError as error:
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
