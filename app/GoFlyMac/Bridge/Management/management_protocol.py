"""Strict, pure protocol-5 codec for the M3 management boundary.

This module deliberately has no filesystem, device, Core, or transport imports.  It
only checks the bounded JSON values exchanged by the eventual management bridge.
"""

from __future__ import annotations

import datetime as _datetime
import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Mapping

PROTOCOL = 5
MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
MAX_ARTIFACT_PATH_BYTES = 4_096
TARGET_BUNDLE_ID = "com.neven.gofly"

UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
UDID_RE = re.compile(r"(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})\Z")
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
EXPIRY_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z\Z")

_COMMON_ERROR_CODES = {
    "invalid-request", "protocol-mismatch", "configuration-invalid",
    "dependency-mismatch", "runtime-api-mismatch", "environment-not-ready",
    "device-disconnected", "trust-required", "developer-mode-required",
    "unsupported-os", "identity-mismatch", "app-already-installed",
    "app-running", "signing-required", "signature-invalid", "artifact-mismatch",
    "support-unavailable", "pairing-unknown", "pairing-rejected",
    "handoff-unknown", "commit-unknown", "transaction-unknown",
    "transaction-conflict", "busy", "cancelled", "timeout",
    "storage-unavailable", "operation-failed", "update-required",
    "source-busy", "backup-invalid", "restore-unknown", "export-conflict",
    "removal-unknown", "operation-abandoned",
}
SAFE_ERROR_CODES = frozenset(_COMMON_ERROR_CODES | {
    "identity-unverified", "update-unknown", "adoption-unknown",
    "operation-released", "revision-conflict", "receipt-capacity",
})

_ACTIONS = frozenset({"preflight", "apply", "query", "resume", "release"})
_KINDS = frozenset({"renew", "repair"})
_TRANSPORTS = frozenset({"USB", "Network"})
_SOURCES = frozenset({"project", "signedApp"})
_STAGES = frozenset({
    "preflight", "artifact", "source", "seal", "update", "pairing", "support",
    "adoption", "complete", "release",
})
_OUTCOMES = frozenset({"ready", "inProgress", "confirmed", "unknown", "failed"})
_PROOF_KEYS = (
    "sourceBound", "sourceQuiescent", "mutationSealed", "updateConfirmed",
    "pairingImported", "supportObserved", "adoptionCommitted",
)
_RECEIPT_KEYS = {
    "version", "managementID", "nonce", "requestSHA256", "sourceSetupID",
    "targetSetupID", "sourceApp", "targetApp", "expectedDeviceUDID", "teamID",
    "sourceActivationSHA256", "sourceRestoreRootSHA256", "targetActivationSHA256",
    "receiptSHA256",
}
_APP_KEYS = {"bundleID", "build", "profileSHA256", "executableSHA256"}
_REQUEST_COMMON_KEYS = {
    "protocol", "operation", "requestID", "managementID", "deviceID", "selectionID",
    "kind", "transport", "connectionRevision", "action",
}


class ManagementBridgeError(Exception):
    """A closed safe error code suitable for the protocol boundary."""

    def __init__(self, code: str):
        self.code = code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed"
        super().__init__(self.code)


def _invalid() -> None:
    raise ManagementBridgeError("invalid-request")


def _failed() -> None:
    raise ManagementBridgeError("operation-failed")


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            _invalid()
        result[key] = value
    return result


def _reject_number(_value: str) -> Any:
    raise ValueError("floating numeric value")


def _reject_constant(_value: str) -> Any:
    raise ValueError("non-finite numeric value")


def _check_depth(value: Any, depth: int = 0) -> None:
    if depth > 32:
        _invalid()
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                _invalid()
            _check_depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _check_depth(child, depth + 1)


def _parse_object(data: bytes, *, limit: int) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > limit:
        _invalid()
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_float=_reject_number,
            parse_constant=_reject_constant,
        )
        _check_depth(value)
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError, ManagementBridgeError):
        raise ManagementBridgeError("invalid-request") from None
    if not isinstance(value, dict):
        _invalid()
    return value


def _uuid(value: Any, *, code: str = "invalid-request") -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise ManagementBridgeError(code)
    return value


def _device(value: Any, *, code: str = "invalid-request") -> str:
    if not isinstance(value, str) or value != value.strip() or value != value.lower() or UDID_RE.fullmatch(value) is None:
        raise ManagementBridgeError(code)
    return value


def _integer(value: Any, *, minimum: int, maximum: int, code: str) -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        raise ManagementBridgeError(code)
    return value


