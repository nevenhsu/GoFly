"""Strict setup bridge codec for the formal GoFly first-install producer."""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from typing import Any, Mapping

try:
    from ..wire import WireError, UUID_RE, TEAM_RE, parse_object, response as wire_response, encode as wire_encode
except ImportError:  # direct/top-level import from the Setup directory
    import sys as _sys
    from pathlib import Path as _Path
    _root = str(_Path(__file__).resolve().parents[1])
    if _root not in _sys.path:
        _sys.path.append(_root)
    from wire import WireError, UUID_RE, TEAM_RE, parse_object, response as wire_response, encode as wire_encode

SetupBridgeError = WireError


def _parse_object(data: bytes, *, limit: int = 32 * 1024) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > limit:
        raise SetupBridgeError("invalid-request")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, SetupBridgeError):
        raise SetupBridgeError("invalid-request") from None
    if not isinstance(value, dict):
        raise SetupBridgeError("invalid-request")
    return value


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SetupBridgeError("invalid-request")
        result[key] = value
    return result


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise SetupBridgeError("invalid-request")
    return value.lower()


MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
TARGET_BUNDLE_ID = "com.neven.gofly"
TARGET_NAME = "GoFly"
_ACTIONS = frozenset({"preflight", "apply", "status", "resume"})
_MODES = frozenset({"install", "renew"})
_STAGES = frozenset({"preflight", "artifact", "pairing", "install", "support", "handoff", "complete"})
_OUTCOMES = frozenset({"ready", "inProgress", "confirmed", "unknown", "failed"})


def normalized_device(value: Any) -> str:
    if not isinstance(value, str):
        raise SetupBridgeError("invalid-request")
    candidate = value.strip().lower()
    if re.fullmatch(r"(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})", candidate) is None:
        raise SetupBridgeError("invalid-request")
    return candidate


@dataclass(frozen=True)
class SetupOptions:
    team_id: str
    allow_provisioning_updates: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "teamID": self.team_id,
            "allowProvisioningUpdates": self.allow_provisioning_updates,
        }


@dataclass(frozen=True)
class SetupRequest:
    request_id: str
    action: str
    setup_id: str | None
    device_id: str | None
    mode: str | None
    options: SetupOptions | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "requestID": self.request_id,
            "action": self.action,
            "setupID": self.setup_id,
            "deviceID": self.device_id,
            "mode": self.mode,
        }
        if self.options is not None:
            value["options"] = self.options.as_dict()
        return value


def _decode_options(value: Any) -> SetupOptions:
    if not isinstance(value, dict):
        raise SetupBridgeError("invalid-request")
    expected = {"teamID", "allowProvisioningUpdates"}
    if set(value) != expected:
        raise SetupBridgeError("invalid-request")
    team = value.get("teamID")
    allow = value.get("allowProvisioningUpdates")
    if type(allow) is not bool:
        raise SetupBridgeError("invalid-request")
    if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
        raise SetupBridgeError("invalid-request")
    return SetupOptions(team, allow)


def decode_request(data: Any) -> SetupRequest:
    value = parse_object(data) if isinstance(data, bytes) else data
    if not isinstance(value, Mapping):
        raise SetupBridgeError("invalid-request")
    required = {"requestID", "action"}
    if set(value) - required - {"setupID", "deviceID", "mode", "options"}:
        raise SetupBridgeError("invalid-request")
    request_id = _uuid(value.get("requestID"))
    action = value.get("action")
    if action not in _ACTIONS:
        raise SetupBridgeError("invalid-request")
    if action == "status" and "setupID" not in value and "deviceID" not in value and "mode" not in value:
        return SetupRequest(request_id, action, None, None, None, None)
    if not {"setupID", "deviceID", "mode"}.issubset(value):
        raise SetupBridgeError("invalid-request")
    setup_id = _uuid(value.get("setupID"))
    device_id = normalized_device(value.get("deviceID"))
    mode = value.get("mode")
    if mode not in _MODES:
        raise SetupBridgeError("invalid-request")
    requires_options = action in {"preflight", "apply"}
    if requires_options != ("options" in value):
        raise SetupBridgeError("invalid-request")
    options = _decode_options(value["options"]) if requires_options else None
    return SetupRequest(request_id, action, setup_id, device_id, mode, options)


