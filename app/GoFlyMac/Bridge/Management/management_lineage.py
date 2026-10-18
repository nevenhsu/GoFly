"""Bounded, data-only validation of M2 transfer and M3 management lineage.

The App's ``ManagementStore`` and ``TransferRestoreStore`` remain the
authorities for projection files and preferences.  This module only validates
the bytes which the Mac can read through the fixed HouseArrest mailbox.  It
never treats a valid root or receipt as native/App authority.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any, Mapping

from .management_protocol import (
    ManagementBridgeError,
    TEAM_RE,
    _device,
    _hash,
    _parse_object,
    _uuid,
    _validate_app,
)
from .management_source import PreparationAppIdentity, SourceActivation, decode_source_activation


MAX_MANAGEMENT_ROOT_BYTES = 512 * 1024
MAX_GENERATION_REQUEST_BYTES = 32 * 1024
MAX_GENERATION_ACTIVATION_BYTES = 256 * 1024
MAX_GENERATION_RESTORE_ROOT_BYTES = 1024 * 1024
MAX_MANAGEMENT_HISTORY = 128

_TRANSFER_ROOT_BYTES = 1024 * 1024
_TRANSFER_REQUEST_BYTES = 256 * 1024
_TRANSFER_CATEGORIES = ("favorites", "routes", "settings")
_TRANSFER_PHASES = {"waiting", "validating", "committed", "failed"}
_TRANSFER_CATEGORY_STATES = {"waiting", "validating", "committed", "failed"}
_MANAGEMENT_PHASES = {"preparing", "ready", "mutationSealed", "released", "adopted"}
_MANAGEMENT_ADMISSIONS = {"live", "cold"}
_MANAGEMENT_RECORD_KEYS = {
    "managementID", "nonce", "requestSHA256", "phase", "sourceAdmission", "currentApp",
    "pid", "sourceSetupID", "targetSetupID", "sourceApp", "targetApp",
    "expectedDeviceUDID", "teamID", "sourceActivationSHA256", "sourceRestoreRootSHA256",
    "adoptionReceipt",
}
_MANAGEMENT_ADOPTION_KEYS = {
    "version", "managementID", "nonce", "requestSHA256", "sourceSetupID", "targetSetupID",
    "sourceApp", "targetApp", "expectedDeviceUDID", "teamID", "sourceActivationSHA256",
    "sourceRestoreRootSHA256", "targetActivationSHA256", "receiptSHA256",
}


def _fail(code: str = "identity-mismatch") -> None:
    raise ManagementBridgeError(code)


def _exact_keys(value: Any, keys: set[str]) -> None:
    if not isinstance(value, Mapping) or set(value) != keys:
        _fail("invalid-request")


def _string(value: Any, *, code: str = "invalid-request") -> str:
    if not isinstance(value, str):
        _fail(code)
    return value


def _integer(value: Any, *, minimum: int, maximum: int, code: str = "invalid-request") -> int:
    if type(value) is not int or not minimum <= value <= maximum:
        _fail(code)
    return value


def _optional_hash(value: Any, *, code: str = "invalid-request") -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or _hash(value, code=code) is None:
        _fail(code)
    return value


@dataclass(frozen=True)
class LineageApp:
    """The exact four-field ``SetupAppIdentity`` projection used by Core."""

    bundle_id: str
    build: str
    profile_sha256: str
    executable_sha256: str

    @classmethod
    def from_mapping(cls, value: Any, *, code: str = "identity-mismatch") -> "LineageApp":
        app = _validate_app(value, code=code)
        return cls(app["bundleID"], app["build"], app["profileSHA256"], app["executableSHA256"])

    def as_dict(self) -> dict[str, str]:
        return {
            "bundleID": self.bundle_id,
            "build": self.build,
            "profileSHA256": self.profile_sha256,
            "executableSHA256": self.executable_sha256,
        }


@dataclass(frozen=True)
class ManagementGeneration:
    """One exact, immutable generation read from Core's three fixed files."""

    request: bytes
    source_activation: bytes
    source_restore_root: bytes | None = None

    # These aliases make the raw nature explicit at call sites while keeping
    # the constructor small and matching the Swift filenames.
    @property
    def raw_request(self) -> bytes:
        return self.request

    @property
    def raw_activation(self) -> bytes:
        return self.source_activation

    @property
    def raw_restore_root(self) -> bytes | None:
        return self.source_restore_root


