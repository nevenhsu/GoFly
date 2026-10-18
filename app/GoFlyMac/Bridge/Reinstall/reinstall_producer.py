"""Bounded protocol-3 reinstall producer.

This coordinator owns ordering and durable authority.  It does not manufacture
device, process, App, or native proof; every irreversible transition is backed
by an adapter observation and a journal checkpoint.
"""

from __future__ import annotations

import contextlib
import copy
import hashlib
import json
import os
import re
import stat
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

try:
    from ..Setup.setup_adapters import ArtifactIdentity, FormalArtifactValidator
    from ..Setup.setup_journal import JournalStore
    from ..Setup.setup_protocol import SetupBridgeError, SetupOptions, SetupRequest, TARGET_BUNDLE_ID, TARGET_NAME
except ImportError:  # direct execution from packaged Reinstall directory
    from Setup.setup_adapters import ArtifactIdentity, FormalArtifactValidator
    from Setup.setup_journal import JournalStore
    from Setup.setup_protocol import SetupBridgeError, SetupOptions, SetupRequest, TARGET_BUNDLE_ID, TARGET_NAME

from .reinstall_adapters import (
    ExportReadback,
    InstallObservation,
    ReinstallDeviceAdapter,
    ReinstallProcessAdapter,
    SourceAppIdentity,
    SwiftTransferValidator,
    TransferValidator,
)
from .reinstall_journal import ReinstallJournalStore, is_completed_journal, is_terminal_journal
from .reinstall_protocol import CATEGORY_ORDER, ReinstallBridgeError, ReinstallOptions, ReinstallRequest

_HEX64 = re.compile(r"[0-9a-f]{64}\Z")
_UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
_SOURCE_STAGES = ("sourceRequest", "sourceReady")
_PROOF_KEYS = (
    "backupValidated", "sourceSealed", "removalConfirmed", "installationConfirmed",
    "pairingImported", "supportObserved", "restoreCommitted",
)
_COUNT_LIMITS = {
    "favorites": 100,
    "importedRoutes": 100,
    "favoriteRoutes": 100,
    "draftNodes": 27,
    "gpxPoints": 2_010_000,
}


def _uuid() -> str:
    return str(uuid.uuid4())


def _hash_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _journal_digest(value: Mapping[str, Any]) -> str:
    """Stable digest for the loaded predecessor record.

    The M1 store has already validated the authoritative bytes before this
    producer is called.  Its canonical object digest binds the predecessor
    identity into the new parent journal without copying any path authority.
    """
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return _hash_bytes(raw)


def _error_code(error: BaseException, default: str = "operation-failed") -> str:
    code = getattr(error, "code", None)
    return code if isinstance(code, str) else default


def _mapping(value: Any) -> Mapping[str, Any] | None:
    return value if isinstance(value, Mapping) else None


class _EmbeddedSetupPort:
    """Private M1 journal port nested in the M2 parent transaction.

    The protocol-2 stage code is intentionally reused through its private
    producer methods, but its public ``apply``/``resume`` entry points are not
    called: they would acquire a second lease and consult the standalone M1
    journal.  Every update here validates the full M1 record and checkpoints
    the enclosing M2 journal while the caller holds the one global lease.
    """

    def __init__(self, parent_store: ReinstallJournalStore, parent: dict[str, Any]):
        self.parent_store = parent_store
        self.parent = parent

    def read(self) -> dict[str, Any] | None:
        setup = self.parent.get("setup")
        return copy.deepcopy(dict(setup)) if isinstance(setup, Mapping) else None

    def update(self, setup: Mapping[str, Any]) -> dict[str, Any]:
        value = copy.deepcopy(dict(setup))
        JournalStore._validate(value)
        if value.get("setupID") != self.parent.get("setupID") or value.get("deviceID") != self.parent.get("deviceID"):
            raise SetupBridgeError("transaction-conflict")
        self.parent["setup"] = value
        self.parent = self.parent_store.update(self.parent)
        return copy.deepcopy(value)

    def checkpoint(
        self,
        setup: Mapping[str, Any],
        stage: str,
        state: str,
        *,
        proof: Mapping[str, bool] | None = None,
        detail: str | None = None,
    ) -> dict[str, Any]:
        if stage not in {"artifact", "pairing", "install", "support", "handoff", "complete"}:
            raise SetupBridgeError("storage-unavailable")
        value = copy.deepcopy(dict(setup))
        JournalStore._validate(value)
        if state not in {"pending", "inflight", "confirmed", "unknown", "failed"}:
            raise SetupBridgeError("storage-unavailable")
        value["stages"][stage] = {"state": state}
        if detail is not None:
            value["stages"][stage]["detail"] = str(detail)[:160]
        if proof is not None:
            for key in ("installationConfirmed", "pairingImported", "supportObserved"):
                if key in proof:
                    if type(proof[key]) is not bool:
                        raise SetupBridgeError("storage-unavailable")
                    value["proof"][key] = proof[key]
        return self.update(value)

    def transaction_root(self, setup_id: str) -> Path:
        if setup_id != self.parent.get("setupID"):
            raise SetupBridgeError("transaction-conflict")
        # This is the existing M1 artifact/support location.  No M1 journal
        # is created there; the parent remains the only current authority.
        return JournalStore(self.parent_store.root).transaction_root(setup_id)

    def bind_parent(self, parent: dict[str, Any]) -> None:
        self.parent = parent


@dataclass(frozen=True)
class ReinstallPayload:
    stage: str
    outcome: str
    can_resume: bool
    can_abandon: bool
    proof: Mapping[str, bool]
    categories: tuple[Mapping[str, Any], ...] = ()
    counts: Mapping[str, int] | None = None
    app: Mapping[str, Any] | None = None
    team_id: str | None = None
    expires_at: str | None = None
    receipt_sha256: str | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "stage": self.stage,
            "outcome": self.outcome,
            "canResume": self.can_resume,
            "canAbandon": self.can_abandon,
            "proof": {key: self.proof.get(key) is True for key in _PROOF_KEYS},
            "categories": [dict(item) for item in self.categories],
            "counts": dict(self.counts) if self.counts is not None else None,
        }
        if self.app is not None:
            value["app"] = dict(self.app)
        if self.team_id is not None:
            value["teamID"] = self.team_id
        if self.expires_at is not None:
            value["expiresAt"] = self.expires_at
        if self.receipt_sha256 is not None:
            value["receiptSHA256"] = self.receipt_sha256
        return value