def _text(value: Any, *, nonempty: bool = True, maximum_bytes: int | None = None, code: str) -> str:
    if not isinstance(value, str) or (nonempty and not value):
        raise ManagementBridgeError(code)
    if any(unicodedata.category(char) in {"Cc", "Cf", "Cs"} for char in value):
        raise ManagementBridgeError(code)
    try:
        encoded_length = len(value.encode("utf-8"))
    except UnicodeError:
        raise ManagementBridgeError(code) from None
    if maximum_bytes is not None and encoded_length > maximum_bytes:
        raise ManagementBridgeError(code)
    return value


def _team(value: Any, *, code: str) -> str:
    if not isinstance(value, str) or TEAM_RE.fullmatch(value) is None:
        raise ManagementBridgeError(code)
    return value


def _hash(value: Any, *, nullable: bool = False, code: str) -> str | None:
    if nullable and value is None:
        return None
    if not isinstance(value, str) or HEX64_RE.fullmatch(value) is None:
        raise ManagementBridgeError(code)
    return value


def _expiry(value: Any, *, code: str) -> str:
    if not isinstance(value, str) or len(value) > 40 or EXPIRY_RE.fullmatch(value) is None:
        raise ManagementBridgeError(code)
    try:
        date_part, time_part = value[:-1].split("T", 1)
        _datetime.datetime.fromisoformat(f"{date_part}T{time_part}+00:00")
    except ValueError:
        raise ManagementBridgeError(code) from None
    return value


def _path(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not value.startswith("/"):
        _invalid()
    try:
        if len(value.encode("utf-8")) > MAX_ARTIFACT_PATH_BYTES:
            _invalid()
    except UnicodeError:
        _invalid()
    if any(unicodedata.category(char) in {"Cc", "Cf", "Cs"} for char in value):
        _invalid()
    if any(part in {"..", ""} for part in value.split("/")[1:]):
        _invalid()
    return value


def _validate_app(value: Any, *, code: str) -> dict[str, Any]:
    if not isinstance(value, Mapping) or set(value) != _APP_KEYS:
        raise ManagementBridgeError(code)
    if value.get("bundleID") != TARGET_BUNDLE_ID:
        raise ManagementBridgeError(code)
    build = _text(value.get("build"), maximum_bytes=128, code=code)
    return {
        "bundleID": TARGET_BUNDLE_ID,
        "build": build,
        "profileSHA256": _hash(value.get("profileSHA256"), code=code),
        "executableSHA256": _hash(value.get("executableSHA256"), code=code),
    }


@dataclass(frozen=True)
class ManagementOptions:
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
class _ResumeSelection:
    selection_id: str
    transport: str

    def as_dict(self) -> dict[str, Any]:
        return {"selectionID": self.selection_id, "transport": self.transport}


@dataclass(frozen=True)
class ManagementRequest:
    request_id: str
    management_id: str
    device_id: str
    selection_id: str
    kind: str
    transport: str
    connection_revision: int
    action: str
    options: ManagementOptions | None = None
    resume_selection: _ResumeSelection | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "protocol": PROTOCOL,
            "operation": "management",
            "requestID": self.request_id,
            "managementID": self.management_id,
            "deviceID": self.device_id,
            "selectionID": self.selection_id,
            "kind": self.kind,
            "transport": self.transport,
            "connectionRevision": self.connection_revision,
            "action": self.action,
        }
        if self.action in {"preflight", "apply"}:
            value["options"] = self.options.as_dict() if self.options is not None else None
        elif self.action == "resume":
            value["resumeSelection"] = self.resume_selection.as_dict() if self.resume_selection is not None else None
        return value


def _decode_options(value: Any, *, kind: str) -> ManagementOptions | None:
    if kind == "repair":
        if value is not None:
            _invalid()
        return None
    if not isinstance(value, Mapping) or set(value) != {"source", "artifactPath", "teamID", "allowProvisioningUpdates"}:
        _invalid()
    source = value.get("source")
    if not isinstance(source, str) or source not in _SOURCES:
        _invalid()
    artifact = _path(value.get("artifactPath"))
    team = _team(value.get("teamID"), code="invalid-request")
    allow = value.get("allowProvisioningUpdates")
    if type(allow) is not bool:
        _invalid()
    if source == "project":
        if artifact is not None:
            _invalid()
    elif artifact is None or not artifact.endswith(".app") or allow is not False:
        _invalid()
    return ManagementOptions(source, artifact, team, allow)


