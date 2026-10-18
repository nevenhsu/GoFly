"""Closed protocol-4 codec for local backup management.

The wire format intentionally contains no device or filesystem path supplied
by the caller.  The manager derives every path from the frozen configuration
and the validated M2 journal records.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Mapping

PROTOCOL = 4
MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
UDID_RE = re.compile(r"(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})\Z")
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
TIMESTAMP_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
SAFE_ERROR_CODES = frozenset(
    {
        "invalid-request",
        "configuration-invalid",
        "storage-unavailable",
        "busy",
        "backup-not-complete",
        "backup-changed",
        "operation-failed",
    }
)
_ACTIONS = frozenset({"list", "maintain", "delete"})
_CATEGORIES = ("favorites", "routes", "settings")
_KINDS = frozenset({"completed", "incomplete", "missing", "deleted"})
_COUNT_KEYS = ("favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints")
_COUNT_LIMITS = {
    "favorites": 100,
    "importedRoutes": 100,
    "favoriteRoutes": 100,
    "draftNodes": 27,
    "gpxPoints": 2_010_000,
}


class BackupBridgeError(Exception):
    """A safe error code that may cross the local process boundary."""

    def __init__(self, code: str):
        self.code = code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed"
        super().__init__(self.code)


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def _reject_number(_value: str) -> Any:
    raise ValueError("non-integer number")


def _check_depth(value: Any, depth: int = 0) -> None:
    if depth > 32:
        raise BackupBridgeError("invalid-request")
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise BackupBridgeError("invalid-request")
            _check_depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _check_depth(child, depth + 1)


def _parse_object(data: bytes, *, limit: int) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > limit:
        raise BackupBridgeError("invalid-request")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            parse_float=_reject_number,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError, BackupBridgeError):
        raise BackupBridgeError("invalid-request") from None
    if not isinstance(value, dict):
        raise BackupBridgeError("invalid-request")
    _check_depth(value)
    return value


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise BackupBridgeError("invalid-request")
    return value


@dataclass(frozen=True)
class BackupRequest:
    request_id: str
    action: str
    transfer_id: str | None = None
    confirmed: bool | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "protocol": PROTOCOL,
            "requestID": self.request_id,
            "action": self.action,
        }
        if self.action == "delete":
            value["transferID"] = self.transfer_id
            value["confirmed"] = self.confirmed
        return value


def decode_request(data: bytes) -> BackupRequest:
    value = _parse_object(data, limit=MAX_REQUEST_BYTES)
    if type(value.get("protocol")) is not int or value.get("protocol") != PROTOCOL:
        raise BackupBridgeError("invalid-request")
    action = value.get("action")
    if not isinstance(action, str) or action not in _ACTIONS:
        raise BackupBridgeError("invalid-request")
    request_id = _uuid(value.get("requestID"))
    if action == "delete":
        if set(value) != {"protocol", "requestID", "action", "transferID", "confirmed"}:
            raise BackupBridgeError("invalid-request")
        transfer_id = _uuid(value.get("transferID"))
        if type(value.get("confirmed")) is not bool or value.get("confirmed") is not True:
            raise BackupBridgeError("invalid-request")
        return BackupRequest(request_id, action, transfer_id, True)
    if set(value) != {"protocol", "requestID", "action"}:
        raise BackupBridgeError("invalid-request")
    return BackupRequest(request_id, action)


def _validate_count(value: Any, categories: list[str]) -> None:
    if value is None:
        return
    if not isinstance(value, dict) or set(value) != set(_COUNT_KEYS):
        raise BackupBridgeError("operation-failed")
    for key in _COUNT_KEYS:
        if type(value[key]) is not int or value[key] < 0 or value[key] > _COUNT_LIMITS[key]:
            raise BackupBridgeError("operation-failed")
    selected = set(categories)
    if "favorites" not in selected and value["favorites"] != 0:
        raise BackupBridgeError("operation-failed")
    if "routes" not in selected and any(value[key] != 0 for key in _COUNT_KEYS[1:]):
        raise BackupBridgeError("operation-failed")


def _validate_entry(value: Any) -> None:
    required = {
        "transferID", "dataSetID", "deviceID", "categories", "counts", "kind",
        "completedObservedAt", "deleteAfter", "canDelete", "canContinue",
    }
    if not isinstance(value, dict) or set(value) != required:
        raise BackupBridgeError("operation-failed")
    for key in ("transferID", "dataSetID"):
        if not isinstance(value[key], str) or UUID_RE.fullmatch(value[key]) is None:
            raise BackupBridgeError("operation-failed")
    device = value["deviceID"]
    if not isinstance(device, str) or UDID_RE.fullmatch(device) is None:
        raise BackupBridgeError("operation-failed")
    categories = value["categories"]
    if not isinstance(categories, list) or len(categories) > len(_CATEGORIES) or tuple(categories) != tuple(item for item in _CATEGORIES if item in categories):
        raise BackupBridgeError("operation-failed")
    if any(not isinstance(item, str) or item not in _CATEGORIES for item in categories):
        raise BackupBridgeError("operation-failed")
    if value["kind"] not in _KINDS:
        raise BackupBridgeError("operation-failed")
    for key in ("completedObservedAt", "deleteAfter"):
        timestamp = value[key]
        if timestamp is not None and (not isinstance(timestamp, str) or TIMESTAMP_RE.fullmatch(timestamp) is None):
            raise BackupBridgeError("operation-failed")
    if (value["completedObservedAt"] is None) != (value["deleteAfter"] is None):
        raise BackupBridgeError("operation-failed")
    if type(value["canDelete"]) is not bool or type(value["canContinue"]) is not bool:
        raise BackupBridgeError("operation-failed")
    _validate_count(value["counts"], categories)


def _validate_payload(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict) or set(payload) != {"entries", "pendingDeletion"}:
        raise BackupBridgeError("operation-failed")
    entries = payload["entries"]
    if not isinstance(entries, list) or len(entries) > 129:
        raise BackupBridgeError("operation-failed")
    for entry in entries:
        _validate_entry(entry)
    if type(payload["pendingDeletion"]) is not bool:
        raise BackupBridgeError("operation-failed")
    return payload


def encode_response(
    request: BackupRequest,
    *,
    status: str,
    payload: Mapping[str, Any] | None = None,
    code: str | None = None,
) -> bytes:
    if not isinstance(request, BackupRequest) or status not in {"ok", "error"}:
        raise BackupBridgeError("operation-failed")
    if status == "ok" and code is not None:
        raise BackupBridgeError("operation-failed")
    value: dict[str, Any] = {
        "protocol": PROTOCOL,
        "requestID": request.request_id,
        "status": status,
    }
    if status == "ok":
        value["payload"] = _validate_payload(dict(payload or {}))
    else:
        value["code"] = code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed"
        if payload is not None:
            try:
                value["payload"] = _validate_payload(dict(payload))
            except BackupBridgeError:
                pass
    try:
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise BackupBridgeError("operation-failed") from None
    if len(encoded) > MAX_RESPONSE_BYTES:
        raise BackupBridgeError("operation-failed")
    return encoded


def _safe_uuid(value: Any) -> str | None:
    return value if isinstance(value, str) and UUID_RE.fullmatch(value) is not None else None


def error_response(request: Mapping[str, Any] | None, code: str) -> dict[str, Any]:
    value = request if isinstance(request, Mapping) else {}
    return {
        "protocol": PROTOCOL,
        "requestID": _safe_uuid(value.get("requestID")),
        "status": "error",
        "code": code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed",
    }


__all__ = [
    "BackupBridgeError", "BackupRequest", "MAX_REQUEST_BYTES", "MAX_RESPONSE_BYTES",
    "PROTOCOL", "SAFE_ERROR_CODES", "decode_request", "encode_response", "error_response",
]