@dataclass(frozen=True)
class SourceLineageSummary:
    """Validated source/transfer lineage, with no native authority claim."""

    current_root_sha256: str | None
    origin_setup_id: str
    origin_app: PreparationAppIdentity
    adopted_management_ids: tuple[str, ...] = ()

    @property
    def root_sha256(self) -> str | None:
        return self.current_root_sha256


# Descriptive aliases are intentionally value aliases, not separate APIs.
ManagementLineageSummary = SourceLineageSummary
ManagementGenerationEvidence = ManagementGeneration


@dataclass(frozen=True)
class _RestoreIntent:
    transfer_id: str
    data_set_id: str
    nonce: str
    raw_manifest_sha256: str
    source_device_id: str
    destination_device_id: str
    source_app: LineageApp
    target_app: LineageApp
    setup_id: str
    categories: tuple[str, ...]


@dataclass(frozen=True)
class _RestoreStatus:
    transfer_id: str
    data_set_id: str
    raw_manifest_sha256: str
    phase: str
    receipt_sha256: str | None
    session_seed_sha256: str | None
    categories: tuple[tuple[str, str, str | None], ...]
    counts: tuple[int, int, int, int, int] | None
    intent: _RestoreIntent | None


@dataclass(frozen=True)
class _RestoreRoot:
    current: _RestoreStatus | None
    pending: tuple[_RestoreStatus, _RestoreIntent] | None
    history: tuple[_RestoreStatus, ...]


@dataclass(frozen=True)
class _ManagementRecord:
    management_id: str
    nonce: str
    request_sha256: str
    phase: str
    source_admission: str
    current_app: LineageApp
    pid: int
    source_setup_id: str
    target_setup_id: str
    source_app: LineageApp
    target_app: LineageApp
    device_id: str
    team_id: str
    source_activation_sha256: str
    source_restore_root_sha256: str | None
    adoption: dict[str, Any] | None


def _decode_uuid(value: Any, *, code: str = "identity-mismatch") -> str:
    try:
        return _uuid(value, code=code)
    except ManagementBridgeError:
        raise
    except Exception:
        _fail(code)
    return ""  # pragma: no cover


def _decode_transfer_intent(value: Any) -> _RestoreIntent:
    keys = {
        "version", "transferID", "dataSetID", "nonce", "rawManifestSHA256",
        "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp", "targetApp", "setupID",
        "categories",
    }
    _exact_keys(value, keys)
    if type(value.get("version")) is not int or value["version"] != 1:
        _fail("invalid-request")
    transfer_id = _decode_uuid(value.get("transferID"))
    data_set_id = _decode_uuid(value.get("dataSetID"))
    nonce = _decode_uuid(value.get("nonce"))
    raw_manifest = _string(value.get("rawManifestSHA256"))
    if _hash(raw_manifest, code="invalid-request") is None:
        _fail("invalid-request")
    source_device = _device(value.get("sourceDeviceUDID"), code="invalid-request")
    destination_device = _device(value.get("destinationDeviceUDID"), code="invalid-request")
    if source_device != destination_device:
        _fail("identity-mismatch")
    categories_value = value.get("categories")
    if not isinstance(categories_value, list):
        _fail("invalid-request")
    categories = tuple(_string(item) for item in categories_value)
    if any(item not in _TRANSFER_CATEGORIES for item in categories):
        _fail("invalid-request")
    if categories != tuple(item for item in _TRANSFER_CATEGORIES if item in categories) or len(set(categories)) != len(categories):
        _fail("invalid-request")
    return _RestoreIntent(
        transfer_id, data_set_id, nonce, raw_manifest, source_device, destination_device,
        LineageApp.from_mapping(value.get("sourceApp")),
        LineageApp.from_mapping(value.get("targetApp")),
        _decode_uuid(value.get("setupID")), categories,
    )


def _decode_counts(value: Any) -> tuple[int, int, int, int, int] | None:
    if value is None:
        return None
    keys = {"favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints"}
    _exact_keys(value, keys)
    # Swift's ``Int`` is 64-bit on the supported Apple targets.
    return tuple(_integer(value[key], minimum=0, maximum=9_223_372_036_854_775_807) for key in (
        "favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints"
    ))  # type: ignore[return-value]


