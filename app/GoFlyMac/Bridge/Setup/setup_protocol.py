"""Strict protocol-2 codec for the formal GoFly first-install producer."""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from typing import Any, Mapping

PROTOCOL = 2
MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
TARGET_BUNDLE_ID = "com.neven.gofly"
TARGET_NAME = "GoFly"
UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\Z"
)
UDID_RE = re.compile(r"(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{16}|[0-9a-fA-F]{40})\Z")
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
SAFE_ERROR_CODES = frozenset(
    {
        "invalid-request",
        "protocol-mismatch",
        "configuration-invalid",
        "dependency-mismatch",
        "runtime-api-mismatch",
        "environment-not-ready",
        "device-disconnected",
        "trust-required",
        "developer-mode-required",
        "unsupported-os",
        "identity-mismatch",
        "app-already-installed", "app-running",
        "signing-required",
        "signature-invalid",
        "artifact-mismatch",
        "support-unavailable",
        "pairing-unknown",
        "pairing-rejected",
        "handoff-unknown",
        "commit-unknown",
        "transaction-unknown",
        "transaction-conflict",
        "busy",
        "cancelled",
        "timeout",
        "storage-unavailable",
        "operation-failed",
    }
)
_ACTIONS = frozenset({"preflight", "apply", "status", "resume"})
_SOURCES = frozenset({"signedApp", "project"})
_STAGES = frozenset({"preflight", "artifact", "pairing", "install", "support", "handoff", "complete"})
_OUTCOMES = frozenset({"ready", "inProgress", "confirmed", "unknown", "failed"})


class SetupBridgeError(Exception):
    """A fixed safe error code suitable for the protocol boundary."""

    def __init__(self, code: str):
        self.code = code if code in SAFE_ERROR_CODES else "operation-failed"
        super().__init__(self.code)


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SetupBridgeError("invalid-request")
        result[key] = value
    return result


def _parse_object(data: bytes, *, limit: int) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > limit:
        raise SetupBridgeError("invalid-request")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_object_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, SetupBridgeError):
        raise SetupBridgeError("invalid-request") from None
    if not isinstance(value, dict):
        raise SetupBridgeError("invalid-request")
    return value


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise SetupBridgeError("invalid-request")
    return value.lower()


def normalized_device(value: Any) -> str:
    if not isinstance(value, str):
        raise SetupBridgeError("invalid-request")
    candidate = value.strip().lower()
    if UDID_RE.fullmatch(candidate) is None:
        raise SetupBridgeError("invalid-request")
    return candidate


@dataclass(frozen=True)
class SetupOptions:
    source: str
    artifact_path: str | None
    team_id: str
    allow_provisioning_updates: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "artifactPath": self.artifact_path,
            "teamID": self.team_id,
            "allowProvisioningUpdates": self.allow_provisioning_updates,
        }


@dataclass(frozen=True)
class SetupRequest:
    request_id: str
    action: str
    setup_id: str
    device_id: str
    options: SetupOptions | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "protocol": PROTOCOL,
            "requestID": self.request_id,
            "operation": "setup",
            "action": self.action,
            "setupID": self.setup_id,
            "deviceID": self.device_id,
        }
        if self.options is not None:
            value["options"] = self.options.as_dict()
        return value


def _decode_options(value: Any) -> SetupOptions:
    if not isinstance(value, dict):
        raise SetupBridgeError("invalid-request")
    expected = {"source", "artifactPath", "teamID", "allowProvisioningUpdates"}
    if set(value) != expected:
        raise SetupBridgeError("invalid-request")
    source = value.get("source")
    artifact = value.get("artifactPath")
    team = value.get("teamID")
    allow = value.get("allowProvisioningUpdates")
    if source not in _SOURCES or type(allow) is not bool:
        raise SetupBridgeError("invalid-request")
    if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
        raise SetupBridgeError("invalid-request")
    if source == "project":
        if artifact is not None:
            raise SetupBridgeError("invalid-request")
    else:
        if not isinstance(artifact, str) or not artifact.startswith("/") or not artifact.endswith(".app"):
            raise SetupBridgeError("invalid-request")
        if allow is not False:
            raise SetupBridgeError("invalid-request")
    return SetupOptions(source, artifact, team, allow)