def decode_request(data: bytes) -> ManagementRequest:
    value = _parse_object(data, limit=MAX_REQUEST_BYTES)
    if value.get("protocol") != PROTOCOL or type(value.get("protocol")) is not int:
        raise ManagementBridgeError("protocol-mismatch")
    if value.get("operation") != "management" or type(value.get("operation")) is not str:
        _invalid()
    unknown = set(value) - _REQUEST_COMMON_KEYS - {"options", "resumeSelection"}
    if unknown:
        _invalid()
    for key in _REQUEST_COMMON_KEYS:
        if key not in value:
            _invalid()
    request_id = _uuid(value.get("requestID"))
    management_id = _uuid(value.get("managementID"))
    selection_id = _uuid(value.get("selectionID"))
    raw_device = value.get("deviceID")
    device_id = _device(raw_device.strip().lower() if isinstance(raw_device, str) else raw_device)
    kind = value.get("kind")
    transport = value.get("transport")
    action = value.get("action")
    if not isinstance(kind, str) or kind not in _KINDS:
        _invalid()
    if not isinstance(transport, str) or transport not in _TRANSPORTS:
        _invalid()
    revision = _integer(value.get("connectionRevision"), minimum=0, maximum=31, code="invalid-request")
    if not isinstance(action, str) or action not in _ACTIONS:
        _invalid()
    has_options = "options" in value
    has_resume = "resumeSelection" in value
    if action in {"preflight", "apply"}:
        if has_resume or not has_options:
            _invalid()
        if revision != 0:
            _invalid()
        options = _decode_options(value.get("options"), kind=kind)
        resume = None
    elif action == "resume":
        if has_options or not has_resume:
            _invalid()
        selection = value.get("resumeSelection")
        if selection is None:
            resume = None
        else:
            if not isinstance(selection, Mapping) or set(selection) != {"selectionID", "transport"}:
                _invalid()
            resume_transport = selection.get("transport")
            if not isinstance(resume_transport, str) or resume_transport not in _TRANSPORTS:
                _invalid()
            resume = _ResumeSelection(_uuid(selection.get("selectionID")), resume_transport)
        options = None
    else:
        if has_options or has_resume:
            _invalid()
        options = None
        resume = None
    return ManagementRequest(
        request_id, management_id, device_id, selection_id, kind, transport,
        revision, action, options, resume,
    )


def _json_bytes(value: Any, *, limit: int | None = None) -> bytes:
    try:
        encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise ManagementBridgeError("operation-failed") from None
    if limit is not None and len(encoded) > limit:
        raise ManagementBridgeError("operation-failed")
    return encoded


def encode_request(request: ManagementRequest) -> bytes:
    if not isinstance(request, ManagementRequest):
        raise ManagementBridgeError("operation-failed")
    # Re-parse the explicit mapping so callers cannot smuggle an invalid frozen object.
    try:
        canonical = decode_request(_json_bytes(request.as_dict(), limit=MAX_REQUEST_BYTES))
        if canonical != request:
            raise ManagementBridgeError("operation-failed")
    except ManagementBridgeError as exc:
        raise ManagementBridgeError("operation-failed") from exc
    return _json_bytes(canonical.as_dict(), limit=MAX_REQUEST_BYTES)


def _canonical_request(request: ManagementRequest) -> ManagementRequest:
    try:
        canonical = decode_request(_json_bytes(request.as_dict(), limit=MAX_REQUEST_BYTES))
        if canonical != request:
            raise ManagementBridgeError("operation-failed")
        return canonical
    except ManagementBridgeError:
        raise ManagementBridgeError("operation-failed") from None