def _decode_restore_status(value: Any) -> _RestoreStatus:
    if not isinstance(value, Mapping):
        _fail("invalid-request")
    keys = {"transferID", "dataSetID", "rawManifestSHA256", "phase", "receiptSHA256", "sessionSeedSHA256", "categories", "counts"}
    if "intent" in value:
        keys.add("intent")
    _exact_keys(value, keys)
    transfer_id = _decode_uuid(value.get("transferID"))
    data_set_id = _decode_uuid(value.get("dataSetID"))
    raw_manifest = _string(value.get("rawManifestSHA256"))
    _hash(raw_manifest, code="invalid-request")
    phase = _string(value.get("phase"))
    if phase not in _TRANSFER_PHASES:
        _fail("invalid-request")
    receipt = _optional_hash(value.get("receiptSHA256"))
    seed = _optional_hash(value.get("sessionSeedSHA256"))
    categories_value = value.get("categories")
    if not isinstance(categories_value, list):
        _fail("invalid-request")
    categories: list[tuple[str, str, str | None]] = []
    seen: set[str] = set()
    for item in categories_value:
        _exact_keys(item, {"category", "state", "receiptSHA256"})
        category = _string(item.get("category"))
        state = _string(item.get("state"))
        if category not in _TRANSFER_CATEGORIES or category in seen or state not in _TRANSFER_CATEGORY_STATES:
            _fail("invalid-request")
        seen.add(category)
        item_receipt = _optional_hash(item.get("receiptSHA256"))
        if (state == "committed") != (item_receipt is not None):
            _fail("identity-mismatch")
        categories.append((category, state, item_receipt))
    category_names = tuple(item[0] for item in categories)
    if category_names != tuple(item for item in _TRANSFER_CATEGORIES if item in seen):
        _fail("identity-mismatch")
    counts = _decode_counts(value.get("counts"))
    intent_value = value.get("intent", None)
    intent = None if "intent" not in value or intent_value is None else _decode_transfer_intent(intent_value)
    if intent is not None:
        if (intent.transfer_id != transfer_id or intent.data_set_id != data_set_id or
                intent.raw_manifest_sha256 != raw_manifest or intent.categories != category_names):
            _fail("identity-mismatch")
    return _RestoreStatus(transfer_id, data_set_id, raw_manifest, phase, receipt, seed,
                          tuple(categories), counts, intent)


