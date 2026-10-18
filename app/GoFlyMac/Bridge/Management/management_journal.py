"""Durable management association, evidence inventory and submission ledger.

This is storage, not device authority. The producer validates the actual typed
receipts before confirming an effect. An interrupted submission never becomes
pending again. The initial selection is consumed by the same atomic file that
creates its management operation, under Setup's real shared operation lock.
"""

from __future__ import annotations

import contextlib
import copy
import hashlib
import json
import os
import uuid
from pathlib import Path
from typing import Any, Iterator, Mapping

from .management_protocol import (
    HEX64_RE, SAFE_ERROR_CODES, UUID_RE, ManagementBridgeError, ManagementRequest,
    _decode_options, _device, _parse_object, _validate_app,
)
from .management_source import decode_source_activation
try:
    from ..Setup.setup_adapters import _write_private
    from ..Setup.setup_journal import (
        _existing_private_root, _lock_file, _read_regular_bytes, _regular, _validate_private_dir,
    )
    from ..Setup.setup_protocol import SetupBridgeError
except ImportError:  # fixed packaged Bridge root
    from Setup.setup_adapters import _write_private
    from Setup.setup_journal import (
        _existing_private_root, _lock_file, _read_regular_bytes, _regular, _validate_private_dir,
    )
    from Setup.setup_protocol import SetupBridgeError

MAX_JOURNAL_BYTES = 2 * 1024 * 1024
MAX_HISTORY = 128
MAX_REVISIONS = 32
STAGES = (
    "artifact", "sourceRequest", "sourceReady", "mutationIntent", "sourceSeal",
    "sourceStop", "legacy", "update", "pairing", "support", "readback",
    "formalInput", "activation", "finalSupport", "complete", "release",
)
EVIDENCE_LIMITS = {
    "sourceActivation": 256 * 1024, "sourceRestoreRoot": 1024 * 1024,
    "sourceRestoreIntent": 256 * 1024, "sourceAdmission": 64 * 1024,
    "targetArtifact": 32 * 1024, "appRequest": 32 * 1024,
    "previousRequest": 32 * 1024, "previousResponse": 64 * 1024,
    "sourceReceipt": 64 * 1024, "sealedReceipt": 64 * 1024,
    "releasedReceipt": 64 * 1024, "legacyInventory": 32 * 1024,
    "legacyIncoming": 256 * 1024, "legacyReadbackRequest": 64 * 1024,
    "legacyReadbackResponse": 64 * 1024, "targetIdentity": 32 * 1024,
    "readbackPlan": 64 * 1024, "formalPlan": 256 * 1024,
    "pairingBinding": 32 * 1024, "activationReceipt": 256 * 1024,
    "adoptionReceipt": 64 * 1024, "supportObservation": 64 * 1024,
    "updateObservation": 32 * 1024,
}
_TOP_KEYS = {"version", "operation", "header", "revisions", "stages", "evidence", "sourceAdmission", "outcome", "errorCode"}
_HEADER_KEYS = {"managementID", "nonce", "targetSetupID", "setupNonce", "deviceID", "selectionID", "kind", "transport", "options"}
_STAGE_KEYS = {"state", "revision", "evidence"}
_REVISION_KEYS = {"number", "selectionID", "transport", "previous", "resolvedThroughSHA256"}


def _completion_ready(value: Mapping[str, Any]) -> bool:
    required = {"sourceRequest", "sourceReady", "mutationIntent", "sourceStop", "legacy", "pairing", "support", "readback", "formalInput", "activation", "finalSupport"}
    if value["header"]["kind"] == "renew":
        required.update({"artifact", "update"})
    if value["sourceAdmission"] == "live":
        required.add("sourceSeal")
    return (value["sourceAdmission"] in {"live", "cold"} and
            {"sourceActivation", "sourceAdmission", "appRequest", "adoptionReceipt"} <= set(value["evidence"]) and
            all(value["stages"][name]["state"] == "confirmed" for name in required))


def _failure(code: str = "storage-unavailable") -> ManagementBridgeError:
    return ManagementBridgeError(code)


def _encoded(value: Any) -> bytes:
    try:
        raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise _failure() from None
    if len(raw) > MAX_JOURNAL_BYTES:
        raise _failure()
    return raw


