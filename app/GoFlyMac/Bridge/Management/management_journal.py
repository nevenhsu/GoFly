"""Durable management association, evidence inventory and submission ledger.

This is storage, not device authority. The producer validates the actual typed
receipts before confirming an effect. An interrupted submission never becomes
pending again. The initial selection is consumed by the same atomic file that
creates its management operation, under Setup's real shared operation lock.
"""

from __future__ import annotations

import contextlib
import copy
import datetime as _datetime
import hashlib
import json
import os
import re
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
MAX_SELECTIONS = 128
MAX_CONTROL_COMMAND_BYTES = 4 * 1024
MAX_CONTROL_ATTEMPTS = 32
CONTROL_ACTIONS = ("quiesce", "seal", "release")
CONTROL_ATTEMPT_STATES = frozenset({
    "inflight", "unknown", "absentAfterReconcile", "confirmed", "supersededByRelease",
})
STAGES = (
    "artifact", "sourceRequest", "sourceReady", "mutationIntent", "sourceSeal",
    "sourceStop", "legacy", "legacyIncomingRemoval", "legacyReadbackRequestRemoval",
    "legacyReadbackResponseRemoval", "legacyTransition", "update", "pairing", "support",
    "readback", "formalInput", "activation", "finalSupport", "complete", "release",
    "pairCreate", "pairDelivery", "readbackPublish", "readbackLaunch", "readbackStop", "formalLaunch",
)
_LEGACY_STAGES = (
    "artifact", "sourceRequest", "sourceReady", "mutationIntent", "sourceSeal",
    "sourceStop", "legacy", "update", "pairing", "support", "readback",
    "formalInput", "activation", "finalSupport", "complete", "release",
)
EVIDENCE_LIMITS = {
    "sourceActivation": 256 * 1024, "sourceRestoreRoot": 1024 * 1024,
    "sourceRestoreIntent": 256 * 1024, "sourceAdmission": 64 * 1024,
    "targetArtifact": 32 * 1024, "appRequest": 32 * 1024,
    "previousRequest": 32 * 1024, "previousResponse": 64 * 1024,
    "previousControl": 4 * 1024, "sourceManagementRoot": 512 * 1024,
    "sourceReceipt": 64 * 1024, "sealedReceipt": 64 * 1024,
    "releasedReceipt": 64 * 1024, "legacyInventory": 32 * 1024,
    "legacyIncoming": 256 * 1024, "legacyReadbackRequest": 64 * 1024,
    "legacyReadbackResponse": 64 * 1024, "targetIdentity": 32 * 1024,
    "readbackPlan": 64 * 1024, "formalPlan": 256 * 1024,
    "pairingBinding": 32 * 1024, "activationReceipt": 256 * 1024,
    "adoptionReceipt": 64 * 1024, "supportObservation": 64 * 1024,
    "updateObservation": 32 * 1024,
    "pairingPlan": 32 * 1024, "readbackProcess": 32 * 1024,
    "formalProcess": 32 * 1024, "targetReadback": 64 * 1024,
    "finalSupportObservation": 64 * 1024,
    "readbackAbsenceObservation": 32 * 1024,
    "quiesceCommand": MAX_CONTROL_COMMAND_BYTES,
    "sealCommand": MAX_CONTROL_COMMAND_BYTES,
    "releaseCommand": MAX_CONTROL_COMMAND_BYTES,
}
_LEGACY_EVIDENCE_PATHS = {
    "legacyIncoming": "incoming.json",
    "legacyReadbackRequest": "readback-request.json",
    "legacyReadbackResponse": "readback-response.json",
}
_LEGACY_REMOVAL_EVIDENCE = {
    "legacyIncomingRemoval": "legacyIncoming",
    "legacyReadbackRequestRemoval": "legacyReadbackRequest",
    "legacyReadbackResponseRemoval": "legacyReadbackResponse",
}
_LEGACY_INVENTORY_ENTRIES = tuple(_LEGACY_EVIDENCE_PATHS)
_LEGACY_INVENTORY_KEYS = {
    "version", "sourceSetupID", "sourceNonce", "sourceApp", "deviceID",
    "rawManifestSHA256", "entries",
}
_LEGACY_INVENTORY_ENTRY_KEYS = {"present", "byteCount", "sha256"}
_TOP_KEYS = {"version", "operation", "header", "revisions", "stages", "evidence", "sourceAdmission", "outcome", "errorCode"}
_HEADER_KEYS = {"managementID", "nonce", "targetSetupID", "setupNonce", "deviceID", "selectionID", "kind", "transport", "options"}
_STAGE_KEYS = {"state", "revision", "evidence"}
_REVISION_KEYS = {"number", "selectionID", "transport", "previous", "resolvedThroughSHA256"}
_COMMAND_KEYS = {"attempts"}
_ATTEMPT_KEYS = {"attempt", "revision", "commandSHA256", "state"}
_PUBLICATION_KEYS = {"attempts", "exhausted"}
_PUBLICATION_ATTEMPT_KEYS = {
    "number", "revision", "requestSHA256", "state", "recordedAt", "priorOutcome", "terminalReason",
}
_PUBLICATION_STATES = frozenset({"inflight", "unknown", "absentAfterReconcile", "confirmed"})
_PUBLICATION_TIMESTAMP_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?Z$"
)


def _publications(value: Mapping[str, Any]) -> dict[str, Any]:
    """Return the optional readback publication record without synthesizing it."""
    publications = value.get("publications")
    if publications is None:
        return {}
    return publications


def _readback_publication(value: Mapping[str, Any]) -> dict[str, Any] | None:
    publications = _publications(value)
    if not publications:
        return None
    return publications.get("readbackPublish")