def decode_request(data: bytes) -> SetupRequest:
    value = _parse_object(data, limit=MAX_REQUEST_BYTES)
    if "protocol" not in value:
        raise SetupBridgeError("invalid-request")
    if value.get("protocol") != PROTOCOL or type(value.get("protocol")) is not int:
        raise SetupBridgeError("protocol-mismatch")
    required = {"protocol", "requestID", "operation", "action", "setupID", "deviceID"}
    if set(value) - required - {"options"}:
        raise SetupBridgeError("invalid-request")
    if value.get("operation") != "setup" or not isinstance(value.get("operation"), str):
        raise SetupBridgeError("invalid-request")
    request_id = _uuid(value.get("requestID"))
    setup_id = _uuid(value.get("setupID"))
    device_id = normalized_device(value.get("deviceID"))
    action = value.get("action")
    if action not in _ACTIONS:
        raise SetupBridgeError("invalid-request")
    requires_options = action in {"preflight", "apply"}
    if requires_options != ("options" in value):
        raise SetupBridgeError("invalid-request")
    options = _decode_options(value["options"]) if requires_options else None
    return SetupRequest(request_id, action, setup_id, device_id, options)


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
        if not all(payload["proof"].values()):
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("app"), dict):
            raise SetupBridgeError("operation-failed")
        if set(payload["app"]) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
            raise SetupBridgeError("operation-failed")
        if any(not isinstance(payload["app"].get(key), str) or not payload["app"].get(key) for key in payload["app"]):
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("teamID"), str) or TEAM_RE.fullmatch(payload["teamID"]) is None:
            raise SetupBridgeError("operation-failed")
        if not isinstance(payload.get("expiresAt"), str) or not payload["expiresAt"]:
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
    if isinstance(request, SetupRequest):
        request_value = request.as_dict()
    elif isinstance(request, Mapping):
        request_value = dict(request)
    else:
        raise SetupBridgeError("operation-failed")
    request_id = request_value.get("requestID")
    setup_id = request_value.get("setupID")
    device_id = request_value.get("deviceID")
    if not isinstance(request_id, str) or not isinstance(setup_id, str) or not isinstance(device_id, str):
        raise SetupBridgeError("operation-failed")
    if status not in {"ok", "error"}:
        raise SetupBridgeError("operation-failed")
    response: dict[str, Any] = {
        "protocol": PROTOCOL,
        "requestID": request_id,
        "operation": "setup",
        "action": request_value.get("action"),
        "setupID": setup_id,
        "deviceID": device_id,
        "status": status,
    }
    if status == "error":
        if code not in SAFE_ERROR_CODES:
            code = "operation-failed"
        response["code"] = code
        response["payload"] = _response_payload(dict(payload) if payload is not None else _default_error_payload())
    else:
        response["payload"] = _response_payload(dict(payload or {}))
    encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) > MAX_RESPONSE_BYTES:
        raise SetupBridgeError("operation-failed")
    return encoded


def error_response(
    request: Mapping[str, Any] | None,
    code: str,
    payload: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """Build a response dict for callers that need to emit structured JSON."""

    value = request if isinstance(request, Mapping) else {}
    result: dict[str, Any] = {
        "protocol": PROTOCOL,
        "requestID": value.get("requestID") if isinstance(value.get("requestID"), str) else None,
        "operation": "setup",
        "action": value.get("action") if isinstance(value.get("action"), str) else None,
        "setupID": value.get("setupID") if isinstance(value.get("setupID"), str) else None,
        "deviceID": value.get("deviceID") if isinstance(value.get("deviceID"), str) else None,
        "status": "error",
        "code": code if code in SAFE_ERROR_CODES else "operation-failed",
    }
    result["payload"] = _response_payload(dict(payload) if payload is not None else _default_error_payload())
    return result


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
