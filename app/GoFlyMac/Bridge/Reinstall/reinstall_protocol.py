"""Strict, pure protocol-3 codec for the bounded reinstall boundary."""

from __future__ import annotations

import datetime as dt
import json
import re
import unicodedata
from dataclasses import dataclass
from typing import Any, Mapping

PROTOCOL = 3
MAX_REQUEST_BYTES = 32 * 1024
MAX_RESPONSE_BYTES = 256 * 1024
TARGET_BUNDLE_ID = "com.neven.gofly"
TARGET_NAME = "GoFly"
UUID_RE = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z"
)
UDID_RE = re.compile(r"(?:[0-9a-f]{8}-[0-9a-f]{16}|[0-9a-f]{40})\Z")
TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
INTEGER_RE = re.compile(r"(?:0|[1-9][0-9]*)\Z")
EXPIRY_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z\Z")
MAX_ARTIFACT_PATH_BYTES = 4_096

CATEGORY_ORDER = ("favorites", "routes", "settings")
_ACTIONS = frozenset({"preflight", "apply", "status", "resume", "abandon"})
_SOURCES = frozenset({"signedApp", "project"})
_STAGES = frozenset(
    {"preflight", "artifact", "source", "backup", "seal", "uninstall", "install", "support", "restore", "complete", "abandon"}
)
_OUTCOMES = frozenset({"ready", "inProgress", "confirmed", "unknown", "failed"})
_CATEGORY_STATES = frozenset({"waiting", "validating", "committed", "failed"})
_COUNT_KEYS = ("favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints")
_COUNT_LIMITS = {
    "favorites": 100,
    "importedRoutes": 100,
    "favoriteRoutes": 100,
    "draftNodes": 27,
    "gpxPoints": 2_010_000,
}
_PROOF_KEYS = (
    "backupValidated",
    "sourceSealed",
    "removalConfirmed",
    "installationConfirmed",
    "pairingImported",
    "supportObserved",
    "restoreCommitted",
)
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
        "update-required",
        "source-busy",
        "backup-invalid",
        "restore-unknown",
        "export-conflict",
        "removal-unknown",
        "operation-abandoned",
    }
)


class ReinstallBridgeError(Exception):
    """A fixed safe error code suitable for the protocol boundary."""

    def __init__(self, code: str):
        self.code = code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed"
        super().__init__(self.code)


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ReinstallBridgeError("invalid-request")
        result[key] = value
    return result


def _reject_number(_value: str) -> Any:
    raise ValueError("floating or exponent numeric value")


def _parse_object(data: bytes, *, limit: int) -> dict[str, Any]:
    if not isinstance(data, bytes) or len(data) > limit:
        raise ReinstallBridgeError("invalid-request")
    try:
        value = json.loads(
            data.decode("utf-8"),
            object_pairs_hook=_object_pairs,
            parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            parse_float=_reject_number,
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError, ReinstallBridgeError):
        raise ReinstallBridgeError("invalid-request") from None
    if not isinstance(value, dict):
        raise ReinstallBridgeError("invalid-request")
    _check_depth(value)
    return value


def _check_depth(value: Any, depth: int = 0) -> None:
    if depth > 64:
        raise ReinstallBridgeError("invalid-request")
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ReinstallBridgeError("invalid-request")
            _check_depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _check_depth(child, depth + 1)


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise ReinstallBridgeError("invalid-request")
    return value


def normalized_device(value: Any) -> str:
    if not isinstance(value, str) or value != value.strip() or value != value.lower():
        raise ReinstallBridgeError("invalid-request")
    candidate = value
    if UDID_RE.fullmatch(candidate) is None:
        raise ReinstallBridgeError("invalid-request")
    return candidate


@dataclass(frozen=True)
class ReinstallOptions:
    source: str
    artifact_path: str | None
    team_id: str
    allow_provisioning_updates: bool
    categories: tuple[str, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "source": self.source,
            "artifactPath": self.artifact_path,
            "teamID": self.team_id,
            "allowProvisioningUpdates": self.allow_provisioning_updates,
            "categories": list(self.categories),
        }


@dataclass(frozen=True)
class ReinstallRequest:
    request_id: str
    action: str
    transfer_id: str
    device_id: str
    options: ReinstallOptions | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "protocol": PROTOCOL,
            "requestID": self.request_id,
            "operation": "reinstall",
            "action": self.action,
            "transferID": self.transfer_id,
            "deviceID": self.device_id,
        }
        if self.options is not None:
            value["options"] = self.options.as_dict()
        return value