def _uuid(value: Any) -> None:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None:
        raise _failure()


def _sync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _validate(value: Any) -> None:
    try:
        if not isinstance(value, dict) or set(value) != _TOP_KEYS:
            raise _failure()
        if type(value["version"]) is not int or value["version"] != 1 or value["operation"] != "management":
            raise _failure()
        header = value["header"]
        if not isinstance(header, dict) or set(header) != _HEADER_KEYS:
            raise _failure()
        for key in ("managementID", "nonce", "targetSetupID", "setupNonce", "selectionID"):
            _uuid(header[key])
        _device(header["deviceID"], code="storage-unavailable")
        if header["kind"] not in {"renew", "repair"} or header["transport"] not in {"USB", "Network"}:
            raise _failure()
        _decode_options(header["options"], kind=header["kind"])
        revisions = value["revisions"]
        if not isinstance(revisions, list) or not 1 <= len(revisions) <= MAX_REVISIONS:
            raise _failure()
        seen_selections = set()
        for index, revision in enumerate(revisions):
            if not isinstance(revision, dict) or set(revision) != _REVISION_KEYS:
                raise _failure()
            if type(revision["number"]) is not int or revision["number"] != index:
                raise _failure()
            _uuid(revision["selectionID"])
            if revision["selectionID"] in seen_selections or revision["transport"] not in {"USB", "Network"}:
                raise _failure()
            seen_selections.add(revision["selectionID"])
            if index == 0:
                if revision != {"number": 0, "selectionID": header["selectionID"], "transport": header["transport"],
                                "previous": None, "resolvedThroughSHA256": None}:
                    raise _failure()
            elif (type(revision["previous"]) is not int or revision["previous"] != index - 1 or
                  not isinstance(revision["resolvedThroughSHA256"], str) or
                  HEX64_RE.fullmatch(revision["resolvedThroughSHA256"]) is None):
                raise _failure()
        evidence = value["evidence"]
        if not isinstance(evidence, dict) or not set(evidence) <= set(EVIDENCE_LIMITS):
            raise _failure()
        for name, descriptor in evidence.items():
            if (not isinstance(descriptor, dict) or set(descriptor) != {"byteCount", "sha256"} or
                    type(descriptor["byteCount"]) is not int or not 1 <= descriptor["byteCount"] <= EVIDENCE_LIMITS[name] or
                    not isinstance(descriptor["sha256"], str) or HEX64_RE.fullmatch(descriptor["sha256"]) is None):
                raise _failure()
        if value["sourceAdmission"] not in {None, "live", "cold"}:
            raise _failure()
        if value["sourceAdmission"] is not None and not {"sourceActivation", "sourceAdmission"} <= set(evidence):
            raise _failure()
        stages = value["stages"]
        if not isinstance(stages, dict) or set(stages) != set(STAGES):
            raise _failure()
        for stage in stages.values():
            if not isinstance(stage, dict) or set(stage) != _STAGE_KEYS:
                raise _failure()
            if stage["state"] == "pending":
                if stage["revision"] is not None or stage["evidence"] is not None:
                    raise _failure()
            elif stage["state"] in {"inflight", "unknown", "confirmed"}:
                if type(stage["revision"]) is not int or not 0 <= stage["revision"] < len(revisions):
                    raise _failure()
                if stage["evidence"] is not None and stage["evidence"] not in evidence:
                    raise _failure()
            else:
                raise _failure()
        if value["outcome"] not in {"inProgress", "confirmed", "unknown", "failed"}:
            raise _failure()
        if value["errorCode"] is not None and value["errorCode"] not in SAFE_ERROR_CODES:
            raise _failure()
        terminal_stages = stages["complete"]["state"] == "confirmed" or stages["release"]["state"] == "confirmed"
        if value["outcome"] == "confirmed" and not terminal_stages:
            raise _failure()
        if terminal_stages and (value["outcome"] != "confirmed" or
                any(stage["state"] in {"inflight", "unknown"} for stage in stages.values())):
            raise _failure()
        if stages["release"]["state"] == "confirmed" and stages["mutationIntent"]["state"] != "pending":
            raise _failure()
        if stages["complete"]["state"] == "confirmed" and not _completion_ready(value):
            raise _failure()
    except ManagementBridgeError as error:
        raise _failure() from error
    except (KeyError, TypeError, ValueError, RecursionError):
        raise _failure() from None