def _utc_timestamp() -> str:
    return _datetime.datetime.now(_datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def _selections(value: Mapping[str, Any]) -> list[dict[str, Any]]:
    # Older component journals predate same-transport selection consumption.
    # Their immutable revision identities still remain consumed.
    return value.get("selections", [{"selectionID": item["selectionID"], "revision": item["number"]}
                                     for item in value["revisions"]])


def _commands(value: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    # Component journals written before the control-mailbox amendment have no
    # command records.  Treat those records as empty until a new command is
    # explicitly frozen; never synthesize a command or an attempt on reopen.
    commands = value.get("commands")
    if commands is None:
        return {action: {"attempts": []} for action in CONTROL_ACTIONS}
    return commands


def _completion_readback_evidence(value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> bool:
    """Check the full immutable plan/response binding for the launchless path."""
    try:
        plan_raw = blobs["readbackPlan"]
        plan = _parse_object(plan_raw, limit=EVIDENCE_LIMITS["readbackPlan"])
        if (
            set(plan) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app"}
            or type(plan["version"]) is not int or plan["version"] != 1
            or plan["setupID"] != value["header"]["targetSetupID"]
            or plan["nonce"] != value["header"]["setupNonce"]
            or plan["expectedDeviceUDID"] != value["header"]["deviceID"]
            or _encoded(plan) != plan_raw
        ):
            return False
        target_app = _validate_app(plan["app"], code="storage-unavailable")
        core = _control_request(blobs["appRequest"])
        admission = _parse_object(blobs["sourceAdmission"], limit=EVIDENCE_LIMITS["sourceAdmission"])
        source_app = _validate_app(admission["sourceApp"], code="storage-unavailable")
        if (
            core["managementID"] != value["header"]["managementID"]
            or core["expectedDeviceUDID"] != value["header"]["deviceID"]
            or core["targetSetupID"] != value["header"]["targetSetupID"]
            or core["sourceApp"] != source_app
            or core["targetApp"] != target_app
        ):
            return False
        response = _parse_object(blobs["targetReadback"], limit=EVIDENCE_LIMITS["targetReadback"])
        if set(response) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app", "pairing"}:
            return False
        if (
            type(response["version"]) is not int or response["version"] != 1
            or response["setupID"] != plan["setupID"]
            or response["nonce"] != plan["nonce"]
            or response["expectedDeviceUDID"] != plan["expectedDeviceUDID"]
            or _validate_app(response["app"], code="storage-unavailable") != target_app
        ):
            return False
        binding_raw = blobs["pairingBinding"]
        binding = _parse_object(binding_raw, limit=EVIDENCE_LIMITS["pairingBinding"])
        if (
            set(binding) != {"version", "managementID", "targetSetupID", "deviceID", "transactionID", "sha256"}
            or type(binding["version"]) is not int or binding["version"] != 1
            or binding["managementID"] != value["header"]["managementID"]
            or binding["targetSetupID"] != value["header"]["targetSetupID"]
            or binding["deviceID"] != value["header"]["deviceID"]
            or not isinstance(binding["transactionID"], str)
            or UUID_RE.fullmatch(binding["transactionID"]) is None
            or not isinstance(binding["sha256"], str)
            or HEX64_RE.fullmatch(binding["sha256"]) is None
            or _encoded(binding) != binding_raw
        ):
            return False
        pairing = response["pairing"]
        if not isinstance(pairing, dict) or pairing.get("kind") != "verified":
            return False
        if (
            set(pairing) != {"kind", "expectedDeviceUDID", "sha256"}
            or pairing["expectedDeviceUDID"] != plan["expectedDeviceUDID"]
            or not isinstance(pairing["sha256"], str)
            or HEX64_RE.fullmatch(pairing["sha256"]) is None
            or pairing["sha256"] != binding["sha256"]
        ):
            return False
        return True
    except (ManagementBridgeError, KeyError, TypeError, ValueError, RecursionError):
        return False


def _completion_ready(value: Mapping[str, Any], blobs: Mapping[str, bytes] | None = None) -> bool:
    stages = value["stages"]
    required = {"sourceRequest", "sourceReady", "mutationIntent", "sourceStop", "legacy", "pairing", "support", "readback", "formalInput", "activation", "finalSupport"}
    if "legacyTransition" in stages:
        required.update({
            "legacyIncomingRemoval", "legacyReadbackRequestRemoval",
            "legacyReadbackResponseRemoval", "legacyTransition",
        })
    if value["header"]["kind"] == "renew":
        required.update({"artifact", "update"})
    if value["sourceAdmission"] == "live":
        required.add("sourceSeal")
    if "pairCreate" in stages:
        required.update({"readbackPublish", "readbackLaunch", "readbackStop", "formalLaunch"})
        if value["header"]["kind"] == "repair":
            required.update({"pairCreate", "pairDelivery"})
        elif any(stages[name]["state"] != "pending" for name in ("pairCreate", "pairDelivery")):
            return False
    # A lost first identity launch may be closed only by a confirmed exact
    # target readback plus a readback-stop checkpoint backed by the bounded,
    # exact genuine-zero observation.  This is a narrow completion alternative;
    # it never creates launch ownership or formal-launch proof.
    recovery_without_launch = (
        "readbackLaunch" in stages
        and stages["readbackLaunch"]["state"] == "pending"
        and stages.get("readbackStop", {}).get("state") == "confirmed"
        and stages["readbackStop"].get("evidence") == "readbackAbsenceObservation"
        and stages.get("readback", {}).get("state") == "confirmed"
        and {"readbackPlan", "targetReadback", "pairingBinding", "readbackAbsenceObservation"} <= set(value["evidence"])
    )
    if recovery_without_launch:
        # The alternative is only valid after the caller has loaded and
        # revalidated every immutable evidence blob.  Stage metadata alone
        # can never close a pending launch.
        if blobs is None or not _completion_readback_evidence(value, blobs):
            return False
        required.discard("readbackLaunch")
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


def _control_request(raw: bytes) -> dict[str, Any]:
    """Validate the stored Core management request without device access."""
    try:
        from .management_preparation import _validate_management_request
    except ImportError:  # fixed packaged Bridge root
        from Management.management_preparation import _validate_management_request
    request = _validate_management_request(raw)
    request["_raw"] = raw
    return request


def _control_bytes(raw: bytes, action: str, request_raw: bytes) -> dict[str, Any]:
    if action not in CONTROL_ACTIONS or not isinstance(raw, bytes) or not 1 <= len(raw) <= MAX_CONTROL_COMMAND_BYTES:
        raise _failure("invalid-request")
    try:
        from .management_preparation import _validate_control
    except ImportError:  # fixed packaged Bridge root
        from Management.management_preparation import _validate_control
    try:
        control = _validate_control(raw, _control_request(request_raw))
    except ManagementBridgeError as error:
        raise _failure(error.code) from None
    except Exception:
        raise _failure("transaction-conflict") from None
    if control["action"] != action:
        raise _failure("transaction-conflict")
    return control


def _typed_source_response(raw: bytes, phases: set[str], request_raw: bytes) -> tuple[dict[str, Any], int]:
    if not isinstance(raw, bytes):
        raise _failure("invalid-request")
    try:
        from .management_preparation import _source_response_has_phase, _strict_object
    except ImportError:  # fixed packaged Bridge root
        from Management.management_preparation import _source_response_has_phase, _strict_object
    try:
        request = _control_request(request_raw)
        if not _source_response_has_phase(raw, request, phases):
            raise ValueError("response does not bind")
        response = _strict_object(raw, limit=64 * 1024)
        pid = response["pid"]
        if type(pid) is not int or pid <= 0:
            raise ValueError("invalid pid")
    except Exception:
        raise _failure("transaction-conflict") from None
    return response, pid


def _control_response(raw: bytes, action: str, request_raw: bytes) -> tuple[dict[str, Any], int]:
    phase = {"quiesce": "ready", "seal": "mutationSealed", "release": "released"}.get(action)
    if phase is None:
        raise _failure("invalid-request")
    return _typed_source_response(raw, {phase}, request_raw)


def _validate(value: Any) -> None:
    try:
        allowed_top_keys = tuple(
            _TOP_KEYS | optional
            for optional in (
                set(), {"selections"}, {"commands"}, {"publications"},
                {"selections", "commands"}, {"selections", "publications"},
                {"commands", "publications"}, {"selections", "commands", "publications"},
            )
        )
        if not isinstance(value, dict) or set(value) not in allowed_top_keys:
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
                  revision["transport"] == revisions[index - 1]["transport"] or
                  not isinstance(revision["resolvedThroughSHA256"], str) or
                  HEX64_RE.fullmatch(revision["resolvedThroughSHA256"]) is None):
                raise _failure()
        selections = _selections(value)
        if not isinstance(selections, list) or not 1 <= len(selections) <= MAX_SELECTIONS:
            raise _failure()
        association_ids = set()
        previous_revision = 0
        for association in selections:
            if not isinstance(association, dict) or set(association) != {"selectionID", "revision"}:
                raise _failure()
            _uuid(association["selectionID"])
            number = association["revision"]
            if (association["selectionID"] in association_ids or type(number) is not int or
                    not previous_revision <= number < len(revisions)):
                raise _failure()
            association_ids.add(association["selectionID"])
            previous_revision = number
        if selections[0] != {"selectionID": header["selectionID"], "revision": 0}:
            raise _failure()
        if any({"selectionID": revision["selectionID"], "revision": revision["number"]} not in selections
               for revision in revisions):
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
        if not isinstance(stages, dict) or set(stages) not in (set(_LEGACY_STAGES), set(STAGES)):
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
        if "legacyTransition" in stages:
            removal_names = (
                "legacyIncomingRemoval", "legacyReadbackRequestRemoval",
                "legacyReadbackResponseRemoval",
            )
            if (stages["legacyTransition"]["state"] == "confirmed" and
                    any(stages[name]["state"] != "confirmed" for name in removal_names)):
                raise _failure()
        if "commands" in value:
            commands = value["commands"]
            if not isinstance(commands, dict) or set(commands) != set(CONTROL_ACTIONS):
                raise _failure()
            for action in CONTROL_ACTIONS:
                record = commands[action]
                if not isinstance(record, dict) or set(record) != _COMMAND_KEYS:
                    raise _failure()
                attempts = record["attempts"]
                if not isinstance(attempts, list) or len(attempts) > MAX_CONTROL_ATTEMPTS:
                    raise _failure()
                previous_revision = None
                for index, attempt in enumerate(attempts):
                    if not isinstance(attempt, dict) or set(attempt) != _ATTEMPT_KEYS:
                        raise _failure()
                    if (type(attempt["attempt"]) is not int or attempt["attempt"] != index + 1 or
                            type(attempt["revision"]) is not int or
                            not 0 <= attempt["revision"] < len(revisions) or
                            not isinstance(attempt["commandSHA256"], str) or
                            HEX64_RE.fullmatch(attempt["commandSHA256"]) is None or
                            attempt["state"] not in CONTROL_ATTEMPT_STATES):
                        raise _failure()
                    if previous_revision is None:
                        previous_revision = attempt["revision"]
                    elif attempt["revision"] != previous_revision:
                        raise _failure()
                    evidence_name = action + "Command"
                    if evidence_name not in evidence or evidence[evidence_name]["sha256"] != attempt["commandSHA256"]:
                        raise _failure()
                    if action != "quiesce" and attempt["state"] == "supersededByRelease":
                        raise _failure()
        if "commands" in value:
            commands = value["commands"]
            if commands["seal"]["attempts"] and not commands["quiesce"]["attempts"]:
                raise _failure()
            if commands["release"]["attempts"] and not commands["quiesce"]["attempts"]:
                raise _failure()
            if (commands["seal"]["attempts"] and commands["release"]["attempts"]):
                raise _failure()
            if (any(attempt["state"] == "supersededByRelease"
                    for attempt in commands["quiesce"]["attempts"])
                    and not commands["release"]["attempts"]):
                raise _failure()
        if "publications" in value:
            publications = value["publications"]
            if not isinstance(publications, dict) or set(publications) != {"readbackPublish"}:
                raise _failure()
            record = publications["readbackPublish"]
            if not isinstance(record, dict) or set(record) != _PUBLICATION_KEYS:
                raise _failure()
            attempts = record["attempts"]
            if (not isinstance(attempts, list) or len(attempts) > MAX_CONTROL_ATTEMPTS or
                    type(record["exhausted"]) is not bool):
                raise _failure()
            first_revision = None
            previous_state = None
            for index, attempt in enumerate(attempts):
                if not isinstance(attempt, dict) or set(attempt) != _PUBLICATION_ATTEMPT_KEYS:
                    raise _failure()
                if (type(attempt["number"]) is not int or attempt["number"] != index + 1 or
                        type(attempt["revision"]) is not int or
                        not 0 <= attempt["revision"] < len(revisions) or
                        not isinstance(attempt["requestSHA256"], str) or
                        HEX64_RE.fullmatch(attempt["requestSHA256"]) is None or
                        attempt["state"] not in _PUBLICATION_STATES or
                        not isinstance(attempt["recordedAt"], str) or
                        _PUBLICATION_TIMESTAMP_RE.fullmatch(attempt["recordedAt"]) is None):
                    raise _failure()
                try:
                    parsed_timestamp = _datetime.datetime.fromisoformat(attempt["recordedAt"].replace("Z", "+00:00"))
                except ValueError:
                    raise _failure() from None
                if parsed_timestamp.tzinfo is None:
                    raise _failure()
                prior = attempt["priorOutcome"]
                if index == 0:
                    if prior is not None:
                        raise _failure()
                    first_revision = attempt["revision"]
                else:
                    if prior != previous_state:
                        raise _failure()
                    if attempt["revision"] != first_revision:
                        raise _failure()
                terminal_reason = attempt["terminalReason"]
                if attempt["state"] == "inflight":
                    if terminal_reason is not None:
                        raise _failure()
                elif attempt["state"] == "unknown":
                    if terminal_reason not in {"publication-interrupted", "attempt-limit"}:
                        raise _failure()
                    if (terminal_reason == "attempt-limit" and
                            (not record["exhausted"] or len(attempts) != MAX_CONTROL_ATTEMPTS)):
                        raise _failure()
                elif attempt["state"] == "absentAfterReconcile":
                    if terminal_reason != "absent-on-explicit-resume":
                        raise _failure()
                elif attempt["state"] == "confirmed":
                    if terminal_reason != "exact-request-observed":
                        raise _failure()
                previous_state = attempt["state"]
            if record["exhausted"] and len(attempts) < MAX_CONTROL_ATTEMPTS:
                raise _failure()
            if attempts:
                if "readbackPlan" not in value["evidence"]:
                    raise _failure()
                plan_sha = value["evidence"]["readbackPlan"]["sha256"]
                if any(attempt["requestSHA256"] != plan_sha for attempt in attempts):
                    raise _failure()
            if attempts:
                latest_state = attempts[-1]["state"]
                publication_stage_state = stages["readbackPublish"]["state"]
                if latest_state == "confirmed" and publication_stage_state != "confirmed":
                    raise _failure()
                if latest_state in {"inflight", "unknown", "absentAfterReconcile"} and publication_stage_state not in {
                    "inflight", "unknown",
                }:
                    raise _failure()
        if value["outcome"] not in {"inProgress", "confirmed", "unknown", "failed"}:
            raise _failure()
        if value["errorCode"] is not None and value["errorCode"] not in SAFE_ERROR_CODES:
            raise _failure()
        terminal_stages = stages["complete"]["state"] == "confirmed" or stages["release"]["state"] == "confirmed"
        if value["outcome"] == "confirmed" and not terminal_stages:
            raise _failure()
        if terminal_stages and (value["outcome"] != "confirmed" or
                any(stage["state"] in {"inflight", "unknown"} for stage in stages.values()) or
                ("commands" in value and any(
                    attempt["state"] in {"inflight", "unknown", "absentAfterReconcile"}
                    for record in value["commands"].values() for attempt in record["attempts"]
                ) or
                ("publications" in value and any(
                    attempt["state"] in {"inflight", "unknown"}
                    for attempt in value["publications"]["readbackPublish"]["attempts"]
                )))):
            raise _failure()
        if stages["release"]["state"] == "confirmed" and stages["mutationIntent"]["state"] != "pending":
            raise _failure()
        # Evidence-backed completion is checked by _check_evidence below.  A
        # pending readback launch specifically requires those bytes, so do not
        # make the structural pass authorize the launchless alternative.
        if (stages["complete"]["state"] == "confirmed"
                and stages.get("readbackLaunch", {}).get("state") != "pending"
                and not _completion_ready(value)):
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

    @staticmethod
    def _private_child_directory(parent: Path, name: str, *, create: bool) -> Path:
        path = parent / name
        try:
            if create and not path.exists():
                path.mkdir(mode=0o700)
                _sync_directory(path)
                _sync_directory(path.parent)
            _validate_private_dir(path)
        except (OSError, SetupBridgeError):
            raise _failure() from None
        return path

    def _evidence_path(self, value: Mapping[str, Any], name: str, *, create: bool = False) -> Path:
        directory = self.transaction_root(value["header"]["managementID"], create=create)
        legacy_name = _LEGACY_EVIDENCE_PATHS.get(name)
        if legacy_name is not None:
            directory = self._private_child_directory(directory, "legacy", create=create)
            return directory / legacy_name
        return directory / (name + ".bin")

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
        blobs = {}
        for name, descriptor in value["evidence"].items():
            try:
                path = self._evidence_path(value, name)
                raw = _read_regular_bytes(path, max_bytes=EVIDENCE_LIMITS[name])
            except SetupBridgeError:
                raise _failure() from None
            if len(raw) != descriptor["byteCount"] or hashlib.sha256(raw).hexdigest() != descriptor["sha256"]:
                raise _failure()
            blobs[name] = raw
        if value["sourceAdmission"] is not None:
            self._check_source_binding(value, blobs)
        self._check_command_records(value, blobs)
        if "legacyInventory" in value["evidence"]:
            self._check_legacy_inventory(value, blobs)
        self._check_legacy_stage_rules(value, blobs)
        if "readbackAbsenceObservation" in value["evidence"]:
            self._check_readback_absence(value, blobs)
        if value["stages"]["complete"]["state"] == "confirmed" and not _completion_ready(value, blobs):
            raise _failure()

    @staticmethod
    def _check_readback_absence(value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> None:
        """Validate the bounded genuine-zero observation against immutable plan identity."""
        if not {"readbackPlan", "readbackAbsenceObservation"} <= set(blobs):
            raise _failure()
        try:
            plan_raw = blobs["readbackPlan"]
            plan = _parse_object(plan_raw, limit=EVIDENCE_LIMITS["readbackPlan"])
            if (
                set(plan) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app"}
                or type(plan["version"]) is not int or plan["version"] != 1
                or plan["setupID"] != value["header"]["targetSetupID"]
                or plan["nonce"] != value["header"]["setupNonce"]
                or plan["expectedDeviceUDID"] != value["header"]["deviceID"]
                or _encoded(plan) != plan_raw
            ):
                raise _failure()
            _validate_app(plan["app"], code="storage-unavailable")
            observation = _parse_object(
                blobs["readbackAbsenceObservation"],
                limit=EVIDENCE_LIMITS["readbackAbsenceObservation"],
            )
        except (ManagementBridgeError, TypeError, ValueError):
            raise _failure() from None
        if set(observation) != {
            "version", "deviceID", "setupID", "nonce", "readbackPlanSHA256", "pid",
        }:
            raise _failure()
        if (type(observation["version"]) is not int or observation["version"] != 1 or
                type(observation["pid"]) is not int or observation["pid"] != 0 or
                observation["deviceID"] != value["header"]["deviceID"] or
                observation["setupID"] != value["header"]["targetSetupID"] or
                observation["nonce"] != value["header"]["setupNonce"] or
                not isinstance(observation["readbackPlanSHA256"], str) or
                HEX64_RE.fullmatch(observation["readbackPlanSHA256"]) is None or
                observation["readbackPlanSHA256"] != value["evidence"]["readbackPlan"]["sha256"]):
            raise _failure()
        _uuid(observation["setupID"])
        _uuid(observation["nonce"])
        _device(observation["deviceID"], code="storage-unavailable")

    @staticmethod
    def _check_command_records(value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> None:
        if "commands" not in value:
            return
        confirmed_names = {
            "quiesce": "sourceReceipt", "seal": "sealedReceipt", "release": "releasedReceipt",
        }
        for action, record in value["commands"].items():
            for attempt in record["attempts"]:
                if attempt["state"] != "confirmed":
                    continue
                receipt_name = confirmed_names[action]
                if "appRequest" not in blobs or receipt_name not in blobs:
                    raise _failure()
                _, response_pid = _control_response(blobs[receipt_name], action, blobs["appRequest"])
                if value["sourceAdmission"] != "live" or "sourceAdmission" not in blobs:
                    raise _failure()
                admission = _parse_object(blobs["sourceAdmission"], limit=EVIDENCE_LIMITS["sourceAdmission"])
                if admission.get("sourcePID") != response_pid:
                    raise _failure()
        if any(attempt["state"] == "confirmed" for attempt in value["commands"]["seal"]["attempts"]):
            if any(attempt["state"] != "confirmed" for attempt in value["commands"]["quiesce"]["attempts"]):
                raise _failure()
        if any(attempt["state"] == "confirmed" for attempt in value["commands"]["release"]["attempts"]):
            if any(attempt["state"] != "supersededByRelease" for attempt in value["commands"]["quiesce"]["attempts"]):
                raise _failure()

    @staticmethod
    def _parse_legacy_inventory(raw: bytes) -> dict[str, Any]:
        inventory = _parse_object(raw, limit=EVIDENCE_LIMITS["legacyInventory"])
        if set(inventory) != _LEGACY_INVENTORY_KEYS or inventory["version"] != 1:
            raise _failure()
        _uuid(inventory["sourceSetupID"])
        _uuid(inventory["sourceNonce"])
        _validate_app(inventory["sourceApp"], code="storage-unavailable")
        _device(inventory["deviceID"], code="storage-unavailable")
        if (not isinstance(inventory["rawManifestSHA256"], str) or
                HEX64_RE.fullmatch(inventory["rawManifestSHA256"]) is None):
            raise _failure()
        entries = inventory["entries"]
        if not isinstance(entries, dict) or set(entries) != set(_LEGACY_INVENTORY_ENTRIES):
            raise _failure()
        for name in _LEGACY_INVENTORY_ENTRIES:
            entry = entries[name]
            if not isinstance(entry, dict) or set(entry) != _LEGACY_INVENTORY_ENTRY_KEYS:
                raise _failure()
            present = entry["present"]
            count = entry["byteCount"]
            digest = entry["sha256"]
            if type(present) is not bool or type(count) is not int:
                raise _failure()
            if present:
                if (not 1 <= count <= EVIDENCE_LIMITS[name] or not isinstance(digest, str) or
                        HEX64_RE.fullmatch(digest) is None):
                    raise _failure()
            elif count != 0 or digest is not None:
                raise _failure()
        return inventory

    def _check_legacy_inventory(self, value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> dict[str, Any]:
        if not {"sourceActivation", "sourceAdmission", "legacyInventory"} <= set(blobs):
            raise _failure()
        inventory = self._parse_legacy_inventory(blobs["legacyInventory"])
        admission = _parse_object(blobs["sourceAdmission"], limit=EVIDENCE_LIMITS["sourceAdmission"])
        source_app = _validate_app(admission["sourceApp"], code="storage-unavailable")
        source = decode_source_activation(
            blobs["sourceActivation"], device_id=value["header"]["deviceID"],
            installed_build=source_app["build"], installed_team=admission["teamID"],
        )
        if (inventory["sourceSetupID"] != source.receipt.setup_id or
                inventory["sourceNonce"] != source.receipt.nonce or
                inventory["sourceApp"] != source.identity.app() or
                inventory["deviceID"] != value["header"]["deviceID"] or
                inventory["deviceID"] != source.receipt.device_id or
                inventory["rawManifestSHA256"] != source.receipt.raw_manifest_sha256 or
                inventory["sourceSetupID"] != admission["sourceSetupID"] or
                inventory["sourceApp"] != source_app or
                inventory["deviceID"] != admission["deviceID"]):
            raise _failure()
        entries = inventory["entries"]
        for name in _LEGACY_INVENTORY_ENTRIES:
            entry = entries[name]
            if entry["present"]:
                if name not in value["evidence"] or name not in blobs:
                    raise _failure()
                if (len(blobs[name]) != entry["byteCount"] or
                        hashlib.sha256(blobs[name]).hexdigest() != entry["sha256"]):
                    raise _failure()
                continue
            if name in value["evidence"] or name in blobs:
                raise _failure()
            directory = self.transaction_root(value["header"]["managementID"])
            legacy_directory = directory / "legacy"
            try:
                legacy_directory.lstat()
            except SetupBridgeError:
                raise _failure() from None
            except FileNotFoundError:
                continue
            except OSError:
                raise _failure() from None
            try:
                _validate_private_dir(legacy_directory)
                legacy_path = legacy_directory / _LEGACY_EVIDENCE_PATHS[name]
                _regular(legacy_path, allow_missing=True)
                if legacy_path.exists():
                    raise _failure()
            except SetupBridgeError:
                raise _failure() from None
        return inventory

    def _check_legacy_stage_rules(self, value: Mapping[str, Any], blobs: Mapping[str, bytes]) -> None:
        stages = value["stages"]
        removal_names = tuple(_LEGACY_REMOVAL_EVIDENCE)
        active_removals = [name for name in removal_names if stages.get(name, {}).get("state") != "pending"]
        transition = stages.get("legacyTransition")
        if not active_removals and (transition is None or transition["state"] == "pending"):
            return
        if (value["sourceAdmission"] not in {"live", "cold"} or
                not {"sourceActivation", "sourceAdmission", "legacyInventory"} <= set(blobs) or
                stages["legacy"]["state"] != "confirmed" or
                stages["legacy"]["evidence"] != "legacyInventory" or
                stages["mutationIntent"]["state"] != "confirmed" or
                stages["sourceStop"]["state"] != "confirmed"):
            raise _failure()
        if value["sourceAdmission"] == "live":
            if stages["sourceSeal"]["state"] != "confirmed":
                raise _failure()
        elif stages["sourceSeal"]["state"] != "pending":
            raise _failure()
        inventory = self._check_legacy_inventory(value, blobs)
        for stage_name, evidence_name in _LEGACY_REMOVAL_EVIDENCE.items():
            stage = stages[stage_name]
            if stage["state"] == "pending":
                continue
            if stage["state"] == "confirmed":
                entry = inventory["entries"][evidence_name]
                expected = evidence_name if entry["present"] else "legacyInventory"
                if stage["evidence"] != expected:
                    raise _failure()
        if transition is not None and transition["state"] != "pending":
            if (stages["legacy"]["state"] != "confirmed" or
                    any(stages[name]["state"] != "confirmed" for name in removal_names) or
                    transition["state"] == "confirmed" and transition["evidence"] != "legacyInventory"):
                raise _failure()

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
        found = None
        if current is not None and any(item["selectionID"] == selection_id for item in _selections(current)):
            found = copy.deepcopy(current["header"])
        history = self.root / "management-history"
        if not history.exists():
            if history.is_symlink():
                raise _failure()
            return found
        self._directory("management-history", create=False)
        try:
            paths = list(history.iterdir())
        except OSError:
            raise _failure() from None
        if len(paths) > MAX_HISTORY:
            raise _failure()
        for path in paths:
            if path.suffix != ".json":
                raise _failure()
            _uuid(path.stem)
            _, value = self._read_path(path)
            if value["header"]["managementID"] != path.stem or not self.is_terminal(value):
                raise _failure()
            if any(item["selectionID"] == selection_id for item in _selections(value)):
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
                 "selections": [{"selectionID": request.selection_id, "revision": 0}],
                 "commands": {action: {"attempts": []} for action in CONTROL_ACTIONS},
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
        if name in {action + "Command" for action in CONTROL_ACTIONS}:
            raise _failure("transaction-conflict")
        if self.is_terminal(value):
            raise _failure("transaction-conflict")
        path = self._evidence_path(value, name, create=True)
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
            return _read_regular_bytes(self._evidence_path(value, name), max_bytes=EVIDENCE_LIMITS[name])
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

    def _evidence_bytes(self, value: Mapping[str, Any], name: str) -> bytes:
        if name not in value["evidence"]:
            raise _failure("transaction-conflict")
        try:
            return _read_regular_bytes(self._evidence_path(value, name), max_bytes=EVIDENCE_LIMITS[name])
        except SetupBridgeError:
            raise _failure() from None

    def _put_evidence(self, value: dict[str, Any], name: str, raw: bytes) -> None:
        """Persist one immutable blob before its journal descriptor changes."""
        directory = self.transaction_root(value["header"]["managementID"], create=True)
        path = self._evidence_path(value, name, create=True)
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

    def _command_record(self, value: Mapping[str, Any], action: str) -> dict[str, Any]:
        if action not in CONTROL_ACTIONS:
            raise _failure("invalid-request")
        return _commands(value)[action]

    @staticmethod
    def _release_command_gate(value: Mapping[str, Any]) -> None:
        commands = _commands(value)
        if commands["seal"]["attempts"] or value["stages"]["sourceSeal"]["state"] != "pending":
            raise _failure("transaction-conflict")
        if value["stages"]["mutationIntent"]["state"] != "pending":
            raise _failure("transaction-conflict")
        forbidden = {
            "sourceStop", "legacy", "legacyIncomingRemoval", "legacyReadbackRequestRemoval",
            "legacyReadbackResponseRemoval", "legacyTransition", "update", "pairing",
            "support", "readback", "formalInput", "activation", "finalSupport",
            "pairCreate", "pairDelivery", "readbackPublish", "readbackLaunch", "readbackStop", "formalLaunch",
        }
        if any(value["stages"].get(name, {"state": "pending"})["state"] != "pending" for name in forbidden):
            raise _failure("transaction-conflict")

    def freeze_command(
        self, action: str, raw: bytes, *, revision: int | None = None,
        prior_response: bytes | None = None, actual_pid: int | None = None,
    ) -> dict[str, Any]:
        """Freeze one exact App control command before any publication attempt."""
        value = self._required()
        if self.is_terminal(value):
            raise _failure("transaction-conflict")
        request_raw = self._evidence_bytes(value, "appRequest")
        _control_bytes(raw, action, request_raw)
        current_revision = len(value["revisions"]) - 1
        if revision is not None and (type(revision) is not int or revision != current_revision):
            raise _failure("revision-conflict")
        record = self._command_record(value, action)
        evidence_name = action + "Command"
        if evidence_name in value["evidence"]:
            if self._evidence_bytes(value, evidence_name) != raw:
                raise _failure("transaction-conflict")
            return value

        commands = _commands(value)
        if action == "seal":
            quiesce = commands["quiesce"]["attempts"]
            if not quiesce or quiesce[-1]["state"] not in {
                "confirmed", "inflight", "unknown", "absentAfterReconcile",
            }:
                raise _failure("transaction-conflict")
            if value["stages"]["mutationIntent"]["state"] == "pending":
                raise _failure("transaction-conflict")
            if quiesce[-1]["state"] != "confirmed":
                if prior_response is None or type(actual_pid) is not int or actual_pid <= 0:
                    raise _failure("transaction-conflict")
                parsed, response_pid = _typed_source_response(
                    prior_response, {"ready", "mutationSealed"}, request_raw,
                )
                if response_pid != actual_pid:
                    raise _failure("identity-mismatch")
                if value["sourceAdmission"] != "live" or "sourceAdmission" not in value["evidence"]:
                    raise _failure("identity-mismatch")
                admission = _parse_object(
                    self._evidence_bytes(value, "sourceAdmission"),
                    limit=EVIDENCE_LIMITS["sourceAdmission"],
                )
                if admission.get("sourcePID") != actual_pid:
                    raise _failure("identity-mismatch")
                if parsed.get("phase") == "ready":
                    self._put_evidence(value, "sourceReceipt", prior_response)
                    for attempt in quiesce:
                        if attempt["state"] in {"inflight", "unknown", "absentAfterReconcile"}:
                            attempt["state"] = "confirmed"
        elif action == "release":
            # The narrow pre-ready exception is a same-operation cancellation
            # only.  It cannot follow a sealed source or any submitted effect.
            self._release_command_gate(value)

        if "commands" not in value:
            value["commands"] = {name: {"attempts": []} for name in CONTROL_ACTIONS}
            record = value["commands"][action]
        self._put_evidence(value, evidence_name, raw)
        return self._write(value)

    def begin_publication(
        self, action: str, raw: bytes | None = None, *, revision: int | None = None,
    ) -> dict[str, Any]:
        """Durably append an inflight command publication attempt."""
        value = self._required()
        if self.is_terminal(value) or action not in CONTROL_ACTIONS:
            raise _failure("transaction-conflict")
        if action == "release":
            self._release_command_gate(value)
        evidence_name = action + "Command"
        command = self._evidence_bytes(value, evidence_name)
        if raw is not None and raw != command:
            raise _failure("transaction-conflict")
        command_sha = hashlib.sha256(command).hexdigest()
        record = self._command_record(value, action)
        attempts = record["attempts"]
        if attempts:
            original_revision = attempts[0]["revision"]
            if revision is not None and revision != original_revision:
                raise _failure("revision-conflict")
            last = attempts[-1]
            if last["commandSHA256"] != command_sha:
                raise _failure("transaction-conflict")
            if last["state"] in {"inflight", "confirmed"}:
                return value
            if last["state"] == "supersededByRelease":
                raise _failure("transaction-conflict")
            if last["state"] == "unknown":
                raise _failure("transaction-conflict")
            revision = original_revision
        else:
            if revision is None:
                revision = len(value["revisions"]) - 1
            if type(revision) is not int or not 0 <= revision < len(value["revisions"]):
                raise _failure("revision-conflict")
        if len(attempts) >= MAX_CONTROL_ATTEMPTS:
            raise _failure("revision-conflict")
        attempts.append({"attempt": len(attempts) + 1, "revision": revision,
                         "commandSHA256": command_sha, "state": "inflight"})
        value["outcome"] = "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def reconcile_command_absence(
        self, action: str, *, revision: int | None = None, fresh_absent: bool = False,
    ) -> dict[str, Any]:
        """Record an explicit Resume read proving the fixed mailbox absent."""
        value = self._required()
        if action not in CONTROL_ACTIONS or not fresh_absent:
            raise _failure("transaction-conflict")
        attempts = self._command_record(value, action)["attempts"]
        if not attempts or attempts[-1]["state"] != "unknown":
            raise _failure("transaction-conflict")
        if revision is not None and revision != attempts[-1]["revision"]:
            raise _failure("revision-conflict")
        attempts[-1]["state"] = "absentAfterReconcile"
        value["outcome"] = "unknown"
        return self._write(value)

    def mark_absent_after_reconcile(
        self, action: str, *, revision: int | None = None, fresh_absent: bool = False,
    ) -> dict[str, Any]:
        return self.reconcile_command_absence(action, revision=revision, fresh_absent=fresh_absent)

    def confirm_command(self, action: str, response: bytes, *, actual_pid: int | None = None) -> dict[str, Any]:
        """Confirm a command only from its exact typed durable App response."""
        value = self._required()
        if action not in CONTROL_ACTIONS or not isinstance(response, bytes) or not response:
            raise _failure("invalid-request")
        attempts = self._command_record(value, action)["attempts"]
        if not attempts:
            raise _failure("transaction-conflict")
        latest = attempts[-1]
        if latest["state"] == "confirmed":
            evidence_name = {"quiesce": "sourceReceipt", "seal": "sealedReceipt", "release": "releasedReceipt"}[action]
            if evidence_name in value["evidence"] and self._evidence_bytes(value, evidence_name) == response:
                return value
            raise _failure("transaction-conflict")
        if latest["state"] not in {"inflight", "unknown", "absentAfterReconcile"}:
            raise _failure("transaction-conflict")
        if action == "release":
            self._release_command_gate(value)
        request_raw = self._evidence_bytes(value, "appRequest")
        parsed, response_pid = _control_response(response, action, request_raw)
        if type(actual_pid) is not int or actual_pid <= 0 or actual_pid != response_pid:
            raise _failure("identity-mismatch")
        if value["sourceAdmission"] != "live" or "sourceAdmission" not in value["evidence"]:
            raise _failure("identity-mismatch")
        try:
            admission = _parse_object(self._evidence_bytes(value, "sourceAdmission"), limit=EVIDENCE_LIMITS["sourceAdmission"])
        except ManagementBridgeError:
            raise _failure("identity-mismatch") from None
        if admission.get("sourcePID") != actual_pid:
            raise _failure("identity-mismatch")
        evidence_name = {"quiesce": "sourceReceipt", "seal": "sealedReceipt", "release": "releasedReceipt"}[action]
        self._put_evidence(value, evidence_name, response)
        latest["state"] = "confirmed"
        if action == "seal":
            # A durable mutationSealed phase is strictly later than ready and
            # can reconcile a prior unknown quiesce command.  It never creates
            # a source-ready claim when no quiesce command was submitted.
            for attempt in _commands(value)["quiesce"]["attempts"]:
                if attempt["state"] in {"inflight", "unknown", "absentAfterReconcile"}:
                    attempt["state"] = "confirmed"
        elif action == "release":
            # Release is the only approved same-operation replacement that may
            # close an unresolved quiesce publication.  Preserve every attempt
            # and retain the terminal superseded audit state.
            for attempt in _commands(value)["quiesce"]["attempts"]:
                if attempt["state"] != "supersededByRelease":
                    attempt["state"] = "supersededByRelease"
        value["outcome"] = "unknown" if self._outstanding(value) else "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def _legacy_removal_gate(self, value: Mapping[str, Any], stage: str) -> dict[str, Any]:
        evidence_name = _LEGACY_REMOVAL_EVIDENCE.get(stage)
        if evidence_name is None:
            raise _failure("invalid-request")
        stages = value["stages"]
        if (stages["legacy"]["state"] != "confirmed" or
                stages["legacy"]["evidence"] != "legacyInventory" or
                stages["mutationIntent"]["state"] != "confirmed" or
                stages["sourceStop"]["state"] != "confirmed" or
                value["sourceAdmission"] not in {"live", "cold"}):
            raise _failure("transaction-conflict")
        if value["sourceAdmission"] == "live":
            if stages["sourceSeal"]["state"] != "confirmed":
                raise _failure("transaction-conflict")
        elif stages["sourceSeal"]["state"] != "pending":
            raise _failure("transaction-conflict")
        self._check_evidence(value)
        try:
            return self._parse_legacy_inventory(self._evidence_bytes(value, "legacyInventory"))
        except ManagementBridgeError:
            raise _failure("transaction-conflict") from None

    def _legacy_transition_gate(self, value: Mapping[str, Any]) -> None:
        if (value["stages"]["legacy"]["state"] != "confirmed" or
                any(value["stages"][name]["state"] != "confirmed"
                    for name in _LEGACY_REMOVAL_EVIDENCE) or
                "legacyInventory" not in value["evidence"]):
            raise _failure("transaction-conflict")
        self._legacy_removal_gate(value, "legacyIncomingRemoval")

    @staticmethod
    def _publication_revision(value: Mapping[str, Any], revision: int | None) -> int:
        current_revision = len(value["revisions"]) - 1
        if revision is None:
            return current_revision
        if type(revision) is not int or not 0 <= revision < len(value["revisions"]):
            raise _failure("revision-conflict")
        return revision

    @staticmethod
    def _publication_record(value: Mapping[str, Any]) -> dict[str, Any] | None:
        return _readback_publication(value)

    def _append_readback_publication(self, value: dict[str, Any], *, revision: int | None = None) -> None:
        """Append one durable intent for the exact frozen readbackPlan bytes."""
        if self.is_terminal(value):
            raise _failure("transaction-conflict")
        stage = value["stages"].get("readbackPublish")
        if not isinstance(stage, dict):
            raise _failure("transaction-conflict")
        plan = value["evidence"].get("readbackPlan")
        if not isinstance(plan, dict):
            raise _failure("transaction-conflict")
        target_revision = self._publication_revision(value, revision)
        request_sha = plan["sha256"]
        record = self._publication_record(value)
        if record is None:
            if stage["state"] != "pending":
                # Component journals written before publication attempts have
                # no retry authority.  An exact request may still be
                # reconciled by the caller through the normal stage confirm.
                raise _failure("transaction-conflict")
            record = {"attempts": [], "exhausted": False}
            value["publications"] = {"readbackPublish": record}
        if record["exhausted"]:
            raise _failure("revision-conflict")
        attempts = record["attempts"]
        if attempts:
            original_revision = attempts[0]["revision"]
            if target_revision != original_revision:
                raise _failure("revision-conflict")
            latest = attempts[-1]
            if latest["requestSHA256"] != request_sha:
                raise _failure("transaction-conflict")
            if latest["state"] in {"inflight", "confirmed"}:
                # A durable inflight intent is not permission to enter the
                # effect again, and a confirmed attempt has no retry path.
                raise _failure("transaction-conflict")
            if latest["state"] == "unknown":
                # Unknown publication is never retried without an explicit
                # fresh fixed-file absence reconciliation.
                raise _failure("transaction-conflict")
            if latest["state"] != "absentAfterReconcile":
                raise _failure("transaction-conflict")
        elif stage["state"] != "pending":
            raise _failure("transaction-conflict")
        if len(attempts) >= MAX_CONTROL_ATTEMPTS:
            record["exhausted"] = True
            self._write(value)
            raise _failure("revision-conflict")
        previous = attempts[-1]["state"] if attempts else None
        attempts.append({
            "number": len(attempts) + 1,
            "revision": target_revision,
            "requestSHA256": request_sha,
            "state": "inflight",
            "recordedAt": _utc_timestamp(),
            "priorOutcome": previous,
            "terminalReason": None,
        })
        stage["state"] = "inflight"
        stage["revision"] = target_revision
        stage["evidence"] = None
        value["outcome"] = "inProgress"
        value["errorCode"] = None

    def begin_readback_publication(self, *, revision: int | None = None) -> dict[str, Any]:
        """Persist readback publication intent before calling the adapter."""
        value = self._required()
        self._append_readback_publication(value, revision=revision)
        return self._write(value)

    def reconcile_readback_absence(
        self, *, fresh_absent: bool = False, revision: int | None = None,
    ) -> dict[str, Any]:
        """Close an unknown attempt only after explicit fresh fixed-file absence."""
        value = self._required()
        if not fresh_absent:
            raise _failure("transaction-conflict")
        record = self._publication_record(value)
        if record is None or not record["attempts"] or record["exhausted"]:
            raise _failure("transaction-conflict")
        latest = record["attempts"][-1]
        if latest["state"] != "unknown":
            raise _failure("transaction-conflict")
        if revision is not None and revision != latest["revision"]:
            raise _failure("revision-conflict")
        latest["state"] = "absentAfterReconcile"
        latest["terminalReason"] = "absent-on-explicit-resume"
        value["outcome"] = "unknown"
        return self._write(value)

    def exhaust_readback_publication(self, *, revision: int | None = None) -> dict[str, Any]:
        """Durably retain the bounded retry limit without creating another attempt."""
        value = self._required()
        record = self._publication_record(value)
        if record is None or not record["attempts"]:
            raise _failure("transaction-conflict")
        latest = record["attempts"][-1]
        if revision is not None and revision != latest["revision"]:
            raise _failure("revision-conflict")
        if len(record["attempts"]) < MAX_CONTROL_ATTEMPTS:
            raise _failure("revision-conflict")
        record["exhausted"] = True
        if latest["state"] == "unknown":
            latest["terminalReason"] = "attempt-limit"
        value["outcome"] = "unknown"
        return self._write(value)

    def mark_readback_publication_unknown(self, code: str = "publication-interrupted") -> dict[str, Any]:
        value = self._required()
        record = self._publication_record(value)
        if record is None or not record["attempts"]:
            raise _failure("transaction-conflict")
        latest = record["attempts"][-1]
        if latest["state"] not in {"inflight", "unknown"}:
            raise _failure("transaction-conflict")
        latest["state"] = "unknown"
        latest["terminalReason"] = "publication-interrupted"
        value["stages"]["readbackPublish"]["state"] = "unknown"
        value["stages"]["readbackPublish"]["revision"] = latest["revision"]
        value["stages"]["readbackPublish"]["evidence"] = None
        value["outcome"] = "unknown"
        value["errorCode"] = code if code in SAFE_ERROR_CODES else "operation-failed"
        return self._write(value)

    def confirm_readback_publication(self, evidence: str = "readbackPlan") -> dict[str, Any]:
        """Close the latest attempt from the caller's exact readonly match."""
        value = self._required()
        record = self._publication_record(value)
        if record is None:
            # Component journals written before the bounded attempt ledger
            # may still close an exact readonly request.  They have no retry
            # authority, so this delegates only to the existing stage proof.
            return self.confirm("readbackPublish", evidence)
        if not record["attempts"]:
            raise _failure("transaction-conflict")
        latest = record["attempts"][-1]
        if latest["state"] == "confirmed":
            if value["stages"]["readbackPublish"]["state"] == "confirmed":
                return value
            raise _failure("transaction-conflict")
        if latest["state"] not in {"inflight", "unknown", "absentAfterReconcile"}:
            raise _failure("transaction-conflict")
        if evidence not in value["evidence"]:
            raise _failure("transaction-conflict")
        latest["state"] = "confirmed"
        latest["terminalReason"] = "exact-request-observed"
        value["stages"]["readbackPublish"]["state"] = "confirmed"
        value["stages"]["readbackPublish"]["revision"] = latest["revision"]
        value["stages"]["readbackPublish"]["evidence"] = evidence
        value["outcome"] = "unknown" if self._outstanding(value) else "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def record_intent(self, stage: str) -> dict[str, Any]:
        value = self._required()
        if stage not in STAGES or stage == "complete" or self.is_terminal(value):
            raise _failure("transaction-conflict")
        if stage == "readbackPublish":
            state = value["stages"][stage]["state"]
            publication = self._publication_record(value)
            retry_after_absence = (
                state == "unknown" and publication is not None and publication["attempts"] and
                publication["attempts"][-1]["state"] == "absentAfterReconcile"
            )
            if state != "pending" and not retry_after_absence:
                raise _failure("transaction-conflict")
            self._append_readback_publication(value)
            return self._write(value)
        if value["stages"][stage]["state"] != "pending":
            raise _failure("transaction-conflict")
        if stage in _LEGACY_REMOVAL_EVIDENCE:
            self._legacy_removal_gate(value, stage)
        elif stage == "legacyTransition":
            self._legacy_transition_gate(value)
        value["stages"][stage] = {"state": "inflight", "revision": len(value["revisions"]) - 1, "evidence": None}
        value["outcome"] = "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def confirm(
        self, stage: str, evidence: str | bytes | None = None, *,
        response: bytes | None = None, actual_pid: int | None = None,
    ) -> dict[str, Any]:
        if stage in CONTROL_ACTIONS:
            raw_response = response if response is not None else evidence
            if not isinstance(raw_response, bytes):
                raise _failure("invalid-request")
            return self.confirm_command(stage, raw_response, actual_pid=actual_pid)
        value = self._required()
        if (stage not in STAGES or stage in {"complete", "release"} or
                value["stages"][stage]["state"] not in {"inflight", "unknown"} or
                (evidence is not None and evidence not in value["evidence"])):
            raise _failure("transaction-conflict")
        if stage in _LEGACY_REMOVAL_EVIDENCE:
            inventory = self._legacy_removal_gate(value, stage)
            evidence_name = _LEGACY_REMOVAL_EVIDENCE[stage]
            expected = evidence_name if inventory["entries"][evidence_name]["present"] else "legacyInventory"
            if evidence != expected:
                raise _failure("transaction-conflict")
        elif stage == "legacyTransition":
            self._legacy_transition_gate(value)
            if evidence != "legacyInventory":
                raise _failure("transaction-conflict")
        elif stage == "readbackPublish" and self._publication_record(value) is not None:
            record = self._publication_record(value)
            if not record or not record["attempts"]:
                raise _failure("transaction-conflict")
            latest = record["attempts"][-1]
            if latest["state"] not in {"inflight", "unknown", "absentAfterReconcile", "confirmed"}:
                raise _failure("transaction-conflict")
            if latest["state"] != "confirmed":
                latest["state"] = "confirmed"
                latest["terminalReason"] = "exact-request-observed"
        value["stages"][stage]["state"] = "confirmed"
        value["stages"][stage]["evidence"] = evidence
        value["outcome"] = "unknown" if self._outstanding(value) else "inProgress"
        value["errorCode"] = None
        return self._write(value)

    def mark_unknown(self, stage: str, code: str = "operation-failed") -> dict[str, Any]:
        if stage in CONTROL_ACTIONS:
            value = self._required()
            attempts = self._command_record(value, stage)["attempts"]
            if not attempts or attempts[-1]["state"] not in {"inflight", "unknown"}:
                raise _failure("transaction-conflict")
            attempts[-1]["state"] = "unknown"
            value["outcome"] = "unknown"
            value["errorCode"] = code if code in SAFE_ERROR_CODES else "operation-failed"
            return self._write(value)
        value = self._required()
        if stage not in STAGES or value["stages"][stage]["state"] not in {"inflight", "unknown"}:
            raise _failure("transaction-conflict")
        if stage == "readbackPublish" and self._publication_record(value) is not None:
            record = self._publication_record(value)
            if not record or not record["attempts"]:
                raise _failure("transaction-conflict")
            latest = record["attempts"][-1]
            if latest["state"] not in {"inflight", "unknown"}:
                raise _failure("transaction-conflict")
            latest["state"] = "unknown"
            latest["terminalReason"] = "publication-interrupted"
        value["stages"][stage]["state"] = "unknown"
        value["outcome"] = "unknown"
        value["errorCode"] = code if code in SAFE_ERROR_CODES else "operation-failed"
        return self._write(value)

    markUnknown = mark_unknown

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
        if any(stage["state"] in {"inflight", "unknown"} for stage in value["stages"].values()):
            return True
        if any(
            action + "Command" in value["evidence"] and not record["attempts"]
            for action, record in _commands(value).items()
        ):
            return True
        if any(
            attempt["state"] in {"inflight", "unknown", "absentAfterReconcile"}
            for record in _commands(value).values()
            for attempt in record["attempts"]
        ):
            return True
        publication = _readback_publication(value)
        if publication and publication["attempts"]:
            # Older absent attempts are audit only.  Only the latest unknown
            # or inflight publication remains native authority.
            return publication["attempts"][-1]["state"] in {"inflight", "unknown"}
        return False

    def append_revision(self, selection_id: str, transport: str) -> dict[str, Any]:
        value = self._required()
        _uuid(selection_id)
        if transport not in {"USB", "Network"} or self.is_terminal(value):
            raise _failure("revision-conflict")
        if transport != value["revisions"][-1]["transport"] and self._outstanding(value):
            raise _failure("revision-conflict")
        consumed = self.find_selection(selection_id)
        associations = _selections(value)
        number = len(value["revisions"]) - 1
        if consumed is not None:
            if (consumed != value["header"] or value["revisions"][-1]["transport"] != transport or
                    {"selectionID": selection_id, "revision": number} not in associations):
                raise _failure("revision-conflict")
            return value
        if len(associations) >= MAX_SELECTIONS:
            raise _failure("revision-conflict")
        if value["revisions"][-1]["transport"] != transport:
            if len(value["revisions"]) >= MAX_REVISIONS:
                raise _failure("revision-conflict")
            number += 1
            value["revisions"].append({"number": number, "selectionID": selection_id, "transport": transport,
                                   "previous": number - 1,
                                   "resolvedThroughSHA256": hashlib.sha256(_encoded(value["stages"])).hexdigest()})
        value["selections"] = associations + [{"selectionID": selection_id, "revision": number}]
        return self._write(value)

    def release(self) -> dict[str, Any]:
        value = self._required()
        if value["stages"]["release"]["state"] == "confirmed":
            return value
        outstanding = any(stage["state"] in {"inflight", "unknown"}
                          for name, stage in value["stages"].items() if name != "release")
        outstanding = outstanding or any(
            attempt["state"] in {"inflight", "unknown", "absentAfterReconcile"}
            for action, record in _commands(value).items() if action != "release"
            for attempt in record["attempts"]
        )
        if value["stages"]["mutationIntent"]["state"] != "pending" or outstanding:
            raise _failure("transaction-conflict")
        release_attempts = _commands(value)["release"]["attempts"]
        if release_attempts and release_attempts[-1]["state"] != "confirmed":
            raise _failure("transaction-conflict")
        if "releaseCommand" in value["evidence"] and (
                not release_attempts or release_attempts[-1]["state"] != "confirmed" or
                "releasedReceipt" not in value["evidence"]):
            raise _failure("transaction-conflict")
        if value["stages"]["sourceRequest"]["state"] != "pending" and (
                (not release_attempts and value["stages"]["release"]["state"] not in {"inflight", "unknown"}) or
                "releasedReceipt" not in value["evidence"]):
            raise _failure("transaction-conflict")
        if release_attempts and "releasedReceipt" not in value["evidence"]:
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
        # Read the immutable blobs before making the terminal transition.  In
        # particular, a launchless recovery must validate the exact pinned
        # response and pairing binding rather than relying on stage metadata.
        blobs = {name: self._evidence_bytes(value, name) for name in value["evidence"]}
        if self._outstanding(value) or not _completion_ready(value, blobs):
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