def _decode_options(value: Any) -> ReinstallOptions:
    if not isinstance(value, dict):
        raise ReinstallBridgeError("invalid-request")
    expected = {"source", "artifactPath", "teamID", "allowProvisioningUpdates", "categories"}
    if set(value) != expected:
        raise ReinstallBridgeError("invalid-request")
    source = value.get("source")
    artifact = value.get("artifactPath")
    team = value.get("teamID")
    allow = value.get("allowProvisioningUpdates")
    categories = value.get("categories")
    if not isinstance(source, str) or source not in _SOURCES or type(allow) is not bool:
        raise ReinstallBridgeError("invalid-request")
    if not isinstance(team, str) or TEAM_RE.fullmatch(team) is None:
        raise ReinstallBridgeError("invalid-request")
    if source == "project":
        if artifact is not None:
            raise ReinstallBridgeError("invalid-request")
    else:
        if not isinstance(artifact, str) or not artifact.startswith("/") or not artifact.endswith(".app"):
            raise ReinstallBridgeError("invalid-request")
        try:
            artifact_bytes = len(artifact.encode("utf-8"))
        except UnicodeError:
            raise ReinstallBridgeError("invalid-request") from None
        if (
            artifact_bytes > MAX_ARTIFACT_PATH_BYTES
            or "\x00" in artifact
            or any(unicodedata.category(char) == "Cs" for char in artifact)
        ):
            raise ReinstallBridgeError("invalid-request")
        if allow is not False:
            raise ReinstallBridgeError("invalid-request")
    if not isinstance(categories, list) or any(not isinstance(item, str) for item in categories):
        raise ReinstallBridgeError("invalid-request")
    if len(categories) != len(set(categories)) or any(item not in CATEGORY_ORDER for item in categories):
        raise ReinstallBridgeError("invalid-request")
    canonical = tuple(item for item in CATEGORY_ORDER if item in categories)
    if tuple(categories) != canonical:
        raise ReinstallBridgeError("invalid-request")
    return ReinstallOptions(source, artifact, team, allow, canonical)


def decode_request(data: bytes) -> ReinstallRequest:
    value = _parse_object(data, limit=MAX_REQUEST_BYTES)
    if "protocol" not in value:
        raise ReinstallBridgeError("invalid-request")
    if type(value.get("protocol")) is not int or value.get("protocol") != PROTOCOL:
        raise ReinstallBridgeError("protocol-mismatch")
    required = {"protocol", "requestID", "operation", "action", "transferID", "deviceID"}
    if set(value) - required - {"options"}:
        raise ReinstallBridgeError("invalid-request")
    if value.get("operation") != "reinstall" or not isinstance(value.get("operation"), str):
        raise ReinstallBridgeError("invalid-request")
    request_id = _uuid(value.get("requestID"))
    transfer_id = _uuid(value.get("transferID"))
    device_id = normalized_device(value.get("deviceID"))
    action = value.get("action")
    if not isinstance(action, str) or action not in _ACTIONS:
        raise ReinstallBridgeError("invalid-request")
    requires_options = action in {"preflight", "apply"}
    if requires_options != ("options" in value):
        raise ReinstallBridgeError("invalid-request")
    options = _decode_options(value["options"]) if requires_options else None
    return ReinstallRequest(request_id, action, transfer_id, device_id, options)


def _validate_hash(value: Any) -> None:
    if not isinstance(value, str) or HEX64_RE.fullmatch(value) is None:
        raise ReinstallBridgeError("operation-failed")