def _response_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise SetupBridgeError("operation-failed")
    # canResume is part of the frozen payload shape even for a confirmed
    # completion.  It describes whether the transaction can be continued and
    # is therefore false for a completed record; omitting it would force the
    # Mac decoder to infer authority from stage alone.
    required = {"stage", "outcome", "canResume", "proof"}
    if set(payload) - required - {"app", "teamID", "expiresAt", "receiptSHA256"}:
        raise SetupBridgeError("operation-failed")
    if payload.get("stage") not in _STAGES or payload.get("outcome") not in _OUTCOMES:
        raise SetupBridgeError("operation-failed")
    if type(payload.get("canResume")) is not bool:
        raise SetupBridgeError("operation-failed")
    proof = payload.get("proof")
    if not isinstance(proof, dict) or set(proof) != {
        "installationConfirmed",
        "pairingImported",
        "supportObserved",
    } or any(type(proof[key]) is not bool for key in proof):
        raise SetupBridgeError("operation-failed")
    if payload.get("stage") == "preflight" and any(payload["proof"].values()):
        raise SetupBridgeError("operation-failed")
    if payload.get("stage") == "complete" and payload.get("outcome") == "confirmed":
        if not payload["proof"]["installationConfirmed"]:
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("app"), dict):
            raise SetupBridgeError("operation-failed")
        if set(payload["app"]) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
            raise SetupBridgeError("operation-failed")
        if any(not isinstance(payload["app"].get(key), str) or not payload["app"].get(key) for key in payload["app"]):
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("teamID"), str) or TEAM_RE.fullmatch(payload["teamID"]) is None:
            raise SetupBridgeError("operation-failed")
        if payload.get("expiresAt") is not None and (
            not isinstance(payload["expiresAt"], str) or not payload["expiresAt"]
        ):
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("receiptSHA256"), str) or re.fullmatch(r"[0-9a-f]{64}", payload["receiptSHA256"]) is None:
            raise SetupBridgeError("operation-failed")
    app = payload.get("app")
    if app is not None:
        if not isinstance(app, dict) or set(app) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
            raise SetupBridgeError("operation-failed")
        if app.get("bundleID") != TARGET_BUNDLE_ID or not isinstance(app.get("build"), str) or not app.get("build"):
            raise SetupBridgeError("operation-failed")
        if any(re.fullmatch(r"[0-9a-f]{64}", app.get(key, "")) is None for key in ("profileSHA256", "executableSHA256")):
            raise SetupBridgeError("operation-failed")
    if payload.get("teamID") is not None and (not isinstance(payload["teamID"], str) or TEAM_RE.fullmatch(payload["teamID"]) is None):
        raise SetupBridgeError("operation-failed")
    if payload.get("expiresAt") is not None and (not isinstance(payload["expiresAt"], str) or not payload["expiresAt"]):
        raise SetupBridgeError("operation-failed")
    if payload.get("receiptSHA256") is not None and (
        not isinstance(payload["receiptSHA256"], str)
        or re.fullmatch(r"[0-9a-f]{64}", payload["receiptSHA256"]) is None
    ):
        raise SetupBridgeError("operation-failed")
    return payload


def encode_response(
    request: SetupRequest | Mapping[str, Any],
    *,
    status: str,
    payload: Mapping[str, Any] | None = None,
    code: str | None = None,
) -> bytes:
    request_value = request.as_dict() if isinstance(request, SetupRequest) else dict(request)
    body = _response_payload(dict(payload) if payload is not None else _default_error_payload()) if status == "error" else _response_payload(dict(payload or {}))
    return wire_encode(wire_response(request_value, status=status, payload=body, code=code))


def error_response(
    request: Mapping[str, Any] | None,
    code: str,
    payload: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    body = _response_payload(dict(payload) if payload is not None else _default_error_payload())
    return wire_response(request, status="error", payload=body, code=code)


def _default_error_payload() -> dict[str, Any]:
    return {
        "stage": "preflight",
        "outcome": "unknown",
        "canResume": False,
        "proof": {
            "installationConfirmed": False,
            "pairingImported": False,
            "supportObserved": False,
        },
    }