class ManagementJournal:
    def __init__(self, state_root: str | Path):
        self.root = Path(state_root)
        self._owns_lock = False

    @property
    def path(self) -> Path:
        return self.root / "management-journal.json"

    @contextlib.contextmanager
    def lock(self) -> Iterator[None]:
        if self._owns_lock:
            raise _failure("busy")
        try:
            with _lock_file(self.root):
                self._owns_lock = True
                try:
                    yield
                finally:
                    self._owns_lock = False
        except SetupBridgeError as error:
            raise _failure(error.code) from None

    def _require_lock(self) -> None:
        if not self._owns_lock:
            raise _failure("busy")

    def _directory(self, name: str, *, create: bool) -> Path:
        path = self.root / name
        try:
            if create and not path.exists():
                path.mkdir(mode=0o700)
                _sync_directory(path)
                _sync_directory(path.parent)
            _validate_private_dir(path)
        except (OSError, SetupBridgeError):
            raise _failure() from None
        return path

    def transaction_root(self, management_id: str, *, create: bool = False) -> Path:
        _uuid(management_id)
        if create:
            self._require_lock()
        parent = self._directory("management-transactions", create=create)
        path = parent / management_id
        try:
            if create and not path.exists():
                path.mkdir(mode=0o700)
                _sync_directory(path)
                _sync_directory(parent)
            _validate_private_dir(path)
        except (OSError, SetupBridgeError):
            raise _failure() from None
        return path

    def _read_path(self, path: Path) -> tuple[bytes, dict[str, Any]]:
        try:
            raw = _read_regular_bytes(path, max_bytes=MAX_JOURNAL_BYTES)
            value = _parse_object(raw, limit=MAX_JOURNAL_BYTES)
            _validate(value)
            self._check_evidence(value)
            return raw, value
        except (SetupBridgeError, ManagementBridgeError):
            raise _failure() from None

    def read(self) -> dict[str, Any] | None:
        try:
            _existing_private_root(self.root)
            if not self.root.exists():
                return None
            _regular(self.path, allow_missing=True)
            if not self.path.exists():
                return None
            return self._read_path(self.path)[1]
        except SetupBridgeError as error:
            raise _failure(error.code) from None

    def _check_evidence(self, value: Mapping[str, Any]) -> None:
        if not value["evidence"]:
            return
        directory = self.transaction_root(value["header"]["managementID"])
        blobs = {}
        for name, descriptor in value["evidence"].items():
            try:
                raw = _read_regular_bytes(directory / (name + ".bin"), max_bytes=EVIDENCE_LIMITS[name])
            except SetupBridgeError:
                raise _failure() from None
            if len(raw) != descriptor["byteCount"] or hashlib.sha256(raw).hexdigest() != descriptor["sha256"]:
                raise _failure()
            blobs[name] = raw
        if value["sourceAdmission"] is not None:
            self._check_source_binding(value, blobs)

    @staticmethod
    def _check_source_binding(value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> None:
        admission = _parse_object(blobs["sourceAdmission"], limit=EVIDENCE_LIMITS["sourceAdmission"])
        if set(admission) != {"activationSHA256", "receiptCount", "maximumReceipts", "sourceSetupID",
                              "sourceApp", "teamID", "deviceID", "sourcePID", "sourceAdmission",
                              "sourceRestoreRootSHA256", "targetSetupID"}:
            raise _failure()
        header = value["header"]
        source_app = _validate_app(admission["sourceApp"], code="storage-unavailable")
        source = decode_source_activation(blobs["sourceActivation"], device_id=header["deviceID"],
                                          installed_build=source_app["build"], installed_team=admission["teamID"])
        source.require_new_receipt_capacity()
        pid = admission["sourcePID"]
        if (admission["sourceAdmission"] != value["sourceAdmission"] or
                type(pid) is not int or not 0 <= pid <= 2_147_483_647 or
                (value["sourceAdmission"] == "cold") != (pid == 0) or
                admission["deviceID"] != header["deviceID"] or
                admission["targetSetupID"] != header["targetSetupID"] or
                source.receipt.setup_id == header["targetSetupID"] or
                source.identity.app() != source_app or
                source.sha256 != admission["activationSHA256"] or
                source.receipt.setup_id != admission["sourceSetupID"] or
                type(admission["receiptCount"]) is not int or source.receipt_count != admission["receiptCount"] or
                type(admission["maximumReceipts"]) is not int or admission["maximumReceipts"] != 128):
            raise _failure()
        root_hash = admission["sourceRestoreRootSHA256"]
        if root_hash is None:
            if "sourceRestoreRoot" in blobs or "sourceRestoreIntent" in blobs:
                raise _failure()
        elif (not isinstance(root_hash, str) or HEX64_RE.fullmatch(root_hash) is None or
              "sourceRestoreRoot" not in blobs or "sourceRestoreIntent" not in blobs or
              hashlib.sha256(blobs["sourceRestoreRoot"]).hexdigest() != root_hash):
            raise _failure()

    def _write(self, value: Mapping[str, Any]) -> dict[str, Any]:
        self._require_lock()
        _validate(value)
        self._check_evidence(value)
        try:
            _write_private(self.path, _encoded(value))
        except SetupBridgeError as error:
            # A parent fsync failure can follow replacement. Never infer that
            # the old pointer survived or retry an effect from in-memory state.
            raise _failure("commit-unknown") from error
        return copy.deepcopy(value)

    def _required(self) -> dict[str, Any]:
        self._require_lock()
        value = self.read()
        if value is None:
            raise _failure("transaction-unknown")
        return value

    def find_selection(self, selection_id: str) -> dict[str, Any] | None:
        _uuid(selection_id)
        current = self.read()
        if current is not None and any(item["selectionID"] == selection_id for item in current["revisions"]):
            return copy.deepcopy(current["header"])
        history = self.root / "management-history"
        if not history.exists():
            if history.is_symlink():
                raise _failure()
            return None
        self._directory("management-history", create=False)
        try:
            paths = list(history.iterdir())
        except OSError:
            raise _failure() from None
        if len(paths) > MAX_HISTORY:
            raise _failure()
        found = None
        for path in paths:
            if path.suffix != ".json":
                raise _failure()
            _uuid(path.stem)
            _, value = self._read_path(path)
            if value["header"]["managementID"] != path.stem or not self.is_terminal(value):
                raise _failure()
            if any(item["selectionID"] == selection_id for item in value["revisions"]):
                if found is not None and found != value["header"]:
                    raise _failure()
                found = copy.deepcopy(value["header"])
        return found

    @staticmethod
    def is_terminal(value: Mapping[str, Any]) -> bool:
        return value["outcome"] == "confirmed" and any(value["stages"][name]["state"] == "confirmed" for name in ("complete", "release"))

    def bind(self, request: ManagementRequest) -> dict[str, Any]:
        value = self._required()
        header = value["header"]
        if any((header["managementID"] != request.management_id, header["deviceID"] != request.device_id,
                header["selectionID"] != request.selection_id, header["kind"] != request.kind,
                header["transport"] != request.transport)):
            raise _failure("transaction-conflict")
        if request.connection_revision != len(value["revisions"]) - 1:
            raise _failure("revision-conflict")
        if request.action in {"apply", "preflight"} and header["options"] != (request.options.as_dict() if request.options else None):
            raise _failure("transaction-conflict")
        return value

    def create(self, request: ManagementRequest) -> dict[str, Any]:
        self._require_lock()
        if request.action != "apply" or request.connection_revision != 0:
            raise _failure("invalid-request")
        current = self.read()
        consumed = self.find_selection(request.selection_id)
        if consumed is not None:
            if current is None or consumed["managementID"] != current["header"]["managementID"]:
                raise _failure("transaction-conflict")
            return self.bind(request)
        historical_id = self.root / "management-history" / (request.management_id + ".json")
        try:
            historical_id.lstat()
        except FileNotFoundError:
            pass
        except OSError:
            raise _failure() from None
        else:
            # An ID owns exactly one immutable transaction directory and
            # archive, independent of the connection selection supplied now.
            raise _failure("transaction-conflict")
        if current is not None:
            if not self.is_terminal(current):
                raise _failure("transaction-conflict")
            if current["header"]["managementID"] == request.management_id:
                raise _failure("transaction-conflict")
            self._archive(current)
        header = {"managementID": request.management_id, "nonce": str(uuid.uuid4()),
                  "targetSetupID": str(uuid.uuid4()), "setupNonce": str(uuid.uuid4()),
                  "deviceID": request.device_id, "selectionID": request.selection_id,
                  "kind": request.kind, "transport": request.transport,
                  "options": request.options.as_dict() if request.options else None}
        value = {"version": 1, "operation": "management", "header": header,
                 "revisions": [{"number": 0, "selectionID": request.selection_id, "transport": request.transport,
                                "previous": None, "resolvedThroughSHA256": None}],
                 "stages": {name: {"state": "pending", "revision": None, "evidence": None} for name in STAGES},
                 "evidence": {}, "sourceAdmission": None, "outcome": "inProgress", "errorCode": None}
        return self._write(value)

    def _archive(self, value: Mapping[str, Any]) -> None:
        history = self._directory("management-history", create=True)
        path = history / (value["header"]["managementID"] + ".json")
        try:
            raw = _read_regular_bytes(self.path, max_bytes=MAX_JOURNAL_BYTES)
            _regular(path, allow_missing=True)
            if path.exists():
                if _read_regular_bytes(path, max_bytes=MAX_JOURNAL_BYTES) != raw:
                    raise _failure()
            else:
                if len(list(history.iterdir())) >= MAX_HISTORY:
                    raise _failure("receipt-capacity")
                _write_private(path, raw)
        except (OSError, SetupBridgeError):
            raise _failure() from None

    def put_evidence(self, name: str, raw: bytes) -> dict[str, Any]:
        value = self._required()
        if name not in EVIDENCE_LIMITS or not isinstance(raw, bytes) or not 1 <= len(raw) <= EVIDENCE_LIMITS[name]:
            raise _failure()
        if self.is_terminal(value):
            raise _failure("transaction-conflict")
        directory = self.transaction_root(value["header"]["managementID"], create=True)
        path = directory / (name + ".bin")
        descriptor = {"byteCount": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
        try:
            _regular(path, allow_missing=True)
            if path.exists():
                if _read_regular_bytes(path, max_bytes=EVIDENCE_LIMITS[name]) != raw:
                    raise _failure("transaction-conflict")
            else:
                _write_private(path, raw)
        except SetupBridgeError as error:
            raise _failure(error.code) from None
        if name in value["evidence"] and value["evidence"][name] != descriptor:
            raise _failure("transaction-conflict")
        value["evidence"][name] = descriptor
        return self._write(value)

    def read_evidence(self, name: str) -> bytes | None:
        value = self.read()
        if value is None or name not in value["evidence"]:
            return None
        try:
            return _read_regular_bytes(self.transaction_root(value["header"]["managementID"]) / (name + ".bin"),
                                       max_bytes=EVIDENCE_LIMITS[name])
        except SetupBridgeError as error:
            raise _failure(error.code) from None

    def bind_source(self, admission: str) -> dict[str, Any]:
        value = self._required()
        if (admission not in {"live", "cold"} or
                value["sourceAdmission"] not in {None, admission} or
                not {"sourceActivation", "sourceAdmission"} <= set(value["evidence"])):
            raise _failure("transaction-conflict")
        value["sourceAdmission"] = admission
        return self._write(value)

    def record_intent(self, stage: str) -> dict[str, Any]:
        value = self._required()
        if stage not in STAGES or stage == "complete" or value["stages"][stage]["state"] != "pending" or self.is_terminal(value):
            raise _failure("transaction-conflict")
        value["stages"][stage] = {"state": "inflight", "revision": len(value["revisions"]) - 1, "evidence": None}
        value["outcome"] = "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def confirm(self, stage: str, evidence: str | None = None) -> dict[str, Any]:
        value = self._required()
        if (stage not in STAGES or stage in {"complete", "release"} or
                value["stages"][stage]["state"] not in {"inflight", "unknown"} or
                (evidence is not None and evidence not in value["evidence"])):
            raise _failure("transaction-conflict")
        value["stages"][stage]["state"] = "confirmed"
        value["stages"][stage]["evidence"] = evidence
        value["outcome"] = "unknown" if self._outstanding(value) else "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def mark_unknown(self, stage: str, code: str) -> dict[str, Any]:
        value = self._required()
        if stage not in STAGES or value["stages"][stage]["state"] not in {"inflight", "unknown"}:
            raise _failure("transaction-conflict")
        value["stages"][stage]["state"] = "unknown"
        value["outcome"] = "unknown"
        value["errorCode"] = code if code in SAFE_ERROR_CODES else "operation-failed"
        return self._write(value)

    def fail(self, code: str) -> dict[str, Any]:
        """Retain a consumed pre-write operation for explicit release/resume.

        Failed never means effects were undone. Submitted or unknown effects
        stay unknown and continue blocking every other writer.
        """
        value = self._required()
        if self.is_terminal(value):
            raise _failure("transaction-conflict")
        value["outcome"] = "unknown" if self._outstanding(value) else "failed"
        value["errorCode"] = code if code in SAFE_ERROR_CODES else "operation-failed"
        return self._write(value)

    @staticmethod
    def _outstanding(value: Mapping[str, Any]) -> bool:
        return any(stage["state"] in {"inflight", "unknown"} for stage in value["stages"].values())

    def append_revision(self, selection_id: str, transport: str) -> dict[str, Any]:
        value = self._required()
        _uuid(selection_id)
        if transport not in {"USB", "Network"} or self.is_terminal(value) or self._outstanding(value):
            raise _failure("revision-conflict")
        if value["revisions"][-1]["transport"] == transport:
            return value
        if len(value["revisions"]) >= MAX_REVISIONS or self.find_selection(selection_id) is not None:
            raise _failure("revision-conflict")
        number = len(value["revisions"])
        value["revisions"].append({"number": number, "selectionID": selection_id, "transport": transport,
                                   "previous": number - 1,
                                   "resolvedThroughSHA256": hashlib.sha256(_encoded(value["stages"])).hexdigest()})
        return self._write(value)

    def release(self) -> dict[str, Any]:
        value = self._required()
        if value["stages"]["release"]["state"] == "confirmed":
            return value
        outstanding = any(stage["state"] in {"inflight", "unknown"}
                          for name, stage in value["stages"].items() if name != "release")
        if value["stages"]["mutationIntent"]["state"] != "pending" or outstanding:
            raise _failure("transaction-conflict")
        if value["stages"]["sourceRequest"]["state"] != "pending" and (
                value["stages"]["release"]["state"] not in {"inflight", "unknown"} or
                "releasedReceipt" not in value["evidence"]):
            raise _failure("transaction-conflict")
        revision = value["stages"]["release"]["revision"]
        value["stages"]["release"] = {"state": "confirmed", "revision": revision if revision is not None else len(value["revisions"]) - 1,
                                      "evidence": "releasedReceipt" if "releasedReceipt" in value["evidence"] else None}
        value["outcome"] = "confirmed"
        value["errorCode"] = None
        return self._write(value)

    def complete(self) -> dict[str, Any]:
        value = self._required()
        if value["stages"]["complete"]["state"] == "confirmed":
            return value
        if self._outstanding(value) or not _completion_ready(value):
            raise _failure("transaction-conflict")
        value["stages"]["complete"] = {"state": "confirmed", "revision": len(value["revisions"]) - 1,
                                       "evidence": "adoptionReceipt"}
        value["outcome"] = "confirmed"
        value["errorCode"] = None
        return self._write(value)


def reject_unresolved_management(state_root: Path) -> None:
    """Read-only guard called by other writers while they own operation.lock."""
    try:
        value = ManagementJournal(state_root).read()
        if value is not None and not ManagementJournal.is_terminal(value):
            raise SetupBridgeError("transaction-conflict")
    except ManagementBridgeError as error:
        raise SetupBridgeError(error.code) from None