def _validate_receipt(receipt: Any, request: ManagementRequest, app: Mapping[str, Any], team: str) -> dict[str, Any]:
    if not isinstance(receipt, Mapping) or set(receipt) != _RECEIPT_KEYS:
        _failed()
    if receipt.get("version") != 1 or type(receipt.get("version")) is not int:
        _failed()
    management_id = _uuid(receipt.get("managementID"), code="operation-failed")
    if management_id != request.management_id:
        _failed()
    _uuid(receipt.get("nonce"), code="operation-failed")
    _hash(receipt.get("requestSHA256"), code="operation-failed")
    source_setup = _uuid(receipt.get("sourceSetupID"), code="operation-failed")
    target_setup = _uuid(receipt.get("targetSetupID"), code="operation-failed")
    if source_setup == target_setup:
        _failed()
    source_app = _validate_app(receipt.get("sourceApp"), code="operation-failed")
    target_app = _validate_app(receipt.get("targetApp"), code="operation-failed")
    if request.kind == "repair" and target_app != source_app:
        _failed()
    if _device(receipt.get("expectedDeviceUDID"), code="operation-failed") != request.device_id:
        _failed()
    if _team(receipt.get("teamID"), code="operation-failed") != team:
        _failed()
    for key in ("sourceActivationSHA256", "targetActivationSHA256"):
        _hash(receipt.get(key), code="operation-failed")
    _hash(receipt.get("sourceRestoreRootSHA256"), nullable=True, code="operation-failed")
    receipt_hash = _hash(receipt.get("receiptSHA256"), code="operation-failed")
    canonical = dict(receipt)
    canonical.pop("receiptSHA256")
    expected_hash = hashlib.sha256(_json_bytes(canonical)).hexdigest()
    if receipt_hash != expected_hash:
        _failed()
    return {
        "version": 1,
        "managementID": management_id,
        "nonce": receipt["nonce"],
        "requestSHA256": receipt["requestSHA256"],
        "sourceSetupID": source_setup,
        "targetSetupID": target_setup,
        "sourceApp": source_app,
        "targetApp": target_app,
        "expectedDeviceUDID": request.device_id,
        "teamID": team,
        "sourceActivationSHA256": receipt["sourceActivationSHA256"],
        "sourceRestoreRootSHA256": receipt["sourceRestoreRootSHA256"],
        "targetActivationSHA256": receipt["targetActivationSHA256"],
        "receiptSHA256": receipt_hash,
    }


def _validate_payload(payload: Any, request: ManagementRequest) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        _failed()
    required = {"stage", "outcome", "canResume", "canRelease", "sourceAdmission", "connectionRevision", "currentTransport", "proof", "app", "teamID", "expiresAt", "adoptionReceipt"}
    if set(payload) != required:
        _failed()
    stage = payload.get("stage")
    outcome = payload.get("outcome")
    if not isinstance(stage, str) or stage not in _STAGES or not isinstance(outcome, str) or outcome not in _OUTCOMES:
        _failed()
    if type(payload.get("canResume")) is not bool or type(payload.get("canRelease")) is not bool:
        _failed()
    admission = payload.get("sourceAdmission")
    if admission is not None and (not isinstance(admission, str) or admission not in {"live", "cold"}):
        _failed()
    revision = _integer(payload.get("connectionRevision"), minimum=request.connection_revision, maximum=31, code="operation-failed")
    transport = payload.get("currentTransport")
    if not isinstance(transport, str) or transport not in _TRANSPORTS:
        _failed()
    if revision == 0 and transport != request.transport:
        _failed()
    proof = payload.get("proof")
    if not isinstance(proof, Mapping) or set(proof) != set(_PROOF_KEYS) or any(type(proof[key]) is not bool for key in proof):
        _failed()
    app = payload.get("app")
    canonical_app = None if app is None else _validate_app(app, code="operation-failed")
    team_value = payload.get("teamID")
    canonical_team = None if team_value is None else _team(team_value, code="operation-failed")
    expiry_value = payload.get("expiresAt")
    canonical_expiry = None if expiry_value is None else _expiry(expiry_value, code="operation-failed")
    receipt_value = payload.get("adoptionReceipt")

    if (canonical_team is None) != (canonical_expiry is None):
        _failed()
    if receipt_value is not None:
        if canonical_app is None or canonical_team is None:
            _failed()
        canonical_receipt = _validate_receipt(receipt_value, request, canonical_app, canonical_team)
        if canonical_receipt["targetApp"] != canonical_app:
            _failed()
    else:
        canonical_receipt = None
    if proof["adoptionCommitted"] and (canonical_receipt is None or canonical_app is None or canonical_team is None):
        _failed()

    if payload["canRelease"]:
        if (
            stage not in {"artifact", "source"}
            or outcome not in {"inProgress", "failed"}
            or proof["mutationSealed"]
            or proof["updateConfirmed"]
            or proof["pairingImported"]
            or proof["adoptionCommitted"]
            or canonical_receipt is not None
        ):
            _failed()
    if stage in {"complete", "release"} or outcome in {"ready", "unknown"}:
        if payload["canRelease"]:
            _failed()
    if stage == "preflight" and outcome == "ready":
        if any(proof.values()) or canonical_receipt is not None or canonical_app is not None or canonical_team is not None or payload["canResume"] or payload["canRelease"]:
            _failed()
    if request.action == "preflight":
        if stage != "preflight" or any(proof.values()) or canonical_app is not None or canonical_team is not None or canonical_receipt is not None or payload["canResume"] or payload["canRelease"]:
            _failed()
    if stage == "complete" and outcome == "confirmed":
        if (
            not all(proof[key] for key in ("sourceBound", "pairingImported", "supportObserved", "adoptionCommitted"))
            or admission is None
            or (admission == "live" and (not proof["sourceQuiescent"] or not proof["mutationSealed"]))
            or (admission == "cold" and (proof["sourceQuiescent"] or proof["mutationSealed"]))
            or request.kind == "renew" and not proof["updateConfirmed"]
            or request.kind == "repair" and proof["updateConfirmed"]
            or canonical_app is None or canonical_team is None or canonical_expiry is None or canonical_receipt is None
            or payload["canResume"] or payload["canRelease"]
        ):
            _failed()
    if stage == "release" and outcome == "confirmed":
        if payload["canResume"] or payload["canRelease"] or proof["adoptionCommitted"] or proof["updateConfirmed"] or canonical_receipt is not None:
            _failed()
    if stage == "complete" and outcome == "unknown":
        _failed()
    if outcome == "ready" and stage != "preflight":
        _failed()
    return {
        "stage": stage,
        "outcome": outcome,
        "canResume": payload["canResume"],
        "canRelease": payload["canRelease"],
        "sourceAdmission": admission,
        "connectionRevision": revision,
        "currentTransport": transport,
        "proof": {key: proof[key] for key in _PROOF_KEYS},
        "app": canonical_app,
        "teamID": canonical_team,
        "expiresAt": canonical_expiry,
        "adoptionReceipt": canonical_receipt,
    }