def _canonical_restore_receipt(status: _RestoreStatus, intent: _RestoreIntent) -> str:
    if status.receipt_sha256 is None or status.session_seed_sha256 is None or status.counts is None:
        _fail("identity-mismatch")
    category_receipts = [
        {"category": category, "receiptSHA256": receipt}
        for category, state, receipt in status.categories
        if state == "committed" and receipt is not None
    ]
    if len(category_receipts) != len(status.categories):
        _fail("identity-mismatch")
    counts = dict(zip(("favorites", "importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints"), status.counts))
    object_value = {
        "version": 1,
        "intent": {
            "version": 1,
            "transferID": intent.transfer_id,
            "dataSetID": intent.data_set_id,
            "nonce": intent.nonce,
            "rawManifestSHA256": intent.raw_manifest_sha256,
            "sourceDeviceUDID": intent.source_device_id,
            "destinationDeviceUDID": intent.destination_device_id,
            "sourceApp": intent.source_app.as_dict(),
            "targetApp": intent.target_app.as_dict(),
            "setupID": intent.setup_id,
            "categories": list(intent.categories),
        },
        "categoryReceipts": category_receipts,
        "sessionSeedSHA256": status.session_seed_sha256,
        "counts": counts,
    }
    encoded = json.dumps(object_value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _decode_restore_root(raw: bytes) -> _RestoreRoot:
    value = _parse_object(raw, limit=_TRANSFER_ROOT_BYTES)
    _exact_keys(value, {"version", "active", "pending", "history"})
    if type(value.get("version")) is not int or value["version"] != 1:
        _fail("invalid-request")
    active_value = value.get("active")
    current = None if active_value is None else _decode_restore_status(active_value)
    pending_value = value.get("pending")
    pending: tuple[_RestoreStatus, _RestoreIntent] | None = None
    if pending_value is not None:
        _exact_keys(pending_value, {"intent", "status", "pointers", "seed"} if "pointers" in pending_value or "seed" in pending_value else {"intent", "status"})
        intent = _decode_transfer_intent(pending_value.get("intent"))
        status = _decode_restore_status(pending_value.get("status"))
        if (status.transfer_id != intent.transfer_id or status.data_set_id != intent.data_set_id or
                status.raw_manifest_sha256 != intent.raw_manifest_sha256):
            _fail("identity-mismatch")
        if "pointers" in pending_value:
            pointers = pending_value["pointers"]
            if not isinstance(pointers, list) or len(pointers) != len(status.categories):
                _fail("identity-mismatch")
            expected = {category: (state, receipt) for category, state, receipt in status.categories}
            seen: set[str] = set()
            for item in pointers:
                _exact_keys(item, {"category", "state", "pointer", "receiptSHA256"})
                category = _string(item.get("category"))
                if category in seen or category not in expected:
                    _fail("identity-mismatch")
                seen.add(category)
                state, receipt = expected[category]
                if item.get("state") != state or item.get("receiptSHA256") != receipt:
                    _fail("identity-mismatch")
                pointer = item.get("pointer")
                _exact_keys(pointer, {"transferID", "category"})
                if pointer.get("transferID") != status.transfer_id or pointer.get("category") != category:
                    _fail("identity-mismatch")
        if "seed" in pending_value:
            seed = pending_value["seed"]
            _exact_keys(seed, {"state", "sessionSeedSHA256"})
            seed_value = _optional_hash(seed.get("sessionSeedSHA256"))
            if seed_value != status.session_seed_sha256 or seed.get("state") != ("committed" if seed_value else "waiting"):
                _fail("identity-mismatch")
        pending = (status, intent)
    history_value = value.get("history")
    if not isinstance(history_value, list) or len(history_value) > MAX_MANAGEMENT_HISTORY:
        _fail("receipt-capacity" if isinstance(history_value, list) and len(history_value) > MAX_MANAGEMENT_HISTORY else "invalid-request")
    history = tuple(_decode_restore_status(item) for item in history_value)
    if len({item.transfer_id for item in history}) != len(history):
        _fail("identity-mismatch")
    if current is not None and current.transfer_id in {item.transfer_id for item in history}:
        _fail("identity-mismatch")
    return _RestoreRoot(current, pending, history)


def _decode_management_adoption(value: Any) -> dict[str, Any]:
    _exact_keys(value, _MANAGEMENT_ADOPTION_KEYS)
    if type(value.get("version")) is not int or value["version"] != 1:
        _fail("identity-mismatch")
    _decode_uuid(value.get("managementID"))
    _decode_uuid(value.get("nonce"))
    _hash(value.get("requestSHA256"), code="identity-mismatch")
    source_setup = _decode_uuid(value.get("sourceSetupID"))
    target_setup = _decode_uuid(value.get("targetSetupID"))
    if source_setup == target_setup:
        _fail("identity-mismatch")
    source_app = LineageApp.from_mapping(value.get("sourceApp"))
    target_app = LineageApp.from_mapping(value.get("targetApp"))
    device = _device(value.get("expectedDeviceUDID"), code="identity-mismatch")
    team = _string(value.get("teamID"))
    if TEAM_RE.fullmatch(team) is None:
        _fail("identity-mismatch")
    source_activation = _string(value.get("sourceActivationSHA256"))
    target_activation = _string(value.get("targetActivationSHA256"))
    _hash(source_activation, code="identity-mismatch")
    _hash(target_activation, code="identity-mismatch")
    source_root = _optional_hash(value.get("sourceRestoreRootSHA256"), code="identity-mismatch")
    receipt_sha = _string(value.get("receiptSHA256"))
    _hash(receipt_sha, code="identity-mismatch")
    # Keep the standalone Core adoption digest on the existing preparation
    # validator so this read-only proof cannot drift from the response path.
    from .management_preparation import _canonical_adoption_sha256
    if receipt_sha != _canonical_adoption_sha256(value):
        _fail("identity-mismatch")
    return {
        "version": 1, "managementID": value["managementID"], "nonce": value["nonce"],
        "requestSHA256": value["requestSHA256"], "sourceSetupID": source_setup,
        "targetSetupID": target_setup, "sourceApp": source_app, "targetApp": target_app,
        "expectedDeviceUDID": device, "teamID": team,
        "sourceActivationSHA256": source_activation, "sourceRestoreRootSHA256": source_root,
        "targetActivationSHA256": target_activation, "receiptSHA256": receipt_sha,
    }


def _decode_management_record(value: Any) -> _ManagementRecord:
    _exact_keys(value, _MANAGEMENT_RECORD_KEYS)
    management_id = _decode_uuid(value.get("managementID"))
    nonce = _decode_uuid(value.get("nonce"))
    request_sha = _string(value.get("requestSHA256"))
    _hash(request_sha, code="identity-mismatch")
    phase = _string(value.get("phase"))
    admission = _string(value.get("sourceAdmission"))
    if phase not in _MANAGEMENT_PHASES or admission not in _MANAGEMENT_ADMISSIONS:
        _fail("identity-mismatch")
    current_app = LineageApp.from_mapping(value.get("currentApp"))
    pid = _integer(value.get("pid"), minimum=0, maximum=2_147_483_647, code="identity-mismatch")
    source_setup = _decode_uuid(value.get("sourceSetupID"))
    target_setup = _decode_uuid(value.get("targetSetupID"))
    if source_setup == target_setup:
        _fail("identity-mismatch")
    source_app = LineageApp.from_mapping(value.get("sourceApp"))
    target_app = LineageApp.from_mapping(value.get("targetApp"))
    device = _device(value.get("expectedDeviceUDID"), code="identity-mismatch")
    team = _string(value.get("teamID"))
    if TEAM_RE.fullmatch(team) is None:
        _fail("identity-mismatch")
    source_activation = _string(value.get("sourceActivationSHA256"))
    _hash(source_activation, code="identity-mismatch")
    source_root = _optional_hash(value.get("sourceRestoreRootSHA256"), code="identity-mismatch")
    adoption_value = value.get("adoptionReceipt")
    adoption = None if adoption_value is None else _decode_management_adoption(adoption_value)
    if phase == "adopted":
        if pid != 0 or adoption is None:
            _fail("identity-mismatch")
    elif admission == "cold":
        if phase != "preparing" or pid != 0 or adoption is not None:
            _fail("identity-mismatch")
    elif pid <= 0 or adoption is not None:
        _fail("identity-mismatch")
    return _ManagementRecord(
        management_id, nonce, request_sha, phase, admission, current_app, pid,
        source_setup, target_setup, source_app, target_app, device, team,
        source_activation, source_root, adoption,
    )


def _decode_management_root(raw: bytes | None) -> tuple[_ManagementRecord, ...]:
    if raw is None:
        return ()
    value = _parse_object(raw, limit=MAX_MANAGEMENT_ROOT_BYTES)
    _exact_keys(value, {"version", "current", "history"})
    if type(value.get("version")) is not int or value["version"] != 1:
        _fail("identity-mismatch")
    current_value = value.get("current")
    current = () if current_value is None else (_decode_management_record(current_value),)
    history_value = value.get("history")
    if not isinstance(history_value, list) or len(history_value) > MAX_MANAGEMENT_HISTORY:
        _fail("receipt-capacity" if isinstance(history_value, list) and len(history_value) > MAX_MANAGEMENT_HISTORY else "identity-mismatch")
    records = current + tuple(_decode_management_record(item) for item in history_value)
    ids = [item.management_id for item in records]
    if len(ids) != len(set(ids)):
        _fail("identity-mismatch")
    return records


def _validate_generation(record: _ManagementRecord, generation: ManagementGeneration) -> SourceActivation:
    if not isinstance(generation, ManagementGeneration):
        _fail("identity-mismatch")
    if not isinstance(generation.request, bytes) or not 0 < len(generation.request) <= MAX_GENERATION_REQUEST_BYTES:
        _fail("identity-mismatch")
    if not isinstance(generation.source_activation, bytes) or not 0 < len(generation.source_activation) <= MAX_GENERATION_ACTIVATION_BYTES:
        _fail("identity-mismatch")
    if generation.source_restore_root is not None and (
        not isinstance(generation.source_restore_root, bytes)
        or not 0 < len(generation.source_restore_root) <= MAX_GENERATION_RESTORE_ROOT_BYTES
    ):
        _fail("identity-mismatch")
    # This validator is deliberately imported at call time so the preparation
    # adapter can expose the typed triple without an import cycle.
    from .management_preparation import _validate_management_request

    request = _validate_management_request(generation.request)
    request["_raw"] = generation.request
    if hashlib.sha256(generation.request).hexdigest() != record.request_sha256:
        _fail("identity-mismatch")
    for key, expected in (
        ("managementID", record.management_id), ("nonce", record.nonce),
        ("sourceSetupID", record.source_setup_id), ("targetSetupID", record.target_setup_id),
        ("sourceApp", record.source_app.as_dict()), ("targetApp", record.target_app.as_dict()),
        ("expectedDeviceUDID", record.device_id), ("teamID", record.team_id),
        ("sourceActivationSHA256", record.source_activation_sha256),
        ("sourceRestoreRootSHA256", record.source_restore_root_sha256),
    ):
        if request.get(key) != expected:
            _fail("identity-mismatch")
    try:
        source = decode_source_activation(
            generation.source_activation,
            device_id=record.device_id,
            installed_build=record.source_app.build,
            installed_team=record.team_id,
        )
    except ManagementBridgeError:
        raise
    except Exception:
        _fail("identity-mismatch")
    if (
        hashlib.sha256(generation.source_activation).hexdigest() != record.source_activation_sha256
        or source.receipt.setup_id != record.source_setup_id
        or source.identity.app() != record.source_app.as_dict()
        or source.receipt.team_id != record.team_id
        or source.receipt.device_id != record.device_id
    ):
        _fail("identity-mismatch")
    if (generation.source_restore_root is None) != (record.source_restore_root_sha256 is None):
        _fail("identity-mismatch")
    if generation.source_restore_root is not None:
        if hashlib.sha256(generation.source_restore_root).hexdigest() != record.source_restore_root_sha256:
            _fail("identity-mismatch")
        # A saved source root is itself evidence, so reject malformed or
        # pending roots even though Mac never validates the editable tree.
        restore = _decode_restore_root(generation.source_restore_root)
        if restore.pending is not None or restore.current is None or restore.current.phase != "committed":
            _fail("identity-mismatch")

    adoption = record.adoption
    if adoption is None:
        _fail("identity-mismatch")
    if (
        adoption["managementID"] != record.management_id
        or adoption["nonce"] != record.nonce
        or adoption["requestSHA256"] != record.request_sha256
        or adoption["sourceSetupID"] != record.source_setup_id
        or adoption["targetSetupID"] != record.target_setup_id
        or adoption["sourceApp"] != record.source_app
        or adoption["targetApp"] != record.target_app
        or adoption["expectedDeviceUDID"] != record.device_id
        or adoption["teamID"] != record.team_id
        or adoption["sourceActivationSHA256"] != record.source_activation_sha256
        or adoption["sourceRestoreRootSHA256"] != record.source_restore_root_sha256
    ):
        _fail("identity-mismatch")
    return source


def _derive_origin(
    source: SourceActivation,
    records: tuple[_ManagementRecord, ...],
    root_sha: str | None,
    generation_sources: Mapping[str, SourceActivation],
) -> tuple[str, PreparationAppIdentity, tuple[str, ...]]:
    links = [record for record in records if record.phase == "adopted"]
    target_links: dict[str, _ManagementRecord] = {}
    for relation in links:
        if relation.target_setup_id in target_links:
            _fail("identity-mismatch")
        target_links[relation.target_setup_id] = relation
    current_setup = source.receipt.setup_id
    current_app = LineageApp.from_mapping(source.identity.app())
    origin_identity = source.identity
    seen_setup: set[str] = set()
    seen_management: set[str] = set()
    ordered: list[str] = []
    while True:
        if current_setup in seen_setup:
            _fail("identity-mismatch")
        seen_setup.add(current_setup)
        relation = target_links.get(current_setup)
        if relation is None:
            if any(record.target_setup_id == current_setup and record.phase != "adopted" for record in records):
                _fail("identity-mismatch")
            break
        if (
            relation.target_app != current_app
            or relation.device_id != source.receipt.device_id
            or relation.team_id != source.receipt.team_id
            or relation.source_restore_root_sha256 != root_sha
        ):
            _fail("identity-mismatch")
        saved_source = generation_sources.get(relation.management_id)
        if saved_source is None or saved_source.identity.app() != relation.source_app.as_dict():
            _fail("identity-mismatch")
        if relation.management_id in seen_management:
            _fail("identity-mismatch")
        seen_management.add(relation.management_id)
        ordered.append(relation.management_id)
        current_setup = relation.source_setup_id
        current_app = relation.source_app
        origin_identity = saved_source.identity
        if len(ordered) > MAX_MANAGEMENT_HISTORY:
            _fail("receipt-capacity")
    return current_setup, origin_identity, tuple(ordered)


def validate_source_lineage(
    source: SourceActivation,
    device_id: str,
    restore_intent: bytes | None,
    restore_root: bytes | None,
    management_root: bytes | None,
    generations: Mapping[str, ManagementGeneration],
) -> SourceLineageSummary:
    """Validate exact source/M2/M3 bytes and derive the original setup/app.

    ``restore_intent`` and ``restore_root`` must be both present or both
    absent.  A present root must have a committed current status, no pending
    transaction, and an exact final receipt.  Every adopted management record
    is independently checked against its fixed generation before the bounded
    successor chain is followed.
    """
    if not isinstance(source, SourceActivation):
        _fail("identity-mismatch")
    if not isinstance(generations, Mapping):
        _fail("identity-mismatch")
    try:
        selected_device = _device(device_id, code="identity-mismatch")
    except ManagementBridgeError:
        raise
    if source.receipt.device_id != selected_device:
        _fail("identity-mismatch")
    if (restore_intent is None) != (restore_root is None):
        _fail("identity-mismatch")
    current_root_sha = None if restore_root is None else hashlib.sha256(restore_root).hexdigest()
    records = _decode_management_root(management_root)
    adopted = [record for record in records if record.phase == "adopted"]
    if len(adopted) > MAX_MANAGEMENT_HISTORY:
        _fail("receipt-capacity")
    generation_sources: dict[str, SourceActivation] = {}
    for record in adopted:
        generation = generations.get(record.management_id)
        if generation is None:
            _fail("identity-mismatch")
        generation_sources[record.management_id] = _validate_generation(record, generation)
    origin_setup, origin_app, adopted_ids = _derive_origin(
        source, records, current_root_sha, generation_sources
    )

    if restore_intent is None:
        return SourceLineageSummary(None, origin_setup, origin_app, adopted_ids)
    if not isinstance(restore_intent, bytes) or len(restore_intent) > _TRANSFER_REQUEST_BYTES:
        _fail("invalid-request")
    if not isinstance(restore_root, bytes) or len(restore_root) > _TRANSFER_ROOT_BYTES:
        _fail("invalid-request")
    intent_value = _parse_object(restore_intent, limit=_TRANSFER_REQUEST_BYTES)
    intent = _decode_transfer_intent(intent_value)
    root = _decode_restore_root(restore_root)
    if (
        intent.source_device_id != selected_device
        or intent.destination_device_id != selected_device
        or intent.setup_id != origin_setup
        or intent.target_app != LineageApp.from_mapping(origin_app.app())
    ):
        _fail("identity-mismatch")
    if root.pending is not None or root.current is None or root.current.phase != "committed":
        _fail("identity-mismatch")
    status = root.current
    if status.intent != intent:
        _fail("identity-mismatch")
    if _canonical_restore_receipt(status, intent) != status.receipt_sha256:
        _fail("identity-mismatch")
    return SourceLineageSummary(current_root_sha, origin_setup, origin_app, adopted_ids)


def generation_ids(raw: bytes | None) -> tuple[str, ...]:
    """Return only adopted generation IDs from one bounded Core root.

    This is a lookup aid for callers which must read the fixed generation
    files before validation.  It performs the same closed root decode as
    ``validate_source_lineage`` and never treats non-adopted records as
    generation authority.
    """
    return tuple(record.management_id for record in _decode_management_root(raw) if record.phase == "adopted")


__all__ = [
    "MAX_MANAGEMENT_ROOT_BYTES", "MAX_GENERATION_REQUEST_BYTES",
    "MAX_GENERATION_ACTIVATION_BYTES", "MAX_GENERATION_RESTORE_ROOT_BYTES",
    "LineageApp", "ManagementGeneration", "ManagementGenerationEvidence",
    "SourceLineageSummary", "ManagementLineageSummary", "validate_source_lineage", "generation_ids",
]