def _validate_expiry(value: Any) -> None:
    if not isinstance(value, str):
        raise ReinstallBridgeError("operation-failed")
    try:
        encoded_length = len(value.encode("utf-8"))
    except UnicodeError:
        raise ReinstallBridgeError("operation-failed") from None
    if encoded_length > 40 or EXPIRY_RE.fullmatch(value) is None:
        raise ReinstallBridgeError("operation-failed")
    try:
        date_part = value.split("T", 1)[0]
        time_part = value.split("T", 1)[1].split(".", 1)[0].removesuffix("Z")
        dt.datetime.strptime(f"{date_part}T{time_part}", "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        raise ReinstallBridgeError("operation-failed") from None


def _validate_app(value: Any) -> None:
    if not isinstance(value, dict) or set(value) != {"bundleID", "build", "profileSHA256", "executableSHA256"}:
        raise ReinstallBridgeError("operation-failed")
    if value.get("bundleID") != TARGET_BUNDLE_ID:
        raise ReinstallBridgeError("operation-failed")
    build = value.get("build")
    if (
        not isinstance(build, str)
        or not build
        or any(unicodedata.category(char) in {"Cc", "Cf", "Cs"} for char in build)
    ):
        raise ReinstallBridgeError("operation-failed")
    try:
        if len(build.encode("utf-8")) > 128:
            raise ReinstallBridgeError("operation-failed")
    except UnicodeError:
        raise ReinstallBridgeError("operation-failed") from None
    _validate_hash(value.get("profileSHA256"))
    _validate_hash(value.get("executableSHA256"))


def _validate_counts(value: Any, selected: set[str] | None, category_names: set[str]) -> None:
    if value is None:
        return
    if not isinstance(value, dict) or set(value) != set(_COUNT_KEYS):
        raise ReinstallBridgeError("operation-failed")
    numeric: dict[str, int] = {}
    for key in _COUNT_KEYS:
        item = value[key]
        if type(item) is not int or item < 0:
            raise ReinstallBridgeError("operation-failed")
        parsed = item
        if parsed > _COUNT_LIMITS[key]:
            raise ReinstallBridgeError("operation-failed")
        numeric[key] = parsed
    effective = selected if selected is not None else category_names
    if "favorites" not in effective and numeric["favorites"] != 0:
        raise ReinstallBridgeError("operation-failed")
    if "routes" not in effective and any(numeric[key] != 0 for key in _COUNT_KEYS[1:]):
        raise ReinstallBridgeError("operation-failed")


def _validate_payload(
    payload: Any,
    *,
    selected: set[str] | None = None,
    allow_default_empty: bool = False,
) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ReinstallBridgeError("operation-failed")
    required = {"stage", "outcome", "canResume", "canAbandon", "proof", "categories", "counts"}
    optional = {"app", "teamID", "expiresAt", "receiptSHA256"}
    if set(payload) - required - optional or not required.issubset(payload):
        raise ReinstallBridgeError("operation-failed")
    if (
        not isinstance(payload.get("stage"), str)
        or payload.get("stage") not in _STAGES
        or not isinstance(payload.get("outcome"), str)
        or payload.get("outcome") not in _OUTCOMES
    ):
        raise ReinstallBridgeError("operation-failed")
    if type(payload.get("canResume")) is not bool or type(payload.get("canAbandon")) is not bool:
        raise ReinstallBridgeError("operation-failed")
    proof = payload.get("proof")
    if not isinstance(proof, dict) or set(proof) != set(_PROOF_KEYS) or any(type(proof[key]) is not bool for key in proof):
        raise ReinstallBridgeError("operation-failed")
    if payload["stage"] == "preflight" and any(proof.values()):
        raise ReinstallBridgeError("operation-failed")
    if payload["stage"] == "install" and payload["outcome"] == "unknown" and proof["installationConfirmed"]:
        raise ReinstallBridgeError("operation-failed")
    if payload["canAbandon"] and any(
        proof[key] for key in ("sourceSealed", "removalConfirmed", "installationConfirmed")
    ):
        raise ReinstallBridgeError("operation-failed")

    categories = payload.get("categories")
    if not isinstance(categories, list):
        raise ReinstallBridgeError("operation-failed")
    category_names: list[str] = []
    for item in categories:
        if not isinstance(item, dict) or set(item) != {"category", "state", "receiptSHA256"}:
            raise ReinstallBridgeError("operation-failed")
        category = item.get("category")
        state = item.get("state")
        receipt = item.get("receiptSHA256")
        if (
            not isinstance(category, str)
            or category not in CATEGORY_ORDER
            or category in category_names
            or not isinstance(state, str)
            or state not in _CATEGORY_STATES
        ):
            raise ReinstallBridgeError("operation-failed")
        if state == "committed":
            _validate_hash(receipt)
        elif receipt is not None:
            raise ReinstallBridgeError("operation-failed")
        category_names.append(category)
    canonical_categories = [item for item in CATEGORY_ORDER if item in category_names]
    if category_names != canonical_categories:
        raise ReinstallBridgeError("operation-failed")
    category_set = set(category_names)
    if selected is not None and not category_set.issubset(selected):
        raise ReinstallBridgeError("operation-failed")
    if selected is not None and category_set != selected:
        if not (
            allow_default_empty
            and not category_set
            and payload["stage"] == "preflight"
            and payload["outcome"] == "unknown"
            and not any(proof.values())
            and payload["counts"] is None
        ):
            raise ReinstallBridgeError("operation-failed")

    _validate_counts(payload.get("counts"), selected, category_set)
    if "app" in payload:
        app = payload.get("app")
        if app is None:
            raise ReinstallBridgeError("operation-failed")
        _validate_app(app)
    team = payload.get("teamID")
    if "teamID" in payload and team is None:
        raise ReinstallBridgeError("operation-failed")
    if team is not None and (not isinstance(team, str) or TEAM_RE.fullmatch(team) is None):
        raise ReinstallBridgeError("operation-failed")
    expires = payload.get("expiresAt")
    if "expiresAt" in payload and expires is None:
        raise ReinstallBridgeError("operation-failed")
    if expires is not None:
        _validate_expiry(expires)
    receipt = payload.get("receiptSHA256")
    if "receiptSHA256" in payload and receipt is None:
        raise ReinstallBridgeError("operation-failed")
    if receipt is not None:
        _validate_hash(receipt)

    if payload["stage"] == "complete" and payload["outcome"] == "confirmed":
        if not all(proof.values()) or payload["canResume"] or payload["canAbandon"]:
            raise ReinstallBridgeError("operation-failed")
        if selected is not None and category_set != selected:
            raise ReinstallBridgeError("operation-failed")
        if any(item["state"] != "committed" for item in categories):
            raise ReinstallBridgeError("operation-failed")
        if payload.get("counts") is None or not isinstance(receipt, str):
            raise ReinstallBridgeError("operation-failed")
    if payload["stage"] == "abandon" and payload["outcome"] == "confirmed":
        if payload["canResume"] or payload["canAbandon"]:
            raise ReinstallBridgeError("operation-failed")
    return payload


def _default_error_payload() -> dict[str, Any]:
    return {
        "stage": "preflight",
        "outcome": "unknown",
        "canResume": False,
        "canAbandon": False,
        "proof": {key: False for key in _PROOF_KEYS},
        "categories": [],
        "counts": None,
    }


def encode_response(
    request: ReinstallRequest,
    *,
    status: str,
    payload: Mapping[str, Any] | None,
    code: str | None = None,
) -> bytes:
    if not isinstance(request, ReinstallRequest) or not isinstance(status, str) or status not in {"ok", "error"}:
        raise ReinstallBridgeError("operation-failed")
    if status == "ok" and code is not None:
        raise ReinstallBridgeError("operation-failed")
    safe_code = code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed"
    if request.options is None:
        selected = None
    elif isinstance(request.options, ReinstallOptions) and all(
        isinstance(item, str) for item in request.options.categories
    ):
        selected = set(request.options.categories)
    else:
        raise ReinstallBridgeError("operation-failed")
    value = _validate_payload(
        _default_error_payload() if payload is None else dict(payload),
        selected=selected,
        allow_default_empty=status == "error",
    )
    if status == "error" and value["stage"] == "complete" and value["outcome"] == "confirmed":
        raise ReinstallBridgeError("operation-failed")
    if request.action == "preflight" and value["stage"] != "preflight":
        raise ReinstallBridgeError("operation-failed")
    response: dict[str, Any] = {
        "protocol": PROTOCOL,
        "requestID": request.request_id,
        "operation": "reinstall",
        "action": request.action,
        "transferID": request.transfer_id,
        "deviceID": request.device_id,
        "status": status,
        "payload": value,
    }
    if status == "error":
        response["code"] = safe_code
        # An error can preserve durable proof, but it cannot claim successful
        # completion through a malformed complete payload.
    try:
        encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise ReinstallBridgeError("operation-failed") from None
    if len(encoded) > MAX_RESPONSE_BYTES:
        raise ReinstallBridgeError("operation-failed")
    return encoded


def _safe_uuid(value: Any) -> str | None:
    return value if isinstance(value, str) and UUID_RE.fullmatch(value) is not None else None


def error_response(
    request: Mapping[str, Any] | None,
    code: str,
    payload: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    value = request if isinstance(request, Mapping) else {}
    action_value = value.get("action")
    action = action_value if isinstance(action_value, str) and action_value in _ACTIONS else None
    try:
        device = normalized_device(value.get("deviceID"))
    except ReinstallBridgeError:
        device = None
    response: dict[str, Any] = {
        "protocol": PROTOCOL,
        "requestID": _safe_uuid(value.get("requestID")),
        "operation": "reinstall",
        "action": action,
        "transferID": _safe_uuid(value.get("transferID")),
        "deviceID": device,
        "status": "error",
        "code": code if isinstance(code, str) and code in SAFE_ERROR_CODES else "operation-failed",
    }
    try:
        candidate = _validate_payload(dict(payload), selected=None) if payload is not None else _default_error_payload()
        if candidate["stage"] == "complete" and candidate["outcome"] == "confirmed":
            raise ReinstallBridgeError("operation-failed")
        response["payload"] = candidate
    except (ReinstallBridgeError, TypeError, ValueError):
        response["payload"] = _default_error_payload()
    return response