def _response_identity(request: ManagementRequest) -> dict[str, Any]:
    return {
        "protocol": PROTOCOL,
        "operation": "management",
        "requestID": request.request_id,
        "managementID": request.management_id,
        "deviceID": request.device_id,
        "selectionID": request.selection_id,
        "kind": request.kind,
        "transport": request.transport,
        "action": request.action,
    }


def encode_response(request: ManagementRequest, payload: Mapping[str, Any]) -> bytes:
    if not isinstance(request, ManagementRequest):
        raise ManagementBridgeError("operation-failed")
    request = _canonical_request(request)
    value = _validate_payload(payload, request)
    response = _response_identity(request)
    response.update({"status": "ok", "payload": value})
    return _json_bytes(response, limit=MAX_RESPONSE_BYTES)


def _safe_uuid(value: Any) -> str | None:
    return value if isinstance(value, str) and UUID_RE.fullmatch(value) is not None else None


def _safe_device(value: Any) -> str | None:
    return value if isinstance(value, str) and UDID_RE.fullmatch(value) is not None and value == value.lower() else None


def error_response(request: ManagementRequest | Mapping[str, Any] | None, code: str) -> dict[str, Any]:
    if isinstance(request, ManagementRequest):
        # Dataclasses are values, not proof that decode_request was called.
        # Sanitize only the identity fields needed by an error response.
        raw = {
            "requestID": request.request_id, "managementID": request.management_id,
            "deviceID": request.device_id, "selectionID": request.selection_id,
            "kind": request.kind, "transport": request.transport, "action": request.action,
        }
    else:
        raw = request if isinstance(request, Mapping) else {}
    action_value = raw.get("action")
    action = action_value if isinstance(action_value, str) and action_value in _ACTIONS else None
    kind_value = raw.get("kind")
    kind = kind_value if isinstance(kind_value, str) and kind_value in _KINDS else None
    transport_value = raw.get("transport")
    transport = transport_value if isinstance(transport_value, str) and transport_value in _TRANSPORTS else None
    response = {
        "protocol": PROTOCOL,
        "operation": "management",
        "requestID": _safe_uuid(raw.get("requestID")),
        "managementID": _safe_uuid(raw.get("managementID")),
        "deviceID": _safe_device(raw.get("deviceID")),
        "selectionID": _safe_uuid(raw.get("selectionID")),
        "kind": kind,
        "transport": transport,
        "action": action,
    }
    response.update({
        "status": "error",
        "code": code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed",
    })
    return response


__all__ = [
    "MAX_REQUEST_BYTES", "MAX_RESPONSE_BYTES", "ManagementBridgeError", "ManagementOptions",
    "ManagementRequest", "PROTOCOL", "SAFE_ERROR_CODES", "decode_request", "encode_request",
    "encode_response", "error_response",
]