class ReinstallProducer:
    """One transaction coordinator for preflight/apply/status/resume/abandon."""

    def __init__(
        self,
        config: Any,
        *,
        store: ReinstallJournalStore | None = None,
        device: ReinstallDeviceAdapter,
        process: ReinstallProcessAdapter | None = None,
        artifact_validator: Any | None = None,
        support: Any | None = None,
        validator: TransferValidator | None = None,
    ):
        self.config = config
        self.store = store or ReinstallJournalStore(config.state_root)
        self.device = device
        self.process = process
        self.artifact_validator = artifact_validator or FormalArtifactValidator()
        self.support = support
        self.validator = validator or SwiftTransferValidator(config.validator_path)

    def handle(self, request: ReinstallRequest) -> ReinstallPayload:
        if request.action == "preflight":
            return self.preflight(request)
        if request.action == "apply":
            return self.apply(request)
        if request.action == "status":
            return self.status(request)
        if request.action == "resume":
            return self.resume(request)
        if request.action == "abandon":
            return self.abandon(request)
        raise ReinstallBridgeError("invalid-request")

    def preflight(self, request: ReinstallRequest) -> ReinstallPayload:
        options = request.options
        if options is None:
            raise ReinstallBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        self._guard_m1()
        journal = self.store.read()
        if journal is not None and not self._terminal(journal):
            raise ReinstallBridgeError("transaction-conflict")
        observed = self._observe(request.device_id)
        installed = self.device.installed(request.device_id)
        if not installed.present:
            raise ReinstallBridgeError("transaction-unknown")
        artifact: ArtifactIdentity | None = None
        if options.source == "signedApp":
            if options.artifact_path is None:
                raise ReinstallBridgeError("invalid-request")
            artifact = self.artifact_validator.inspect(options.artifact_path, device_id=request.device_id, team_id=options.team_id)
        return self._payload_preflight(options, artifact=artifact)

    def apply(self, request: ReinstallRequest) -> ReinstallPayload:
        options = request.options
        if options is None:
            raise ReinstallBridgeError("invalid-request")
        self.config.ensure_state_root()
        with self.store.lock():
            self._guard_m1()
            m1_store = JournalStore(self.config.state_root)
            m1 = m1_store.read()
            existing = self.store.read()
            if existing is not None:
                if existing["transferID"] == request.transfer_id or not self._terminal(existing):
                    raise ReinstallBridgeError("transaction-conflict")
                self.store.archive_completed(existing)
            observed = self._observe(request.device_id)
            installed = self.device.installed(request.device_id)
            if not installed.present:
                raise ReinstallBridgeError("transaction-unknown")
            known_source = {"bundleID": TARGET_BUNDLE_ID, "build": self._installed_build(installed)}
            predecessor = None
            if m1 is not None:
                predecessor = {
                    "setupID": m1["setupID"],
                    "deviceID": m1["deviceID"],
                    "rawJournalSHA256": _journal_digest(m1),
                    "archived": False,
                }
            journal = self.store.create(
                request.transfer_id,
                request.device_id,
                data_set_id=_uuid(), nonce=_uuid(), setup_id=_uuid(),
                known_source=known_source,
                options=options.as_dict(),
                predecessor=predecessor,
            )
            if m1 is not None:
                # The parent intent is durable before archiving the proven M1
                # predecessor, both under the one already-held lease.
                m1_store.archive_completed_locked(m1["setupID"], m1["deviceID"])
                journal["predecessor"]["archived"] = True
                journal = self.store.update(journal)
            try:
                journal = self._apply_artifact(journal, request, observed)
                journal = self._export(journal, request)
                journal = self._backup(journal, request)
                journal = self._remove_source(journal, request)
                journal = self._install_target(journal, request)
                journal = self._restore_target(journal, request)
                journal = self._confirm_final_support(journal, request)
                journal["outcome"] = "confirmed"
                journal["stages"]["complete"] = {"state": "confirmed"}
                journal = self.store.update(journal)
                return self._payload_from_journal(journal)
            except (SetupBridgeError, ReinstallBridgeError) as error:
                self._record_failure(journal, error)
                raise ReinstallBridgeError(_error_code(error)) from None
            except Exception as error:
                self._record_failure(journal, error)
                raise ReinstallBridgeError("operation-failed") from None

    def status(self, request: ReinstallRequest) -> ReinstallPayload:
        journal = self.store.read()
        if journal is None:
            raise ReinstallBridgeError("transaction-unknown")
        self._bind(journal, request)
        return self._payload_from_journal(journal)

    def resume(self, request: ReinstallRequest) -> ReinstallPayload:
        with self.store.lock():
            # M1 mutators use the same lease and crossguard; resume keeps the
            # admission symmetric before it touches any source/target seam.
            self._guard_m1()
            journal = self.store.read()
            if journal is None:
                raise ReinstallBridgeError("transaction-unknown")
            predecessor = journal.get("predecessor")
            if isinstance(predecessor, Mapping) and predecessor.get("archived") is False:
                m1_store = JournalStore(self.config.state_root)
                m1 = m1_store.read()
                if m1 is None or m1.get("setupID") != predecessor.get("setupID") or m1.get("deviceID") != predecessor.get("deviceID") or _journal_digest(m1) != predecessor.get("rawJournalSHA256"):
                    raise ReinstallBridgeError("transaction-conflict")
                m1_store.archive_completed_locked(m1["setupID"], m1["deviceID"])
                journal["predecessor"]["archived"] = True
                journal = self.store.update(journal)
            self._bind(journal, request)
            if journal["outcome"] == "confirmed":
                return self._payload_from_journal(journal)
            # An install boundary with a lost result is permanent unknown;
            # do not adopt or resubmit even when lookup shows a matching App.
            if journal["stages"]["install"]["state"] in {"unknown", "inflight"}:
                with contextlib.suppress(Exception):
                    self.device.installed(request.device_id)
                return self._payload_from_journal(journal)
            try:
                if journal["stages"]["sourceReady"]["state"] != "confirmed":
                    journal = self._export(journal, request)
                if journal["stages"]["backup"]["state"] != "confirmed":
                    journal = self._backup(journal, request)
                if journal["stages"]["uninstall"]["state"] != "confirmed":
                    journal = self._remove_source(journal, request)
                if journal["stages"]["install"]["state"] != "confirmed":
                    journal = self._install_target(journal, request)
                if journal["stages"]["restoreReceipt"]["state"] != "confirmed":
                    journal = self._restore_target(journal, request)
                journal = self._confirm_final_support(journal, request)
                journal["stages"]["complete"] = {"state": "confirmed"}
                journal["outcome"] = "confirmed"
                journal = self.store.update(journal)
                return self._payload_from_journal(journal)
            except (SetupBridgeError, ReinstallBridgeError) as error:
                self._record_failure(journal, error)
                raise ReinstallBridgeError(_error_code(error)) from None
            except Exception:
                self._record_failure(journal, ReinstallBridgeError("operation-failed"))
                raise ReinstallBridgeError("operation-failed") from None

    def abandon(self, request: ReinstallRequest) -> ReinstallPayload:
        with self.store.lock():
            self._guard_m1()
            journal = self.store.read()
            if journal is None:
                raise ReinstallBridgeError("transaction-unknown")
            self._bind(journal, request)
            journal = self._reload_bound(journal, request)
            if journal["stages"]["destructiveIntent"]["state"] in {"inflight", "confirmed", "unknown"}:
                raise ReinstallBridgeError("operation-abandoned")
            if journal["outcome"] == "confirmed":
                return self._payload_from_journal(journal)
            journal["stages"]["abandonIntent"] = {"state": "confirmed"}
            journal = self.store.update(journal)
            try:
                phase = journal["stages"]["sourceReady"]["state"]
                manifest = journal.get("rawManifestSHA256") if phase == "confirmed" else None
                source_app = journal.get("sourceApp") if phase == "confirmed" else None
                journal, control = self._prepare_control(
                    journal,
                    slot="release",
                    action="release",
                    manifest=manifest,
                    source=source_app if isinstance(source_app, Mapping) else None,
                )
                journal = self._reload_bound(journal, request)
                self._call("source_release", request.device_id, control)
                release_command = journal["commands"].get("release")
                if not isinstance(release_command, Mapping):
                    raise ReinstallBridgeError("transaction-unknown")
                response = self._read_control_response(journal, request, release_command)
                # A pre-ready null release can race with the source reaching
                # Ready.  The App's Ready+export-conflict observation is not
                # release authority: persist the exact observed binding and
                # issue a new full release command before accepting a receipt.
                if response is not None and response.phase == "ready" and manifest is None:
                    if (
                        response.error_code != "export-conflict"
                        or not isinstance(response.raw_manifest_sha256, str)
                        or not _HEX64.fullmatch(response.raw_manifest_sha256)
                        or response.source_app is None
                    ):
                        response = None
                    else:
                        previous = dict(release_command)
                        history = list(journal.get("history", []))
                        if len(history) >= 128:
                            raise ReinstallBridgeError("storage-unavailable")
                        history.append(
                            {
                                "action": "release",
                                "commandID": previous["commandID"],
                                "controlSHA256": previous["controlSHA256"],
                                "transferID": journal["transferID"],
                                "nonce": journal["nonce"],
                                "requestSHA256": response.request_sha256,
                                "manifestSHA256": response.raw_manifest_sha256,
                                "sourceApp": response.source_app.as_dict(),
                                "phase": "ready",
                                "pid": response.pid,
                                "receiptSHA256": response.receipt_sha256,
                                "errorCode": response.error_code,
                            }
                        )
                        journal["history"] = history
                        journal["sourceApp"] = response.source_app.as_dict()
                        journal["rawManifestSHA256"] = response.raw_manifest_sha256
                        journal["stages"]["sourceReady"] = {"state": "confirmed"}
                        journal = self.store.update(journal)
                        manifest = journal["rawManifestSHA256"]
                        source_app = journal["sourceApp"]
                        journal, control = self._prepare_control(
                            journal,
                            slot="release",
                            action="release",
                            manifest=manifest,
                            source=source_app,
                        )
                        journal = self._reload_bound(journal, request)
                        self._call("source_release", request.device_id, control)
                        release_command = journal["commands"].get("release")
                        if not isinstance(release_command, Mapping):
                            raise ReinstallBridgeError("transaction-unknown")
                        response = self._read_control_response(journal, request, release_command)
                if response is None or response.phase not in {"released", "releasedNoSnapshot"} or response.error_code is not None:
                    journal["stages"]["abandon"]["state"] = "unknown"
                    journal["outcome"] = "unknown"
                    self.store.update(journal)
                    raise ReinstallBridgeError("export-conflict")
                if response.raw_manifest_sha256 != manifest:
                    raise ReinstallBridgeError("export-conflict")
                if source_app is not None and (response.source_app is None or response.source_app.as_dict() != dict(source_app)):
                    raise ReinstallBridgeError("export-conflict")
                journal["commands"]["release"]["sourcePID"] = response.pid
                journal["stages"]["abandon"] = {"state": "confirmed"}
                journal["outcome"] = "confirmed"
                journal["errorCode"] = None
                journal = self.store.update(journal)
                return self._payload_from_journal(journal)
            except ReinstallBridgeError as error:
                current = None
                with contextlib.suppress(Exception):
                    current = self.store.read()
                if isinstance(current, Mapping):
                    value = copy.deepcopy(dict(current))
                    value["stages"]["abandon"]["state"] = "unknown"
                    value["outcome"] = "unknown"
                    value["errorCode"] = _error_code(error)
                    with contextlib.suppress(Exception):
                        self.store.update(value)
                raise
            except Exception as error:
                journal["stages"]["abandon"]["state"] = "unknown"
                journal["outcome"] = "unknown"
                journal["errorCode"] = _error_code(error)
                with contextlib.suppress(Exception):
                    self.store.update(journal)
                raise ReinstallBridgeError(_error_code(error, "operation-failed")) from None

    def _apply_artifact(self, journal: dict[str, Any], request: ReinstallRequest, observed: Any) -> dict[str, Any]:
        options = request.options or ReinstallOptions("project", None, "ABCDEFGHIJ", False, ())
        artifact: ArtifactIdentity | None = None
        if options.source == "signedApp":
            if options.artifact_path is None:
                raise ReinstallBridgeError("invalid-request")
            artifact = self.artifact_validator.inspect(options.artifact_path, device_id=request.device_id, team_id=options.team_id)
        else:
            if self.process is None:
                raise ReinstallBridgeError("environment-not-ready")
            artifact_path = self.process.build(journal["setupID"], options.team_id, options.allow_provisioning_updates)
            artifact = self.artifact_validator.inspect(artifact_path, device_id=request.device_id, team_id=options.team_id)
        journal["targetArtifact"] = self._artifact_dict(artifact)
        journal["stages"]["artifact"] = {"state": "confirmed"}
        return self.store.update(journal)

    @staticmethod
    def _canonical_bytes(value: Mapping[str, Any]) -> bytes:
        try:
            return json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
                allow_nan=False,
            ).encode("utf-8")
        except (TypeError, ValueError, UnicodeError):
            raise ReinstallBridgeError("storage-unavailable") from None

    @classmethod
    def _validate_restore_receipt(
        cls,
        value: Any,
        *,
        expected_intent: Mapping[str, Any],
        selected: Sequence[str],
        expected_counts: Mapping[str, int],
    ) -> Mapping[str, Any]:
        required = {"version", "intent", "categoryReceipts", "sessionSeedSHA256", "counts", "receiptSHA256"}
        if not isinstance(value, Mapping) or set(value) != required or value.get("version") != 1:
            raise ReinstallBridgeError("restore-unknown")
        if value.get("intent") != expected_intent:
            raise ReinstallBridgeError("restore-unknown")
        if not isinstance(value.get("sessionSeedSHA256"), str) or not _HEX64.fullmatch(value["sessionSeedSHA256"]):
            raise ReinstallBridgeError("restore-unknown")
        receipt_sha = value.get("receiptSHA256")
        if not isinstance(receipt_sha, str) or not _HEX64.fullmatch(receipt_sha):
            raise ReinstallBridgeError("restore-unknown")
        categories = value.get("categoryReceipts")
        if not isinstance(categories, list) or len(categories) != len(selected) or [item.get("category") for item in categories if isinstance(item, Mapping)] != list(selected):
            raise ReinstallBridgeError("restore-unknown")
        for category, item in zip(selected, categories):
            if not isinstance(item, Mapping) or set(item) != {"category", "receiptSHA256"} or item.get("category") != category or not isinstance(item.get("receiptSHA256"), str) or not _HEX64.fullmatch(item["receiptSHA256"]):
                raise ReinstallBridgeError("restore-unknown")
        counts = value.get("counts")
        if not isinstance(counts, Mapping) or set(counts) != set(_COUNT_LIMITS) or any(type(counts[key]) is not int or counts[key] < 0 or counts[key] > _COUNT_LIMITS[key] for key in _COUNT_LIMITS) or dict(counts) != dict(expected_counts):
            raise ReinstallBridgeError("restore-unknown")
        canonical = {key: value[key] for key in value if key != "receiptSHA256"}
        if _hash_bytes(cls._canonical_bytes(canonical)) != receipt_sha:
            raise ReinstallBridgeError("restore-unknown")
        return dict(value)

    def _prepare_control(
        self,
        journal: dict[str, Any],
        *,
        slot: str,
        action: str,
        manifest: str | None,
        source: Mapping[str, Any] | None,
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        """Persist one exact control command before crossing the device seam."""
        if action not in {"export", "seal", "release"} or slot not in {"sourceRequest", "seal", "release"}:
            raise ReinstallBridgeError("storage-unavailable")
        if action == "export" and (manifest is not None or source is not None):
            raise ReinstallBridgeError("export-conflict")
        source_value = copy.deepcopy(dict(source)) if isinstance(source, Mapping) else None
        existing = journal.get("commands", {}).get(slot) if isinstance(journal.get("commands"), Mapping) else None
        existing_id = existing.get("commandID") if isinstance(existing, Mapping) else None
        command_id = existing_id if isinstance(existing_id, str) and _UUID_RE.fullmatch(existing_id) else _uuid()

        def control_for(identifier: str) -> tuple[dict[str, Any], str]:
            control: dict[str, Any] = {
                "version": 1,
                "action": action,
                "commandID": identifier,
                "transferID": journal["transferID"],
                "nonce": journal["nonce"],
                "requestSHA256": journal.get("requestSHA256"),
                "manifestSHA256": manifest,
                "sourceApp": source_value,
            }
            return control, _hash_bytes(self._canonical_bytes(control))

        control, control_sha = control_for(command_id)
        new_identity = not isinstance(existing, Mapping)
        if isinstance(existing, Mapping) and (
            existing.get("action") != action or existing.get("controlSHA256") != control_sha
        ):
            # A release may legitimately transition from a null no-snapshot
            # release to the full release once Ready wins.  Every other
            # mismatch means the durable command cannot be reconstructed.
            if slot != "release":
                raise ReinstallBridgeError("export-conflict")
            command_id = _uuid()
            control, control_sha = control_for(command_id)
            new_identity = True
        record: dict[str, Any] = {
            "action": action,
            "commandID": command_id,
            "controlSHA256": control_sha,
        }
        if not new_identity and isinstance(existing, Mapping) and isinstance(existing.get("sourcePID"), int) and existing["sourcePID"] >= 0:
            record["sourcePID"] = existing["sourcePID"]
        if existing != record:
            journal["commands"] = {**journal.get("commands", {}), slot: record}
            journal = self.store.update(journal)
        return journal, control

    @staticmethod
    def _require_control_readback(
        readback: ExportReadback,
        journal: Mapping[str, Any],
        command: Mapping[str, Any],
    ) -> None:
        if (
            readback.transfer_id != journal.get("transferID")
            or readback.data_set_id != journal.get("dataSetID")
            or readback.nonce != journal.get("nonce")
            or readback.command_id != command.get("commandID")
            or readback.action != command.get("action")
            or readback.request_sha256 != journal.get("requestSHA256")
            or type(readback.pid) is not int
            or readback.pid <= 0
            or readback.source_app is None
        ):
            raise ReinstallBridgeError("export-conflict")
        if readback.source_app.bundle_id != TARGET_BUNDLE_ID or not readback.source_app.build or not _HEX64.fullmatch(readback.source_app.profile_sha256) or not _HEX64.fullmatch(readback.source_app.executable_sha256):
            raise ReinstallBridgeError("export-conflict")

    def _read_control_response(
        self,
        journal: dict[str, Any],
        request: ReinstallRequest,
        command: Mapping[str, Any],
    ) -> ExportReadback | None:
        response = self._call("source_readback", request.device_id, request.transfer_id, journal["nonce"])
        readback = self._coerce_readback(response, journal)
        if readback is None:
            return None
        self._require_control_readback(readback, journal, command)
        return readback

    def _export(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        journal = self._reload_bound(journal, request)
        known_source = journal.get("knownSource")
        if not isinstance(known_source, Mapping):
            raise ReinstallBridgeError("export-conflict")
        request_value = {
            "version": 1,
            "transferID": journal["transferID"],
            "dataSetID": journal["dataSetID"],
            "nonce": journal["nonce"],
            "sourceDeviceUDID": journal["deviceID"],
            "destinationDeviceUDID": journal["deviceID"],
            "sourceBundleID": known_source.get("bundleID"),
            "sourceBuild": known_source.get("build"),
            "setupID": journal["setupID"],
            "categories": list(journal["options"]["categories"]),
            "targetApp": self._target_app_from_journal(journal),
        }
        raw = self._canonical_bytes(request_value)
        journal["requestSHA256"] = _hash_bytes(raw)
        transaction = self.store.transaction_root(journal["transferID"])
        self._write_private_idempotent(transaction / "export-request.json", raw)
        command = None
        if journal["stages"]["sourceRequest"]["state"] != "confirmed":
            journal, control = self._prepare_control(
                journal,
                slot="sourceRequest",
                action="export",
                manifest=None,
                source=None,
            )
            journal["stages"]["sourceRequest"] = {"state": "inflight"}
            journal = self.store.update(journal)
            self._call("source_request", request.device_id, request_value, control)
            journal["stages"]["sourceRequest"] = {"state": "confirmed"}
            journal = self.store.update(journal)
        command = journal.get("commands", {}).get("sourceRequest")
        if not isinstance(command, Mapping):
            raise ReinstallBridgeError("transaction-unknown")
        readback = self._read_control_response(journal, request, command)
        if readback is None:
            journal["stages"]["sourceReady"] = {"state": "unknown"}
            journal["outcome"] = "unknown"
            self.store.update(journal)
            raise ReinstallBridgeError("update-required")
        if readback.phase not in {"ready", "preparing"}:
            journal["stages"]["sourceReady"] = {"state": "unknown"}
            journal["outcome"] = "unknown"
            self.store.update(journal)
            raise ReinstallBridgeError("source-busy")
        if readback.transfer_id != journal["transferID"] or readback.data_set_id != journal["dataSetID"] or readback.nonce != journal["nonce"]:
            raise ReinstallBridgeError("export-conflict")
        if readback.source_app.build != known_source.get("build"):
            raise ReinstallBridgeError("export-conflict")
        journal["commands"]["sourceRequest"]["sourcePID"] = readback.pid
        actual_source = readback.source_app.as_dict()
        if journal.get("sourceApp") is not None and journal["sourceApp"] != actual_source:
            raise ReinstallBridgeError("export-conflict")
        if readback.phase == "ready" and not _HEX64.fullmatch(readback.raw_manifest_sha256 or ""):
            raise ReinstallBridgeError("source-busy")
        if readback.phase == "preparing" and readback.raw_manifest_sha256 is not None:
            raise ReinstallBridgeError("export-conflict")
        if journal.get("rawManifestSHA256") is not None and journal["rawManifestSHA256"] != readback.raw_manifest_sha256:
            raise ReinstallBridgeError("export-conflict")
        journal["sourceApp"] = actual_source
        journal["rawManifestSHA256"] = readback.raw_manifest_sha256
        journal["stages"]["sourceReady"] = {"state": "confirmed" if readback.phase == "ready" else "inflight"}
        return self.store.update(journal)

    def _validate_backup_result(
        self,
        journal: Mapping[str, Any],
        result: Any,
        *,
        require_stored: bool,
    ) -> Mapping[str, Any]:
        """Validate a complete immutable validator result against the journal.

        The Swift validator is the only source of package evidence.  A later
        boundary revalidates the same private package and compares every
        immutable field to the already checkpointed result; it never refreshes
        counts or adopts a changed package.
        """
        if not isinstance(result, Mapping) or result.get("version") != 1:
            raise ReinstallBridgeError("backup-invalid")
        expected_source = journal.get("sourceApp")
        expected_target = self._target_app_from_journal(journal)
        expected_categories = list(journal["options"]["categories"])
        immutable = (
            ("transferID", journal.get("transferID")),
            ("dataSetID", journal.get("dataSetID")),
            ("nonce", journal.get("nonce")),
            ("sourceDeviceUDID", journal.get("deviceID")),
            ("destinationDeviceUDID", journal.get("deviceID")),
            ("sourceApp", expected_source),
            ("targetApp", expected_target),
            ("setupID", journal.get("setupID")),
            ("categories", expected_categories),
            ("rawManifestSHA256", journal.get("rawManifestSHA256")),
        )
        if any(result.get(key) != expected for key, expected in immutable):
            raise ReinstallBridgeError("backup-invalid")
        counts = result.get("counts")
        if (
            not isinstance(counts, Mapping)
            or set(counts) != set(_COUNT_LIMITS)
            or any(type(counts[key]) is not int or counts[key] < 0 or counts[key] > _COUNT_LIMITS[key] for key in _COUNT_LIMITS)
            or ("favorites" not in expected_categories and counts["favorites"] != 0)
            or ("routes" not in expected_categories and any(counts[key] != 0 for key in ("importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints")))
        ):
            raise ReinstallBridgeError("backup-invalid")
        if require_stored:
            stored_counts = journal.get("counts")
            stored_backup = journal.get("backup")
            if not isinstance(stored_counts, Mapping) or dict(counts) != dict(stored_counts):
                raise ReinstallBridgeError("backup-invalid")
            if (
                not isinstance(stored_backup, Mapping)
                or set(stored_backup) != {"dataSetID", "rawManifestSHA256", "inventory", "counts"}
                or stored_backup.get("dataSetID") != result.get("dataSetID")
                or stored_backup.get("rawManifestSHA256") != result.get("rawManifestSHA256")
                or stored_backup.get("counts") != dict(counts)
            ):
                raise ReinstallBridgeError("backup-invalid")
            inventory = stored_backup.get("inventory")
            if not isinstance(inventory, Mapping) or inventory.get("categories") != expected_categories:
                raise ReinstallBridgeError("backup-invalid")
        return result

    def _revalidate_backup(self, journal: Mapping[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        """Reopen and revalidate the private package before a physical boundary."""
        current = self._reload_bound(journal, request)
        if current["stages"]["backup"]["state"] != "confirmed" or current.get("proof", {}).get("backupValidated") is not True:
            raise ReinstallBridgeError("backup-invalid")
        backup = self.store.transaction_root(current["transferID"]) / "backup"
        try:
            result = self.validator.validate(backup)
        except ReinstallBridgeError:
            raise ReinstallBridgeError("backup-invalid") from None
        except Exception:
            raise ReinstallBridgeError("backup-invalid") from None
        self._validate_backup_result(current, result, require_stored=True)
        return current

    def _backup(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        journal = self._reload_bound(journal, request)
        if journal["stages"]["sourceReady"]["state"] != "confirmed":
            raise ReinstallBridgeError("source-busy")
        journal["stages"]["backup"] = {"state": "inflight"}
        journal = self.store.update(journal)
        command = journal.get("commands", {}).get("sourceRequest")
        if not isinstance(command, Mapping):
            raise ReinstallBridgeError("transaction-unknown")
        readback = self._read_control_response(journal, request, command)
        if readback is None:
            raise ReinstallBridgeError("backup-invalid")
        transaction = self.store.transaction_root(journal["transferID"])
        backup = transaction / "backup"
        # The control readback carries no payload authority.  The adapter
        # must copy through the real device boundary into this exact private
        # transaction directory; arbitrary local package paths are rejected.
        journal = self._reload_bound(journal, request)
        copier = getattr(self.device, "copy_source_package", None)
        if not callable(copier):
            raise ReinstallBridgeError("backup-invalid")
        try:
            copier(request.device_id, request.transfer_id, backup)
        except ReinstallBridgeError:
            raise
        except Exception:
            raise ReinstallBridgeError("backup-invalid") from None
        try:
            validated = self.validator.validate(backup)
        except ReinstallBridgeError:
            raise
        except Exception:
            raise ReinstallBridgeError("backup-invalid") from None
        result = self._validate_backup_result(journal, validated, require_stored=False)
        counts = result["counts"]
        journal["counts"] = dict(counts)
        journal["backup"] = {
            "dataSetID": result["dataSetID"],
            "rawManifestSHA256": result["rawManifestSHA256"],
            "inventory": {"categories": list(result["categories"])},
            "counts": dict(counts),
        }
        journal["proof"] = {**journal.get("proof", {}), "backupValidated": True}
        journal["stages"]["backup"] = {"state": "confirmed"}
        journal["outcome"] = "inProgress"
        return self.store.update(journal)

    def _remove_source(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        journal = self._reload_bound(journal, request)
        if journal["stages"]["backup"]["state"] != "confirmed":
            raise ReinstallBridgeError("backup-invalid")
        # Reopen and validate before any source removal boundary.  This also
        # covers a resume where destructiveIntent was checkpointed previously
        # but the sealed-source operation has not completed yet.
        journal = self._revalidate_backup(journal, request)
        if journal["stages"]["destructiveIntent"]["state"] == "pending":
            journal["stages"]["destructiveIntent"] = {"state": "confirmed"}
            journal = self.store.update(journal)
        if journal["stages"]["sourceSeal"]["state"] != "confirmed":
            source = journal.get("sourceApp")
            manifest = journal.get("rawManifestSHA256")
            if not isinstance(source, Mapping) or not isinstance(manifest, str):
                raise ReinstallBridgeError("export-conflict")
            journal, control = self._prepare_control(
                journal,
                slot="seal",
                action="seal",
                manifest=manifest,
                source=source,
            )
            journal["stages"]["sourceSeal"] = {"state": "inflight"}
            journal = self.store.update(journal)
            journal = self._reload_bound(journal, request)
            self._call("source_seal", request.device_id, control)
            seal_command = journal["commands"].get("seal")
            if not isinstance(seal_command, Mapping):
                raise ReinstallBridgeError("transaction-unknown")
            receipt = self._read_control_response(journal, request, seal_command)
            if receipt is None or receipt.phase not in {"removalSealed", "sealed"} or receipt.error_code is not None:
                raise ReinstallBridgeError("removal-unknown")
            if receipt.raw_manifest_sha256 != manifest or receipt.source_app is None or receipt.source_app.as_dict() != dict(source):
                raise ReinstallBridgeError("export-conflict")
            if type(receipt.pid) is not int or receipt.pid <= 0:
                raise ReinstallBridgeError("removal-unknown")
            journal["commands"]["seal"]["sourcePID"] = receipt.pid
            journal["stages"]["sourceSeal"] = {"state": "confirmed", "evidence": {"receipt": {"phase": receipt.phase, "receiptSHA256": receipt.receipt_sha256}}}
            journal["proof"] = {**journal.get("proof", {}), "sourceSealed": True}
            journal = self.store.update(journal)
        if journal["stages"]["sourceStop"]["state"] != "confirmed":
            journal["stages"]["sourceStop"] = {"state": "inflight"}
            journal = self.store.update(journal)
            journal = self._reload_bound(journal, request)
            pid = self._call("source_pid", request.device_id)
            sealed_pid = journal.get("commands", {}).get("seal", {}).get("sourcePID")
            if type(pid) is not int or pid < 0 or type(sealed_pid) is not int or sealed_pid <= 0:
                raise ReinstallBridgeError("removal-unknown")
            if pid != 0 and pid != sealed_pid:
                raise ReinstallBridgeError("removal-unknown")
            if pid:
                self._call("stop_source", request.device_id, pid)
            journal["stages"]["sourceStop"] = {"state": "confirmed"}
            journal = self.store.update(journal)
        uninstall_state = journal["stages"]["uninstall"]["state"]
        if uninstall_state in {"unknown", "inflight"}:
            # An uninstall result is ambiguous.  Reconcile only the actual
            # absence; a still-present app never receives a second uninstall
            # command from resume.
            try:
                present = self.device.installed(request.device_id).present
            except Exception:
                journal["outcome"] = "unknown"
                with contextlib.suppress(Exception):
                    self.store.update(journal)
                raise ReinstallBridgeError("removal-unknown") from None
            if present:
                journal["outcome"] = "unknown"
                with contextlib.suppress(Exception):
                    self.store.update(journal)
                raise ReinstallBridgeError("removal-unknown")
            journal["stages"]["uninstall"] = {"state": "confirmed"}
            journal["proof"] = {**journal.get("proof", {}), "removalConfirmed": True}
            journal = self.store.update(journal)
            uninstall_state = "confirmed"
        if uninstall_state != "confirmed":
            journal["stages"]["uninstall"] = {"state": "inflight"}
            journal = self.store.update(journal)
            journal = self._reload_bound(journal, request)
            journal = self._revalidate_backup(journal, request)
            self._call("uninstall", request.device_id, TARGET_BUNDLE_ID)
            try:
                present = self.device.installed(request.device_id).present
            except Exception:
                journal["stages"]["uninstall"] = {"state": "unknown"}
                journal["outcome"] = "unknown"
                self.store.update(journal)
                raise ReinstallBridgeError("removal-unknown")
            if present:
                journal["stages"]["uninstall"] = {"state": "unknown"}
                journal["outcome"] = "unknown"
                self.store.update(journal)
                raise ReinstallBridgeError("removal-unknown")
            journal["stages"]["uninstall"] = {"state": "confirmed"}
            journal["proof"] = {**journal.get("proof", {}), "removalConfirmed": True}
            journal = self.store.update(journal)
        return journal

    def _install_target(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        journal = self._reload_bound(journal, request)
        if journal["stages"]["install"]["state"] == "confirmed":
            # A process restart can leave the install stage durable while the
            # nested M1 record has not yet been initialized.  Keep that
            # initialization idempotent and under the same parent lease.
            if journal.get("setup") is None:
                journal = self._ensure_embedded_setup(journal, request)
            return journal
        artifact = self._artifact_from_journal(journal)
        if artifact is None:
            raise ReinstallBridgeError("artifact-mismatch")
        journal["stages"]["install"] = {"state": "inflight"}
        journal = self.store.update(journal)
        journal = self._reload_bound(journal, request)
        result = self._call("install", request.device_id, artifact)
        if isinstance(result, InstallObservation):
            confirmed = result.state == "confirmed"
        elif isinstance(result, Mapping):
            confirmed = result.get("state") == "confirmed"
        else:
            confirmed = False
        if not confirmed:
            journal["stages"]["install"] = {"state": "unknown"}
            journal["outcome"] = "unknown"
            self.store.update(journal)
            raise ReinstallBridgeError("removal-unknown")
        # A successful adapter return is not enough to establish ownership;
        # immediately read back the exact installed Bundle before any target
        # process/input boundary is allowed.
        try:
            installed_after = self.device.installed(request.device_id)
        except Exception:
            journal["stages"]["install"] = {"state": "unknown"}
            journal["outcome"] = "unknown"
            self.store.update(journal)
            raise ReinstallBridgeError("removal-unknown") from None
        if (
            not getattr(installed_after, "present", False)
            or getattr(installed_after, "bundle_id", TARGET_BUNDLE_ID) not in {None, TARGET_BUNDLE_ID}
            or (
                isinstance(getattr(installed_after, "build", None), str)
                and getattr(installed_after, "build") != artifact.build
            )
            or any(
                isinstance(getattr(installed_after, field, None), str)
                and getattr(installed_after, field) != expected
                for field, expected in (
                    ("artifact_sha256", artifact.artifact_sha256),
                    ("profile_sha256", artifact.profile_sha256),
                    ("executable_sha256", artifact.executable_sha256),
                )
            )
        ):
            journal["stages"]["install"] = {"state": "unknown"}
            journal["outcome"] = "unknown"
            self.store.update(journal)
            raise ReinstallBridgeError("removal-unknown")
        journal["stages"]["install"] = {"state": "confirmed"}
        journal["proof"] = {**journal.get("proof", {}), "installationConfirmed": True}
        journal = self.store.update(journal)
        return self._ensure_embedded_setup(journal, request)

    def _restore_target(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        journal = self._reload_bound(journal, request)
        options = journal["options"]
        intent = {
            "version": 1,
            "transferID": journal["transferID"],
            "dataSetID": journal["dataSetID"],
            "nonce": journal["nonce"],
            "rawManifestSHA256": journal.get("rawManifestSHA256"),
            "sourceDeviceUDID": journal["deviceID"],
            "destinationDeviceUDID": journal["deviceID"],
            "sourceApp": journal.get("sourceApp"),
            "setupID": journal["setupID"],
            "deviceID": journal["deviceID"],
            "categories": list(options["categories"]),
            "targetApp": self._target_app_from_journal(journal),
        }
        intent.pop("deviceID", None)
        if journal["stages"]["restoreDelivery"]["state"] != "confirmed":
            journal["restoreIntent"] = intent
            journal["stages"]["restoreDelivery"] = {"state": "inflight"}
            journal = self.store.update(journal)
            journal = self._reload_bound(journal, request)
            # The restore lock is durable before any target-side M1 input,
            # readback, or launch boundary.  A lost publish remains an
            # unknown delivery and is resumed from this exact intent.
            journal = self._revalidate_backup(journal, request)
            self._call("publish_restore_intent", request.device_id, intent)
            package = self.store.transaction_root(journal["transferID"]) / "backup"
            journal = self._reload_bound(journal, request)
            journal = self._revalidate_backup(journal, request)
            self._call("deliver_restore", request.device_id, request.transfer_id, package)
            journal["stages"]["restoreDelivery"] = {"state": "confirmed"}
            journal = self.store.update(journal)
        if journal["stages"]["restoreReceipt"]["state"] != "confirmed":
            # Reuse the complete protocol-2 pairing/support/handoff path with
            # its private M1 journal nested in this parent.  This method is
            # reached only after the durable restore intent and package
            # delivery, so its first launch/input cannot outrun the restore
            # authority.
            journal = self._reload_bound(journal, request)
            journal = self._run_embedded_setup(journal, request)
            journal = self._reload_bound(journal, request)
            result = self._call("restore_readback", request.device_id, request.transfer_id)
            if result is None:
                raise ReinstallBridgeError("restore-unknown")
            if hasattr(result, "phase"):
                phase = result.phase
                categories = list(getattr(result, "categories", ()))
                counts = getattr(result, "counts", None)
                result_intent = getattr(result, "intent", None)
                full_receipt = getattr(result, "receipt", None)
            elif isinstance(result, Mapping):
                if set(result) != {"phase", "categories", "counts", "intent", "receipt"}:
                    raise ReinstallBridgeError("restore-unknown")
                phase, categories, counts = result.get("phase"), result.get("categories"), result.get("counts")
                result_intent = result.get("intent")
                full_receipt = result.get("receipt")
            else:
                raise ReinstallBridgeError("restore-unknown")
            expected_intent = journal.get("restoreIntent")
            expected_counts = journal.get("counts")
            if phase != "committed" or not isinstance(result_intent, Mapping) or not isinstance(expected_intent, Mapping) or result_intent != expected_intent or not isinstance(counts, Mapping) or not isinstance(expected_counts, Mapping):
                raise ReinstallBridgeError("restore-unknown")
            selected = set(options["categories"])
            if not isinstance(categories, list) or len(categories) != len(options["categories"]):
                raise ReinstallBridgeError("restore-unknown")
            committed = []
            for item in categories:
                if not isinstance(item, Mapping) or set(item) != {"category", "state", "receiptSHA256"}:
                    raise ReinstallBridgeError("restore-unknown")
                if item.get("state") != "committed" or not isinstance(item.get("receiptSHA256"), str) or not _HEX64.fullmatch(item["receiptSHA256"]):
                    raise ReinstallBridgeError("restore-unknown")
                committed.append(item.get("category"))
            if committed != options["categories"] or set(committed) != selected:
                raise ReinstallBridgeError("restore-unknown")
            receipt = self._validate_restore_receipt(
                full_receipt,
                expected_intent=expected_intent,
                selected=options["categories"],
                expected_counts=expected_counts,
            )
            receipt_categories = receipt["categoryReceipts"]
            if dict(counts) != dict(expected_counts) or [item["category"] for item in receipt_categories] != committed or [item["receiptSHA256"] for item in receipt_categories] != [item["receiptSHA256"] for item in categories]:
                raise ReinstallBridgeError("restore-unknown")
            journal["restoreReceipt"] = dict(receipt)
            journal["counts"] = dict(counts)
            journal["stages"]["restoreReceipt"] = {"state": "confirmed"}
            journal["proof"] = {**journal.get("proof", {}), "restoreCommitted": True}
            journal = self.store.update(journal)
        setup = journal.get("setup")
        if not isinstance(setup, Mapping) or setup.get("stages", {}).get("complete", {}).get("state") != "confirmed":
            raise ReinstallBridgeError("support-unavailable")
        setup_proof = setup.get("proof", {})
        if setup_proof.get("pairingImported") is not True or setup_proof.get("supportObserved") is not True:
            raise ReinstallBridgeError("support-unavailable")
        return journal

    def _confirm_final_support(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        """Bind final support proof to a fresh same-device observation."""
        journal = self._reload_bound(journal, request)
        if journal["stages"]["restoreReceipt"]["state"] != "confirmed":
            raise ReinstallBridgeError("restore-unknown")
        setup = journal.get("setup")
        if not isinstance(setup, Mapping) or setup.get("stages", {}).get("complete", {}).get("state") != "confirmed":
            raise ReinstallBridgeError("support-unavailable")
        setup_proof = setup.get("proof", {})
        if setup_proof.get("pairingImported") is not True or setup_proof.get("supportObserved") is not True:
            raise ReinstallBridgeError("support-unavailable")
        planned = setup.get("support")
        if not isinstance(planned, Mapping):
            raise ReinstallBridgeError("support-unavailable")
        journal["stages"]["finalSupport"] = {"state": "inflight"}
        journal = self.store.update(journal)
        observed = self._observe(request.device_id)
        actual = self._call("support", request.device_id)
        if not isinstance(actual, Mapping) or set(actual) != {"observed", "method", "osVersion", "generationID", "identifier", "version"}:
            raise ReinstallBridgeError("support-unavailable")
        if (
            actual.get("observed") is not True
            or not isinstance(actual.get("method"), str)
            or not isinstance(planned.get("method"), str)
            or actual.get("method") != planned.get("method")
            or actual.get("method") == ""
            or not isinstance(actual.get("osVersion"), str)
            or not isinstance(planned.get("osVersion"), str)
            or actual.get("osVersion") != observed.os_version
            or actual.get("osVersion") != planned.get("osVersion")
            or not isinstance(actual.get("generationID"), str)
            or not isinstance(planned.get("generationID"), str)
            or not actual["generationID"]
            or actual["generationID"].lower() != planned["generationID"].lower()
            or actual.get("generationID", "").lower() != journal["setupID"].lower()
            or not isinstance(actual.get("identifier"), str)
            or not isinstance(planned.get("identifier"), str)
            or not actual["identifier"]
            or actual.get("identifier") != planned.get("identifier")
            or not isinstance(actual.get("version"), str)
            or not isinstance(planned.get("version"), str)
            or not actual["version"]
            or actual.get("version") != planned.get("version")
        ):
            raise ReinstallBridgeError("support-unavailable")
        journal = self._reload_bound(journal, request)
        journal["stages"]["setup"] = {"state": "confirmed", "evidence": {"pairingImported": True, "supportObserved": True}}
        journal["stages"]["finalSupport"] = {
            "state": "confirmed",
            "evidence": {"pairingImported": True, "supportObserved": True},
        }
        journal["proof"] = {**journal.get("proof", {}), "supportObserved": True, "pairingImported": True}
        return self.store.update(journal)

    def _ensure_embedded_setup(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        """Create the nested M1 record after target install ownership exists."""
        if isinstance(journal.get("setup"), Mapping):
            return journal
        options = journal.get("options")
        artifact = self._artifact_from_journal(journal)
        if not isinstance(options, Mapping) or artifact is None:
            raise ReinstallBridgeError("artifact-mismatch")
        observed = self._observe(request.device_id)
        setup = {
            "version": 1,
            "operation": "setup",
            "setupID": journal["setupID"],
            "deviceID": journal["deviceID"],
            "intent": {
                "source": options["source"],
                "artifactPath": options.get("artifactPath"),
                "teamID": options["teamID"],
                "allowProvisioningUpdates": options["allowProvisioningUpdates"],
                "targetBundleID": TARGET_BUNDLE_ID,
                "targetName": TARGET_NAME,
                "deviceObservation": {
                    "deviceID": observed.device_id,
                    "osVersion": observed.os_version,
                    "transport": observed.transport,
                    "developerMode": True,
                    "trust": True,
                },
                "pairingTransactionID": _uuid(),
                "artifact": {
                    "path": artifact.path,
                    "bundleID": artifact.bundle_id,
                    "executable": TARGET_NAME,
                    "teamID": artifact.team_id,
                    "artifactSHA256": artifact.artifact_sha256,
                    "executableSHA256": artifact.executable_sha256,
                    "profileSHA256": artifact.profile_sha256,
                    "expiresAt": artifact.expires_at,
                    "build": artifact.build,
                },
            },
            "stages": {
                "artifact": {"state": "confirmed"},
                "pairing": {"state": "pending"},
                # M2's confirmed install is the same InstallationProxy
                # ownership boundary; it is recorded in the embedded M1
                # record so M1's handoff validator can consume it.
                "install": {"state": "confirmed"},
                "support": {"state": "pending"},
                "handoff": {"state": "pending"},
                "complete": {"state": "pending"},
            },
            "proof": {"installationConfirmed": True, "pairingImported": False, "supportObserved": False},
            "delivery": {"state": "notStarted"},
            "installOwnership": {
                "transactionID": journal["setupID"],
                "bundleID": artifact.bundle_id,
                "build": artifact.build,
                "artifactSHA256": artifact.artifact_sha256,
                "executableSHA256": artifact.executable_sha256,
                "profileSHA256": artifact.profile_sha256,
            },
        }
        try:
            JournalStore._validate(setup)
        except SetupBridgeError:
            raise ReinstallBridgeError("storage-unavailable") from None
        journal["setup"] = setup
        return self.store.update(journal)

    def _run_embedded_setup(self, journal: dict[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        """Run M1 private stages against the parent-owned embedded record."""
        # This method owns the target-side M1 handoff and launch boundary.
        # Revalidate the private source package immediately before entering it
        # so a changed package cannot reach restore input or launch.
        journal = self._revalidate_backup(journal, request)
        journal = self._ensure_embedded_setup(journal, request)
        setup = journal.get("setup")
        if not isinstance(setup, Mapping):
            raise ReinstallBridgeError("transaction-unknown")
        if setup.get("stages", {}).get("complete", {}).get("state") == "confirmed":
            return journal
        port = _EmbeddedSetupPort(self.store, journal)
        options = journal["options"]
        m1_options = SetupOptions(
            options["source"], options.get("artifactPath"), options["teamID"], options["allowProvisioningUpdates"]
        )
        m1_request = SetupRequest(_uuid(), "apply", journal["setupID"], journal["deviceID"], m1_options)

        _Config = type(
            "_EmbeddedSetupConfig",
            (),
            {
                "state_root": self.config.state_root,
                "target_bundle_id": TARGET_BUNDLE_ID,
                "target_name": TARGET_NAME,
            },
        )

        # The private M1 methods use only this config's frozen identity and
        # the shared adapter seams; its public apply/resume/lease are never
        # entered from this nested call.
        try:
            from ..Setup.setup_producer import SetupProducer
        except ImportError:  # direct packaged execution
            from Setup.setup_producer import SetupProducer
        m1 = SetupProducer(_Config(), store=port, device=self.device, process=None, support=None)
        setup = port.read()
        if setup is None:
            raise ReinstallBridgeError("transaction-unknown")
        if setup["stages"]["pairing"]["state"] == "pending":
            setup = port.checkpoint(setup, "pairing", "inflight")
            m1._boundary_observe(setup, m1_request.device_id)
            setup = m1._pair(setup, m1_request)
            setup = port.checkpoint(setup, "pairing", "confirmed", proof={"pairingImported": False})
        elif setup["stages"]["pairing"]["state"] in {"unknown", "inflight"}:
            # Resume consumes only the frozen candidate.  It never creates a
            # second pair operation after an ambiguous device boundary.
            candidate = port.transaction_root(m1_request.setup_id) / "pairing.candidate"
            verify = getattr(self.device, "verify_pairing", None)
            if not callable(verify) or not candidate.exists() or candidate.is_symlink():
                raise ReinstallBridgeError("pairing-unknown")
            observed_pairing = verify(m1_request.device_id, candidate)
            if getattr(observed_pairing, "state", None) != "verified" or not isinstance(getattr(observed_pairing, "sha256", None), str):
                raise ReinstallBridgeError("pairing-unknown")
            setup["pairing"] = {
                "candidate": f"transactions/{m1_request.setup_id}/pairing.candidate",
                "sha256": observed_pairing.sha256,
            }
            setup = port.checkpoint(setup, "pairing", "confirmed", proof={"pairingImported": False})

        artifact = m1._artifact_from_journal(setup)
        if artifact is None:
            raise ReinstallBridgeError("artifact-mismatch")
        handoff_state = setup["stages"]["handoff"]["state"]
        if handoff_state == "pending":
            setup = m1._handoff(setup, m1_request, artifact)
        elif handoff_state == "inflight":
            # M1's private resume path consumes the durable nonce/PID/formal
            # plan and never creates a second handoff identity.
            m1._resume_handoff(setup, m1_request)
            setup = port.read()
        elif handoff_state == "unknown":
            raise ReinstallBridgeError("handoff-unknown")

        setup = port.read()
        if setup is None:
            raise ReinstallBridgeError("transaction-unknown")
        if setup["stages"]["support"]["state"] != "confirmed":
            observed = m1._boundary_observe(setup, m1_request.device_id)
            planned_support = setup.get("support")
            expected_support = copy.deepcopy(planned_support) if isinstance(planned_support, Mapping) else None
            setup = m1._support(setup, m1_request, observed, expected=expected_support)
        if setup["stages"]["handoff"]["state"] != "confirmed":
            raise ReinstallBridgeError("handoff-unknown")
        if setup["stages"]["complete"]["state"] != "confirmed":
            setup = port.checkpoint(
                setup,
                "complete",
                "confirmed",
                proof={"installationConfirmed": True, "pairingImported": True, "supportObserved": True},
            )
        return copy.deepcopy(port.parent)

    @staticmethod
    def _target_app_from_journal(journal: Mapping[str, Any]) -> dict[str, Any]:
        artifact = _mapping(journal.get("targetArtifact"))
        if artifact is None:
            raise ReinstallBridgeError("artifact-mismatch")
        value = {
            "bundleID": artifact.get("bundleID"),
            "build": artifact.get("build"),
            "profileSHA256": artifact.get("profileSHA256"),
            "executableSHA256": artifact.get("executableSHA256"),
        }
        if value["bundleID"] != TARGET_BUNDLE_ID or not isinstance(value["build"], str) or not value["build"] or not all(isinstance(value[key], str) and _HEX64.fullmatch(value[key]) for key in ("profileSHA256", "executableSHA256")):
            raise ReinstallBridgeError("artifact-mismatch")
        return value

    def _payload_preflight(self, options: ReinstallOptions, *, artifact: ArtifactIdentity | None) -> ReinstallPayload:
        app = self._artifact_dict(artifact) if artifact is not None else None
        app_payload = None
        if app is not None:
            app_payload = {key: app[key] for key in ("bundleID", "build", "profileSHA256", "executableSHA256")}
        return ReinstallPayload(
            "preflight", "ready", False, False, {key: False for key in _PROOF_KEYS},
            tuple({"category": name, "state": "waiting", "receiptSHA256": None} for name in options.categories),
            None, app_payload, options.team_id, app.get("expiresAt") if app else None,
        )

    def _payload_from_journal(self, journal: Mapping[str, Any]) -> ReinstallPayload:
        stages = journal["stages"]
        if is_completed_journal(journal):
            stage, outcome = "complete", "confirmed"
        elif stages["abandon"]["state"] == "confirmed":
            stage, outcome = "abandon", "confirmed"
        else:
            mapping = (
                ("artifact", "artifact"), ("sourceRequest", "source"), ("sourceReady", "source"),
                ("backup", "backup"), ("destructiveIntent", "seal"), ("sourceSeal", "seal"),
                ("sourceStop", "uninstall"), ("uninstall", "uninstall"), ("install", "install"),
                ("setup", "support"), ("restoreDelivery", "restore"), ("restoreReceipt", "restore"),
                ("finalSupport", "support"), ("complete", "complete"),
            )
            stage, outcome = "preflight", "inProgress"
            for key, external in mapping:
                state = stages[key]["state"]
                if state in {"unknown", "inflight"}:
                    stage, outcome = external, "unknown"
                    break
                if state != "confirmed":
                    stage, outcome = external, "inProgress"
                    break
        proof = journal.get("proof", {})
        selected = journal["options"]["categories"]
        receipts = _mapping(journal.get("restoreReceipt")) or {}
        by_category = {item.get("category"): item for item in receipts.get("categoryReceipts", []) if isinstance(item, Mapping)}
        categories = tuple(
            {"category": name, "state": "committed" if isinstance(by_category.get(name), Mapping) else "waiting", "receiptSHA256": by_category[name].get("receiptSHA256") if name in by_category else None}
            for name in selected
        )
        artifact = _mapping(journal.get("targetArtifact"))
        app = None
        if artifact is not None:
            app = {key: artifact.get(key) for key in ("bundleID", "build", "profileSHA256", "executableSHA256")}
        destructive = stages["destructiveIntent"]["state"] in {"confirmed", "inflight", "unknown"}
        can_abandon = not destructive and outcome not in {"confirmed"} and stages["abandon"]["state"] != "confirmed"
        return ReinstallPayload(
            stage, outcome, outcome not in {"confirmed"}, can_abandon,
            {key: proof.get(key) is True for key in _PROOF_KEYS}, categories,
            journal.get("counts") if isinstance(journal.get("counts"), Mapping) else None,
            app, journal["options"].get("teamID"), artifact.get("expiresAt") if artifact else None,
            (receipts.get("receiptSHA256") if isinstance(receipts.get("receiptSHA256"), str) else None),
        )

    def _artifact_from_journal(self, journal: Mapping[str, Any]) -> ArtifactIdentity | None:
        value = _mapping(journal.get("targetArtifact"))
        if value is None:
            return None
        try:
            return ArtifactIdentity(
                str(value["path"]), value["bundleID"], TARGET_NAME, value["teamID"], value["artifactSHA256"],
                value["executableSHA256"], value["profileSHA256"], value["expiresAt"], {}, value["build"],
            )
        except (KeyError, TypeError, ValueError):
            return None

    @staticmethod
    def _artifact_dict(artifact: ArtifactIdentity) -> dict[str, Any]:
        return {
            "path": str(artifact.path), "bundleID": artifact.bundle_id, "build": artifact.build,
            "teamID": artifact.team_id, "artifactSHA256": artifact.artifact_sha256,
            "profileSHA256": artifact.profile_sha256, "executableSHA256": artifact.executable_sha256,
            "expiresAt": artifact.expires_at,
        }

    @staticmethod
    def _installed_build(installed: Any) -> str:
        build = getattr(installed, "build", None)
        return build if isinstance(build, str) and build else "unknown"

    def _observe(self, device_id: str) -> Any:
        observed = self.device.observe(device_id)
        if getattr(observed, "device_id", "").lower() != device_id.lower():
            raise ReinstallBridgeError("identity-mismatch")
        if getattr(observed, "transport", "").upper() != "USB":
            raise ReinstallBridgeError("device-disconnected")
        if getattr(observed, "developer_mode", None) is not True or getattr(observed, "trust", None) is not True:
            raise ReinstallBridgeError("trust-required")
        return observed

    @staticmethod
    def _bind(journal: Mapping[str, Any], request: ReinstallRequest) -> None:
        if journal.get("transferID") != request.transfer_id or journal.get("deviceID") != request.device_id:
            raise ReinstallBridgeError("transaction-conflict")
        if request.options is not None and request.options.as_dict() != journal.get("options"):
            raise ReinstallBridgeError("transaction-conflict")

    def _reload_bound(self, journal: Mapping[str, Any], request: ReinstallRequest) -> dict[str, Any]:
        """Reopen the authoritative record immediately before a boundary."""
        current = self.store.read()
        if current is None:
            raise ReinstallBridgeError("transaction-unknown")
        self._bind(current, request)
        for key in (
            "version", "operation", "transferID", "deviceID", "dataSetID", "nonce", "setupID",
            "knownSource", "options", "sourceApp", "rawManifestSHA256", "targetArtifact",
            "requestSHA256", "restoreIntent",
        ):
            if key in journal and current.get(key) != journal.get(key):
                raise ReinstallBridgeError("transaction-conflict")
        # The caller's object may contain only a just-completed in-memory
        # checkpoint.  Every boundary is called after that checkpoint has
        # been written, so the reopened record is the only authority.
        return current

    @staticmethod
    def _terminal(journal: Mapping[str, Any]) -> bool:
        return is_terminal_journal(journal)

    def _guard_m1(self) -> None:
        current = JournalStore(self.config.state_root).read()
        if current is None:
            return
        stages = current.get("stages", {}) if isinstance(current, Mapping) else {}
        if not isinstance(stages, Mapping) or not all(isinstance(stages.get(key), Mapping) and stages[key].get("state") == "confirmed" for key in ("complete",)):
            raise ReinstallBridgeError("transaction-conflict")

    def _call(self, name: str, *args: Any) -> Any:
        method = getattr(self.device, name, None)
        if not callable(method):
            raise ReinstallBridgeError("environment-not-ready")
        try:
            return method(*args)
        except ReinstallBridgeError:
            raise
        except SetupBridgeError as error:
            raise ReinstallBridgeError(self._boundary_error(name, error)) from None
        except TimeoutError:
            raise ReinstallBridgeError("timeout") from None
        except Exception:
            raise ReinstallBridgeError(self._boundary_error(name, None)) from None

    @staticmethod
    def _boundary_error(name: str, error: BaseException | None) -> str:
        """Map an adapter exception to the fixed M2 boundary code."""
        existing = getattr(error, "code", None)
        if isinstance(existing, str) and existing in {
            "device-disconnected", "trust-required", "developer-mode-required",
            "unsupported-os", "identity-mismatch", "artifact-mismatch",
            "storage-unavailable", "configuration-invalid", "dependency-mismatch",
            "runtime-api-mismatch", "timeout", "backup-invalid", "restore-unknown",
            "support-unavailable", "update-required", "source-busy", "export-conflict",
            "removal-unknown", "operation-abandoned",
        }:
            return existing
        if name in {"source_request", "source_readback", "source_pid"}:
            return "source-busy"
        if name in {"source_seal", "source_release", "stop_source", "uninstall", "install"}:
            return "removal-unknown"
        if name in {"publish_restore_intent", "deliver_restore", "restore_readback"}:
            return "restore-unknown"
        if name == "support":
            return "support-unavailable"
        return "operation-failed"

    @staticmethod
    def _coerce_readback(value: Any, journal: Mapping[str, Any]) -> ExportReadback | None:
        if isinstance(value, ExportReadback):
            return value
        if not isinstance(value, Mapping):
            return None
        source = value.get("sourceApp")
        identity = None
        if isinstance(source, Mapping):
            try:
                identity = SourceAppIdentity(source["bundleID"], source["build"], source["profileSHA256"], source["executableSHA256"])
            except (KeyError, TypeError):
                return None
        return ExportReadback(
            transfer_id=str(value.get("transferID", journal.get("transferID", ""))),
            data_set_id=str(value.get("dataSetID", journal.get("dataSetID", ""))),
            nonce=str(value.get("nonce", journal.get("nonce", ""))),
            raw_manifest_sha256=(
                value.get("rawManifestSHA256")
                if isinstance(value.get("rawManifestSHA256"), str)
                else value.get("manifestSHA256") if isinstance(value.get("manifestSHA256"), str) else None
            ),
            source_app=identity,
            receipt_sha256=value.get("receiptSHA256") if isinstance(value.get("receiptSHA256"), str) else None,
            command_id=value.get("commandID") if isinstance(value.get("commandID"), str) else None,
            action=value.get("action") if isinstance(value.get("action"), str) else None,
            request_sha256=value.get("requestSHA256") if isinstance(value.get("requestSHA256"), str) else None,
            pid=value.get("pid") if type(value.get("pid")) is int else None,
            error_code=value.get("errorCode") if isinstance(value.get("errorCode"), str) else None,
        )

    @staticmethod
    def _write_private(path: Path, data: bytes) -> None:
        if path.exists() or path.is_symlink():
            raise ReinstallBridgeError("storage-unavailable")
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            os.write(fd, data)
            os.fsync(fd)
        finally:
            os.close(fd)
        directory_fd = os.open(path.parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)

    @staticmethod
    def _write_private_idempotent(path: Path, data: bytes) -> None:
        """Retain an identical immutable request across crash/resume."""
        if not path.exists() and not path.is_symlink():
            ReinstallProducer._write_private(path, data)
            return
        fd: int | None = None
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            info = os.fstat(fd)
            if (
                not stat.S_ISREG(info.st_mode)
                or info.st_uid != os.getuid()
                or info.st_nlink != 1
                or stat.S_IMODE(info.st_mode) != 0o600
                or info.st_size != len(data)
            ):
                raise ReinstallBridgeError("storage-unavailable")
            value = bytearray()
            while len(value) < info.st_size:
                chunk = os.read(fd, min(1024 * 1024, info.st_size - len(value)))
                if not chunk:
                    raise ReinstallBridgeError("storage-unavailable")
                value.extend(chunk)
            if os.read(fd, 1) or bytes(value) != data:
                raise ReinstallBridgeError("export-conflict")
        except ReinstallBridgeError:
            raise
        except OSError:
            raise ReinstallBridgeError("storage-unavailable") from None
        finally:
            if fd is not None:
                with contextlib.suppress(OSError):
                    os.close(fd)

    def _record_failure(self, journal: Mapping[str, Any], error: BaseException) -> None:
        # A private embedded M1 stage checkpoints through the parent store and
        # may fail after several nested writes.  Never overwrite those newer
        # durable observations with the outer caller's stale copy while
        # recording the conservative boundary state.
        current = None
        with contextlib.suppress(Exception):
            current = self.store.read()
        value = copy.deepcopy(dict(current if isinstance(current, Mapping) else journal))
        value["errorCode"] = _error_code(error)
        value["outcome"] = "unknown"
        for stage, item in value.get("stages", {}).items():
            if isinstance(item, Mapping) and item.get("state") == "inflight":
                value["stages"][stage] = {"state": "unknown", "detail": _error_code(error)[:160]}
        with contextlib.suppress(Exception):
            self.store.update(value)


__all__ = ["ReinstallPayload", "ReinstallProducer"]
