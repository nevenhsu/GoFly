"""Protocol-5 management coordinator.

The producer is the Mac-side ordering boundary for management.  It owns the
durable journal, but it does not manufacture device, App, or Core proof.  The
default adapters are transport pinned and every positive stage is backed by a
typed observation before the journal is advanced.
"""

from __future__ import annotations

import contextlib
import copy
import hashlib
import json
import os
import re
import time
import uuid
from dataclasses import dataclass, replace
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Callable, Mapping

try:
    from ..Reinstall.reinstall_config import ReinstallConfiguration
    from ..Setup.setup_adapters import (
        ArtifactIdentity,
        FormalArtifactValidator,
        PinnedPymobiledeviceAdapter,
        PinnedXcodeProcessAdapter,
        snapshot_artifact,
        build_formal_setup_input,
    )
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME
    from .management_adapters import (
        ManagementDeviceObservation,
        ManagementInstalledIdentity,
        PinnedManagementDeviceAdapter,
    )
    from .management_journal import ManagementJournal, reject_unresolved_management
    from .management_lineage import generation_ids, validate_source_lineage
    from .management_preparation import ManagementPreparationAdapter
    from .management_protocol import (
        ManagementBridgeError,
        ManagementRequest,
        _canonical_request,
        _parse_object,
        _validate_receipt,
        _validate_app,
        _expiry,
        _team,
        _hash,
        encode_request,
    )
    from .management_source import PreparationAppIdentity, SourceActivation, decode_source_activation
except ImportError:  # direct execution from packaged Bridge root
    from Reinstall.reinstall_config import ReinstallConfiguration
    from Setup.setup_adapters import ArtifactIdentity, FormalArtifactValidator, PinnedPymobiledeviceAdapter, PinnedXcodeProcessAdapter, build_formal_setup_input, snapshot_artifact
    from Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME
    from Management.management_adapters import ManagementDeviceObservation, ManagementInstalledIdentity, PinnedManagementDeviceAdapter
    from Management.management_journal import ManagementJournal, reject_unresolved_management
    from Management.management_lineage import generation_ids, validate_source_lineage
    from Management.management_preparation import ManagementPreparationAdapter
    from Management.management_protocol import ManagementBridgeError, ManagementRequest, _canonical_request, _parse_object, _validate_receipt, _validate_app, _expiry, _team, _hash, encode_request
    from Management.management_source import PreparationAppIdentity, SourceActivation, decode_source_activation


_HEX64 = re.compile(r"[0-9a-f]{64}\Z")
# Public phases deliberately use protocol 5's closed vocabulary. Internal
# readback/launch checkpoints are grouped under pairing or adoption.
_STAGE_MAP = (
    ("artifact", "artifact"), ("sourceRequest", "source"), ("sourceReady", "source"),
    ("mutationIntent", "seal"), ("sourceSeal", "seal"), ("sourceStop", "seal"),
    ("legacy", "seal"), ("legacyIncomingRemoval", "seal"),
    ("legacyReadbackRequestRemoval", "seal"), ("legacyReadbackResponseRemoval", "seal"),
    ("legacyTransition", "seal"), ("update", "update"),
    ("pairCreate", "pairing"), ("pairDelivery", "pairing"),
    ("readbackPublish", "pairing"), ("readbackLaunch", "pairing"),
    ("readback", "pairing"), ("readbackStop", "pairing"), ("support", "support"),
    ("formalInput", "adoption"), ("formalLaunch", "adoption"),
    ("pairing", "adoption"), ("activation", "adoption"), ("finalSupport", "support"),
)

_PROOF_KEYS = (
    "sourceBound", "sourceQuiescent", "mutationSealed", "updateConfirmed",
    "pairingImported", "supportObserved", "adoptionCommitted",
)
_LEGACY_NAMES = ("setupIncoming", "setupReadbackRequest", "setupReadbackResponse")
_LEGACY_EVIDENCE = {
    "setupIncoming": "legacyIncoming",
    "setupReadbackRequest": "legacyReadbackRequest",
    "setupReadbackResponse": "legacyReadbackResponse",
}


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _json(raw: Mapping[str, Any]) -> bytes:
    return json.dumps(raw, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def _error(error: BaseException, default: str = "operation-failed") -> ManagementBridgeError:
    if isinstance(error, ManagementBridgeError):
        return error
    if isinstance(error, SetupBridgeError):
        return ManagementBridgeError(error.code)
    code = getattr(error, "code", None)
    return ManagementBridgeError(code if isinstance(code, str) else default)


def _app_dict(identity: Any) -> dict[str, str]:
    if isinstance(identity, PreparationAppIdentity):
        value = identity.app()
    elif isinstance(identity, ArtifactIdentity):
        value = {
            "bundleID": identity.bundle_id,
            "build": identity.build,
            "profileSHA256": identity.profile_sha256,
            "executableSHA256": identity.executable_sha256,
        }
    elif isinstance(identity, Mapping):
        value = dict(identity)
    else:
        raise ManagementBridgeError("identity-unverified")
    return _validate_app(value, code="identity-unverified")


def _identity_from_app(app: Mapping[str, Any], team: str, expiry: str) -> PreparationAppIdentity:
    return PreparationAppIdentity(
        app["bundleID"], app["build"], app["profileSHA256"], app["executableSHA256"], team, expiry
    )


def _observation_dict(value: Any) -> dict[str, Any]:
    if isinstance(value, Mapping):
        return dict(value)
    result: dict[str, Any] = {}
    for name in ("device_id", "os_version", "transport", "trust", "developer_mode", "exists", "build", "team_id", "bundle_id"):
        if hasattr(value, name):
            result[name] = getattr(value, name)
    return result


@dataclass(frozen=True)
class ManagementPayload:
    stage: str
    outcome: str
    can_resume: bool
    can_release: bool
    source_admission: str | None
    connection_revision: int
    current_transport: str
    proof: Mapping[str, bool]
    app: Mapping[str, Any] | None = None
    team_id: str | None = None
    expires_at: str | None = None
    adoption_receipt: Mapping[str, Any] | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "stage": self.stage,
            "outcome": self.outcome,
            "canResume": self.can_resume,
            "canRelease": self.can_release,
            "sourceAdmission": self.source_admission,
            "connectionRevision": self.connection_revision,
            "currentTransport": self.current_transport,
            "proof": {key: self.proof.get(key) is True for key in _PROOF_KEYS},
            "app": dict(self.app) if self.app is not None else None,
            "teamID": self.team_id,
            "expiresAt": self.expires_at,
            "adoptionReceipt": dict(self.adoption_receipt) if self.adoption_receipt is not None else None,
        }


class ManagementProducer:
    """One protocol-5 transaction coordinator.

    Adapters are injectable for offline boundary tests.  Production instances
    create the D1/D2 adapters from the request's immutable transport revision.
    """

    def __init__(
        self,
        config: ReinstallConfiguration,
        *,
        store: ManagementJournal | None = None,
        device: Any | None = None,
        preparation: Any | None = None,
        process: Any | None = None,
        artifact_validator: Any | None = None,
    ) -> None:
        self.config = config
        self.store = store or ManagementJournal(config.state_root)
        self._device = device
        self._preparation = preparation
        self.process = process
        self.artifact_validator = artifact_validator or FormalArtifactValidator()

    def _adapters(self, transport: str) -> tuple[Any, Any]:
        if transport not in {"USB", "Network"}:
            raise ManagementBridgeError("invalid-request")
        device = self._device or PinnedManagementDeviceAdapter(self.config, transport)
        preparation = self._preparation or ManagementPreparationAdapter(self.config, transport)
        return device, preparation

    def handle(self, request: ManagementRequest) -> Mapping[str, Any]:
        if not isinstance(request, ManagementRequest):
            raise ManagementBridgeError("invalid-request")
        request = _canonical_request(request)
        if request.action == "query":
            return self.query_payload(request)
        if request.action == "preflight":
            return self.preflight(request).as_dict()
        if request.action == "apply":
            return self.apply(request).as_dict()
        if request.action == "resume":
            return self.resume(request).as_dict()
        if request.action == "release":
            return self.release(request).as_dict()
        raise ManagementBridgeError("invalid-request")

    def query_payload(self, request: ManagementRequest) -> Mapping[str, Any]:
        """Build a response solely from validated local journal bytes."""
        if request.action != "query":
            raise ManagementBridgeError("invalid-request")
        value = self.store.read()
        if value is None:
            return ManagementPayload(
                "preflight", "inProgress", False, False, None,
                request.connection_revision, request.transport,
                {key: False for key in _PROOF_KEYS},
            ).as_dict()
        self._bind_identity(value, request, allow_options=False)
        return self._payload(value, request).as_dict()

    def preflight(self, request: ManagementRequest) -> ManagementPayload:
        if (request.action != "preflight" or
                (request.kind == "renew" and request.options is None) or
                (request.kind == "repair" and request.options is not None)):
            raise ManagementBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        self._guard_other_operations()
        current = self.store.read()
        if current is not None and not self.store.is_terminal(current):
            raise ManagementBridgeError("transaction-conflict")
        device, preparation = self._adapters(request.transport)
        observed = self._observe(device, request.device_id)
        installed = self._installed(device, request.device_id)
        if not bool(getattr(installed, "exists", False)):
            raise ManagementBridgeError("identity-unverified")
        build = getattr(installed, "build", None)
        team = getattr(installed, "team_id", None)
        if not isinstance(build, str) or not build or not isinstance(team, str):
            raise ManagementBridgeError("identity-unverified")
        activation_raw = self._read_activation(device, request.device_id)
        source = self._decode_source(activation_raw, request.device_id, build, team)
        source.require_new_receipt_capacity()
        if request.options is not None and request.options.team_id != source.receipt.team_id:
            raise ManagementBridgeError("identity-mismatch")
        intent = preparation.read_file(request.device_id, "restoreIntent")
        root = preparation.read_file(request.device_id, "restoreRoot")
        management_root = preparation.read_management_root(request.device_id)
        generations = self._read_generations(preparation, request.device_id, management_root)
        validate_source_lineage(source, request.device_id, intent, root, management_root, generations)
        pid = self._source_pid(device, request.device_id)
        if type(pid) is not int or pid < 0:
            raise ManagementBridgeError("identity-mismatch")
        return ManagementPayload(
            "preflight", "ready", False, False, None, request.connection_revision,
            observed.transport, {key: False for key in _PROOF_KEYS},
        )

    def apply(self, request: ManagementRequest) -> ManagementPayload:
        if (request.action != "apply" or
                (request.kind == "renew" and request.options is None) or
                (request.kind == "repair" and request.options is not None)):
            raise ManagementBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        self.config.ensure_state_root()
        device, preparation = self._adapters(request.transport)
        with self.store.lock():
            self._guard_other_operations()
            previous = self.store.read()
            if previous is not None and previous["header"]["managementID"] == request.management_id:
                value = previous
                self._bind_identity(value, request, allow_options=True)
                # A duplicate apply only reads its consumed operation. Later
                # physical work requires the explicit Resume command.
                return self._payload(value, request)
            value = self.store.create(request)
            try:
                return self._initialize(request, device, preparation, value)
            except Exception as error:
                self._record_failure(value, _error(error).code)
                raise _error(error)

    def _initialize(self, request: ManagementRequest, device: Any, preparation: Any,
                    value: Mapping[str, Any]) -> ManagementPayload:
        # All source evidence and the admission decision are persisted
        # before the first remote publication or process mutation.
        source, restore_intent, restore_root, management_root, installed, observed = self._capture_source(
            device, preparation, request, value
        )
        self.store.put_evidence("sourceActivation", source.raw)
        self._put_optional("sourceRestoreIntent", restore_intent)
        self._put_optional("sourceRestoreRoot", restore_root)
        self._put_optional("sourceManagementRoot", management_root)
        target_artifact = self._candidate_artifact(request, value, observed)
        if target_artifact is not None and target_artifact.team_id != source.receipt.team_id:
            raise ManagementBridgeError("identity-mismatch")
        app = _app_dict(target_artifact) if target_artifact is not None else source.identity.app()
        identity = source.identity if target_artifact is None else PreparationAppIdentity(
            target_artifact.bundle_id, target_artifact.build, target_artifact.profile_sha256,
            target_artifact.executable_sha256, target_artifact.team_id, target_artifact.expires_at)
        self.store.put_evidence("targetIdentity", _json({**identity.app(), "teamID": identity.team_id, "expiresAt": identity.expires_at}))
        if target_artifact is not None:
            self.store.put_evidence("targetArtifact", _json({"app": app, "teamID": identity.team_id,
                "expiresAt": identity.expires_at, "artifactSHA256": target_artifact.artifact_sha256}))
            if self.store.read()["stages"]["artifact"]["state"] == "pending":
                self.store.record_intent("artifact")
            if self.store.read()["stages"]["artifact"]["state"] != "confirmed":
                self.store.confirm("artifact", "targetArtifact")
        target_setup = value["header"]["targetSetupID"]
        source_root_sha = _sha(restore_root) if restore_root is not None else None
        core_request = {
            "version": 1,
            "managementID": value["header"]["managementID"],
            "nonce": value["header"]["nonce"],
            "kind": value["header"]["kind"],
            "expectedDeviceUDID": request.device_id,
            "sourceSetupID": source.receipt.setup_id,
            "sourceApp": source.identity.app(),
            "sourceActivationSHA256": source.sha256,
            "sourceRestoreRootSHA256": source_root_sha,
            "teamID": source.receipt.team_id,
            "targetSetupID": target_setup,
            "targetApp": app,
        }
        request_raw = _json(core_request)
        admission_pid = self._source_pid(device, request.device_id)
        admission = "live" if admission_pid > 0 else "cold"
        admission_raw = _json({
            **source.admission_evidence(),
            "deviceID": request.device_id,
            "sourcePID": admission_pid,
            "sourceAdmission": admission,
            "sourceRestoreRootSHA256": source_root_sha,
            "targetSetupID": target_setup,
        })
        self.store.put_evidence("sourceActivation", source.raw)
        self._put_optional("sourceRestoreIntent", restore_intent)
        self._put_optional("sourceRestoreRoot", restore_root)
        self.store.put_evidence("sourceAdmission", admission_raw)
        self.store.bind_source(admission)
        self.store.put_evidence("appRequest", request_raw)
        return self._continue(request, device, preparation, explicit_resume=request.action == "resume")

    def _publish_source(self, request: ManagementRequest, device: Any, preparation: Any) -> None:
        from .management_preparation import _validate_management_request, _terminal_response_is_bound
        value = self.store.read()
        state = value["stages"]["sourceRequest"]["state"]
        if state == "confirmed":
            return
        raw = self.store.read_evidence("appRequest")
        previous = preparation.read_file(request.device_id, "managementRequest")
        if previous == raw:
            if state == "pending":
                self.store.record_intent("sourceRequest")
            self.store.confirm("sourceRequest", "appRequest")
            return
        if state != "pending":
            raise ManagementBridgeError("handoff-unknown")
        if previous is not None:
            response = preparation.read_file(request.device_id, "managementResponse")
            old = _validate_management_request(previous)
            old["_raw"] = previous
            if response is None or old["expectedDeviceUDID"] != request.device_id or not _terminal_response_is_bound(response, old):
                raise ManagementBridgeError("transaction-conflict")
            self.store.put_evidence("previousRequest", previous)
            self.store.put_evidence("previousResponse", response)
        old_control = preparation.read_file(request.device_id, "managementControl")
        if old_control is not None:
            self.store.put_evidence("previousControl", old_control)
        self._fresh_source_unchanged(device, preparation, value)
        self.store.record_intent("sourceRequest")
        try:
            preparation.publish_management_request(request.device_id, raw, previous=previous)
            self.store.confirm("sourceRequest", "appRequest")
        except Exception:
            self.store.mark_unknown("sourceRequest", "handoff-unknown")
            raise

    def _load_source(self, value: Mapping[str, Any]) -> SourceActivation:
        admission = _parse_object(self.store.read_evidence("sourceAdmission") or b"", limit=64 * 1024)
        return decode_source_activation(self.store.read_evidence("sourceActivation") or b"",
            device_id=value["header"]["deviceID"], installed_build=admission["sourceApp"]["build"],
            installed_team=admission["teamID"])

    def _load_candidate(self, request: ManagementRequest, value: Mapping[str, Any]) -> ArtifactIdentity | None:
        if request.kind == "repair":
            return None
        expected = _parse_object(self.store.read_evidence("targetArtifact") or b"", limit=32 * 1024)
        candidate = self.store.transaction_root(request.management_id) / "candidate.app"
        actual = self.artifact_validator.inspect(candidate, device_id=request.device_id, team_id=expected["teamID"])
        if expected != {"app": _app_dict(actual), "teamID": actual.team_id,
                        "expiresAt": actual.expires_at, "artifactSHA256": actual.artifact_sha256}:
            raise ManagementBridgeError("artifact-mismatch")
        return actual

    def _continue(self, request: ManagementRequest, device: Any, preparation: Any,
                  *, explicit_resume: bool) -> ManagementPayload:
        value = self.store.read()
        if self.store.is_terminal(value):
            return self._payload(value, request)
        if self.store.read_evidence("appRequest") is None:
            return self._initialize(request, device, preparation, value)
        self._validate_journal_typed(value)
        source = self._load_source(value)
        artifact = self._load_candidate(request, value)
        admission = _parse_object(self.store.read_evidence("sourceAdmission"), limit=64 * 1024)
        self._publish_source(request, device, preparation)
        value = self.store.read()
        if value["stages"]["sourceReady"]["state"] != "confirmed":
            if value["sourceAdmission"] == "live":
                self._quiesce(device, preparation, request, value, admission["sourcePID"], explicit_resume=explicit_resume)
            else:
                self._fresh_source_unchanged(device, preparation, value)
                if value["stages"]["sourceReady"]["state"] == "pending":
                    self.store.record_intent("sourceReady")
                self.store.confirm("sourceReady", "sourceAdmission")
        value = self._source_mutation_gate(device, preparation, request, self.store.read(), source,
            admission["sourceAdmission"], admission["sourcePID"], explicit_resume=explicit_resume)
        value = self._legacy_gate(preparation, request, value)
        value = self._target_flow(device, preparation, request, value, source, artifact)
        self.store.complete()
        return self._payload(self.store.read(), request)

    def resume(self, request: ManagementRequest) -> ManagementPayload:
        if request.action != "resume":
            raise ManagementBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        with self.store.lock():
            self._guard_other_operations()
            value = self.store.read()
            if value is None:
                raise ManagementBridgeError("transaction-unknown")
            self._bind_identity(value, request, allow_options=False)
            if self.store.is_terminal(value):
                return self._payload(value, request)
            transport = request.resume_selection.transport if request.resume_selection else value["revisions"][-1]["transport"]
            device, preparation = self._adapters(transport)
            observed = self._observe(device, request.device_id)
            if observed.transport != transport:
                raise ManagementBridgeError("revision-conflict")
            try:
                # Until the revision commit every adapter call below is read-only.
                self._reconcile_candidate_readonly(device, preparation, request, value)
                if request.resume_selection is not None:
                    value = self.store.append_revision(request.resume_selection.selection_id, transport)
                elif transport != value["revisions"][-1]["transport"]:
                    raise ManagementBridgeError("revision-conflict")
                committed_request = replace(request, connection_revision=len(self.store.read()["revisions"]) - 1)
                if self.store.read_evidence("releaseCommand") is not None:
                    latest = self.store.read()
                    attempts = latest.get("commands", {}).get("release", {}).get("attempts", [])
                    if not attempts or attempts[-1]["state"] != "confirmed":
                        self._publish_source(committed_request, device, preparation)
                        admission = _parse_object(self.store.read_evidence("sourceAdmission"), limit=64 * 1024)
                        self._control_action(device, preparation, committed_request, "release",
                                             admission["sourcePID"], explicit_resume=True)
                    self.store.release()
                    return self._payload(self.store.read(), committed_request)
                return self._continue(committed_request, device, preparation, explicit_resume=True)
            except Exception as error:
                self._record_failure(value, _error(error).code)
                raise _error(error)

    def release(self, request: ManagementRequest) -> ManagementPayload:
        if request.action != "release":
            raise ManagementBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        with self.store.lock():
            self._guard_other_operations()
            value = self.store.read()
            if value is None:
                raise ManagementBridgeError("transaction-unknown")
            self._bind_identity(value, request, allow_options=False)
            if self.store.is_terminal(value):
                return self._payload(value, request)
            if value["stages"]["mutationIntent"]["state"] != "pending":
                raise ManagementBridgeError("transaction-conflict")
            try:
                if value["stages"]["sourceRequest"]["state"] != "pending":
                    attempts = value.get("commands", {}).get("release", {}).get("attempts", [])
                    if not attempts or attempts[-1]["state"] != "confirmed":
                        if value["sourceAdmission"] != "live":
                            raise ManagementBridgeError("source-busy")
                        device, preparation = self._adapters(value["revisions"][-1]["transport"])
                        self._publish_source(request, device, preparation)
                        admission = _parse_object(self.store.read_evidence("sourceAdmission"), limit=64 * 1024)
                        self._control_action(device, preparation, request, "release", admission["sourcePID"], explicit_resume=False)
                self.store.release()
                return self._payload(self.store.read(), request)
            except Exception as error:
                self._record_failure(value, _error(error).code)
                raise _error(error)

    def _capture_source(self, device: Any, preparation: Any, request: ManagementRequest, value: Mapping[str, Any]) -> tuple[SourceActivation, bytes | None, bytes | None, bytes | None, Any, Any]:
        observed = self._observe(device, request.device_id)
        installed = self._installed(device, request.device_id)
        if not bool(getattr(installed, "exists", False)):
            raise ManagementBridgeError("identity-unverified")
        build, team = getattr(installed, "build", None), getattr(installed, "team_id", None)
        raw = self._read_activation(device, request.device_id)
        source = self._decode_source(raw, request.device_id, build, team)
        source.require_new_receipt_capacity()
        options = value["header"]["options"]
        if options is not None and options["teamID"] != source.receipt.team_id:
            raise ManagementBridgeError("identity-mismatch")
        restore_intent = preparation.read_file(request.device_id, "restoreIntent")
        restore_root = preparation.read_file(request.device_id, "restoreRoot")
        management_root = preparation.read_management_root(request.device_id)
        generations = self._read_generations(preparation, request.device_id, management_root)
        validate_source_lineage(source, request.device_id, restore_intent, restore_root, management_root, generations)
        return source, restore_intent, restore_root, management_root, installed, observed

    @staticmethod
    def _decode_source(raw: bytes | None, device_id: str, build: Any, team: Any) -> SourceActivation:
        if raw is None:
            raise ManagementBridgeError("identity-unverified")
        return decode_source_activation(raw, device_id=device_id, installed_build=build, installed_team=team)

    @staticmethod
    def _observe(device: Any, device_id: str) -> Any:
        try:
            value = device.observe(device_id)
        except Exception as error:
            raise _error(error, "device-disconnected")
        if getattr(value, "device_id", "").lower() != device_id.lower():
            raise ManagementBridgeError("identity-mismatch")
        if getattr(value, "trust", None) is not True:
            raise ManagementBridgeError("trust-required")
        if getattr(value, "developer_mode", None) is not True:
            raise ManagementBridgeError("developer-mode-required")
        if getattr(value, "transport", "").upper() not in {"USB", "NETWORK"}:
            raise ManagementBridgeError("device-disconnected")
        return value

    @staticmethod
    def _installed(device: Any, device_id: str) -> Any:
        try:
            value = device.installed_identity(device_id)
        except Exception as error:
            raise _error(error, "identity-unverified")
        if not isinstance(value, ManagementInstalledIdentity) and not hasattr(value, "exists"):
            raise ManagementBridgeError("identity-unverified")
        return value

    @staticmethod
    def _read_activation(device: Any, device_id: str) -> bytes | None:
        try:
            return device.read_activation(device_id)
        except Exception as error:
            raise _error(error, "identity-unverified")

    @staticmethod
    def _source_pid(device: Any, device_id: str) -> int:
        try:
            value = device.source_pid(device_id)
        except Exception as error:
            raise _error(error, "identity-unverified")
        if type(value) is not int or not 0 <= value <= 2_147_483_647:
            raise ManagementBridgeError("identity-mismatch")
        return value

    @staticmethod
    def _read_generations(preparation: Any, device_id: str, root: bytes | None) -> dict[str, Any]:
        return {identifier: generation for identifier in generation_ids(root)
                if (generation := preparation.read_management_generation(device_id, identifier)) is not None}

    def _candidate_artifact(self, request: ManagementRequest, value: Mapping[str, Any], observed: Any) -> ArtifactIdentity | None:
        if request.kind == "repair":
            return None
        from .management_protocol import _decode_options
        options = _decode_options(value["header"]["options"], kind=request.kind)
        if options is None:
            raise ManagementBridgeError("invalid-request")
        transaction = self.store.transaction_root(value["header"]["managementID"], create=True)
        candidate = transaction / "candidate.app"
        if self.store.read_evidence("targetArtifact") is not None:
            return self._load_candidate(request, value)
        if candidate.exists() or candidate.is_symlink():
            if candidate.is_symlink() or not candidate.is_dir():
                raise ManagementBridgeError("artifact-mismatch")
            # Snapshot publication can finish just before its evidence is
            # frozen. Reinspect that private copy instead of building a new
            # signature that could conflict with the already published copy.
            return self.artifact_validator.inspect(candidate, device_id=request.device_id, team_id=options.team_id)
        if options.source == "signedApp":
            if options.artifact_path is None:
                raise ManagementBridgeError("invalid-request")
            artifact = self.artifact_validator.inspect(options.artifact_path, device_id=request.device_id, team_id=options.team_id)
            return snapshot_artifact(artifact, candidate, self.artifact_validator,
                                     device_id=request.device_id, team_id=options.team_id)
        # The existing builder owns local files only. Isolate its output in
        # this management operation, never an M1 install-owning transaction.
        build_root = transaction / "local-builds" / str(uuid.uuid4())
        build_root.mkdir(parents=True, mode=0o700)
        build_config = SimpleNamespace(state_root=build_root,
            project_path=self.config.project_path, workspace_root=self.config.workspace_root,
            developer_directory=self.config.developer_directory)
        process = self.process or PinnedXcodeProcessAdapter(build_config)
        try:
            path = process.build(value["header"]["targetSetupID"], options.team_id, options.allow_provisioning_updates)
            expected = (build_root / "transactions" / value["header"]["targetSetupID"] / "build").resolve()
            Path(path).resolve().relative_to(expected)
            artifact = self.artifact_validator.inspect(path, device_id=request.device_id, team_id=options.team_id)
            return snapshot_artifact(artifact, candidate, self.artifact_validator,
                                     device_id=request.device_id, team_id=options.team_id)
        except ManagementBridgeError:
            raise
        except SetupBridgeError as error:
            raise _error(error)
        except Exception:
            raise ManagementBridgeError("artifact-mismatch")

    def _quiesce(self, device: Any, preparation: Any, request: ManagementRequest,
                 value: Mapping[str, Any], pid: int, *, explicit_resume: bool = False) -> dict[str, Any]:
        self._control_action(device, preparation, request, "quiesce", pid, explicit_resume=explicit_resume)
        value = self.store.read()
        if value["stages"]["sourceReady"]["state"] != "confirmed":
            if value["stages"]["sourceReady"]["state"] == "pending":
                self.store.record_intent("sourceReady")
            self.store.confirm("sourceReady", "sourceReceipt")
        return self.store.read()

    def _control_action(self, device: Any, preparation: Any, request: ManagementRequest,
                        action: str, pid: int, *, explicit_resume: bool = False) -> None:
        from .management_journal import _control_response
        value = self.store.read()
        self._fresh_source_unchanged(device, preparation, value)
        raw = self._control_raw(value, action)
        self.store.freeze_command(action, raw,
            prior_response=self.store.read_evidence("sourceReceipt"), actual_pid=pid)
        attempts = self.store.read()["commands"][action]["attempts"]
        publish = not attempts
        if attempts and attempts[-1]["state"] in {"confirmed", "supersededByRelease"}:
            return
        if attempts and attempts[-1]["state"] in {"inflight", "unknown"}:
            actual = preparation.read_file(request.device_id, "managementControl")
            if actual is None and explicit_resume:
                original_revision = attempts[-1]["revision"]
                if original_revision != len(value["revisions"]) - 1:
                    raise ManagementBridgeError("revision-conflict")
                if attempts[-1]["state"] == "inflight":
                    self.store.mark_unknown(action, "handoff-unknown")
                self.store.reconcile_command_absence(action, revision=original_revision, fresh_absent=True)
                publish = True
            elif actual != raw:
                raise ManagementBridgeError("handoff-unknown")
        if publish:
            self.store.begin_publication(action)
            try:
                # A crash may leave the terminal prior operation's command
                # in the mailbox before this operation's quiesce reached it.
                # Select only freshly matched immutable prior bytes. The
                # adapter independently checks the archived terminal request
                # and response before replacing a prior operation.
                actual = preparation.read_file(request.device_id, "managementControl")
                quiesce = self.store.read_evidence("quiesceCommand")
                archived = self.store.read_evidence("previousControl")
                if actual is None or actual == raw:
                    previous = actual
                elif action in {"seal", "release"} and actual == quiesce:
                    previous = quiesce
                elif action in {"quiesce", "release"} and actual == archived:
                    previous = archived
                else:
                    raise ManagementBridgeError("transaction-conflict")
                preparation.publish_control(request.device_id, raw, previous=previous,
                    previous_request=self.store.read_evidence("previousRequest"))
            except Exception:
                self.store.mark_unknown(action, "handoff-unknown")
                raise
        # The App observes commands on its real foreground loop. Publication
        # alone does not establish an owner lease or a source phase.
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            before = self._source_pid(device, request.device_id)
            response = preparation.read_file(request.device_id, "managementResponse")
            if before != pid:
                raise ManagementBridgeError("identity-mismatch")
            if response is not None:
                try:
                    _control_response(response, action, self.store.read_evidence("appRequest"))
                except ManagementBridgeError:
                    pass
                else:
                    if self._source_pid(device, request.device_id) != pid:
                        raise ManagementBridgeError("identity-mismatch")
                    self.store.confirm_command(action, response, actual_pid=pid)
                    return
            time.sleep(0.25)
        self.store.mark_unknown(action, "source-busy")
        raise ManagementBridgeError("source-busy")

    def _source_mutation_gate(self, device: Any, preparation: Any, request: ManagementRequest,
                              value: Mapping[str, Any], source: SourceActivation,
                              admission: str, pid: int, *, explicit_resume: bool = False) -> dict[str, Any]:
        current = self.store.read()
        if current["stages"]["sourceStop"]["state"] == "confirmed":
            return current
        stop_submitted = current["stages"]["sourceStop"]["state"] in {"inflight", "unknown"}
        sealed = current["stages"]["sourceSeal"]["state"] == "confirmed"
        self._fresh_source_unchanged(device, preparation, current, require_pid=not (stop_submitted or sealed))
        if stop_submitted and self._source_pid(device, request.device_id) == 0:
            return self.store.confirm("sourceStop", "sealedReceipt" if admission == "live" else "sourceAdmission")
        if current["stages"]["mutationIntent"]["state"] == "pending":
            self.store.record_intent("mutationIntent")
        if self.store.read()["stages"]["mutationIntent"]["state"] != "confirmed":
            self.store.confirm("mutationIntent", "sourceAdmission")
        if admission == "live" and current["stages"]["sourceSeal"]["state"] != "confirmed":
            self._control_action(device, preparation, request, "seal", pid, explicit_resume=explicit_resume)
            if self.store.read()["stages"]["sourceSeal"]["state"] == "pending":
                self.store.record_intent("sourceSeal")
            self.store.confirm("sourceSeal", "sealedReceipt")
        current = self.store.read()
        sealed = current["stages"]["sourceSeal"]["state"] == "confirmed"
        state = current["stages"]["sourceStop"]["state"]
        fresh_pid = self._source_pid(device, request.device_id)
        if state == "pending":
            if fresh_pid != pid and not (sealed and fresh_pid == 0):
                raise ManagementBridgeError("identity-mismatch")
            self.store.record_intent("sourceStop")
            if admission == "live" and fresh_pid != 0:
                try:
                    device.stop_owned_process(request.device_id, pid)
                except Exception:
                    self.store.mark_unknown("sourceStop", "handoff-unknown")
                    raise
            fresh_pid = self._source_pid(device, request.device_id)
        # A submitted stop can be reconciled by genuine absence. A changed
        # process is never adopted or stopped in its place.
        if fresh_pid != 0:
            raise ManagementBridgeError("app-running")
        return self.store.confirm("sourceStop", "sealedReceipt" if admission == "live" else "sourceAdmission")

    def _legacy_gate(self, preparation: Any, request: ManagementRequest, value: Mapping[str, Any]) -> dict[str, Any]:
        current = self.store.read() or value
        if current["stages"]["legacyTransition"]["state"] == "confirmed":
            return current
        if current["stages"]["legacy"]["state"] == "pending":
            present = {name: preparation.read_file(request.device_id, name) for name in _LEGACY_NAMES}
            self._validate_legacy_files(current, request, present)
            inventory = {
                "version": 1,
                "sourceSetupID": self._source_setup_id(current),
                "sourceNonce": self._source_nonce(current),
                "sourceApp": self._source_app(current),
                "deviceID": request.device_id,
                "rawManifestSHA256": self._source_manifest_sha(current),
                "entries": {},
            }
            for name, raw in present.items():
                inventory["entries"][_LEGACY_EVIDENCE[name]] = {
                    "present": raw is not None,
                    "byteCount": len(raw) if raw is not None else 0,
                    "sha256": _sha(raw) if raw is not None else None,
                }
                if raw is not None:
                    self.store.put_evidence(_LEGACY_EVIDENCE[name], raw)
            self.store.put_evidence("legacyInventory", _json(inventory))
            self.store.record_intent("legacy")
            self.store.confirm("legacy", "legacyInventory")
        stage_map = {
            "setupIncoming": "legacyIncomingRemoval",
            "setupReadbackRequest": "legacyReadbackRequestRemoval",
            "setupReadbackResponse": "legacyReadbackResponseRemoval",
        }
        for name, stage in stage_map.items():
            current = self.store.read() or value
            if current["stages"][stage]["state"] == "confirmed":
                continue
            raw = self.store.read_evidence(_LEGACY_EVIDENCE[name])
            if current["stages"][stage]["state"] == "pending":
                if preparation.read_file(request.device_id, name) != raw:
                    raise ManagementBridgeError("transaction-conflict")
                self.store.record_intent(stage)
            if raw is None:
                if preparation.read_file(request.device_id, name) is not None:
                    raise ManagementBridgeError("transaction-conflict")
                self.store.confirm(stage, "legacyInventory")
            else:
                removed = preparation.remove_legacy(request.device_id, name, raw)
                if removed is not True:
                    raise ManagementBridgeError("removal-unknown")
                self.store.confirm(stage, _LEGACY_EVIDENCE[name])
        current = self.store.read() or value
        if current["stages"]["legacyTransition"]["state"] == "pending":
            self.store.record_intent("legacyTransition")
            self.store.confirm("legacyTransition", "legacyInventory")
        return self.store.read() or value

    def _validate_legacy_files(self, value: Mapping[str, Any], request: ManagementRequest, present: Mapping[str, bytes | None]) -> None:
        source_app = self._source_app(value)
        source_setup = self._source_setup_id(value)
        source_manifest = self._source_manifest_sha(value)
        incoming = present.get("setupIncoming")
        readback_request = present.get("setupReadbackRequest")
        readback_response = present.get("setupReadbackResponse")
        if incoming is None and (readback_request is not None or readback_response is not None):
            raise ManagementBridgeError("transaction-conflict")
        if incoming is not None:
            try:
                incoming_value = _parse_object(incoming, limit=256 * 1024)
                setup_id = incoming_value.get("setupID")
                nonce = incoming_value.get("nonce")
                if setup_id != source_setup or nonce != self._source_nonce(value):
                    raise ValueError()
                PinnedPymobiledeviceAdapter._decode_formal_manifest(
                    incoming, device_id=request.device_id, setup_id=setup_id, nonce=nonce
                )
                if incoming_value.get("app") != source_app or incoming_value.get("expectedDeviceUDID") != request.device_id:
                    raise ValueError()
                if _sha(incoming) != source_manifest:
                    raise ValueError()
            except Exception:
                raise ManagementBridgeError("transaction-conflict") from None
        if readback_request is not None:
            try:
                request_value = _parse_object(readback_request, limit=64 * 1024)
                if set(request_value) != {"version", "setupID", "nonce", "expectedDeviceUDID", "app"} or request_value.get("version") != 1:
                    raise ValueError()
                if request_value.get("setupID") != source_setup or request_value.get("expectedDeviceUDID") != request.device_id or request_value.get("app") != source_app:
                    raise ValueError()
                nonce = request_value.get("nonce")
                if nonce != self._source_nonce(value):
                    raise ValueError()
            except Exception:
                raise ManagementBridgeError("transaction-conflict") from None
        if readback_response is not None:
            if readback_request is None:
                raise ManagementBridgeError("transaction-conflict")
            try:
                request_value = _parse_object(readback_request, limit=64 * 1024)
                decoded = PinnedPymobiledeviceAdapter._decode_readback(
                    readback_response,
                    device_id=request.device_id,
                    setup_id=request_value["setupID"],
                    nonce=request_value["nonce"],
                )
                if decoded.build and decoded.build != source_app["build"]:
                    raise ValueError()
                if decoded.executable_sha256 != source_app["executableSHA256"] or decoded.profile_sha256 != source_app["profileSHA256"]:
                    raise ValueError()
            except Exception:
                raise ManagementBridgeError("transaction-conflict") from None

    def _source_setup_id(self, value: Mapping[str, Any]) -> str:
        raw = self.store.read_evidence("sourceActivation")
        if raw is None:
            raise ManagementBridgeError("transaction-conflict")
        try:
            parsed = _parse_object(raw, limit=256 * 1024)
            return parsed["activeSetupID"]
        except Exception:
            raise ManagementBridgeError("transaction-conflict") from None

    def _source_nonce(self, value: Mapping[str, Any]) -> str:
        raw = self.store.read_evidence("sourceActivation")
        try:
            parsed = _parse_object(raw or b"", limit=256 * 1024)
            receipt = next(item for item in parsed["receipts"] if item.get("setupID") == parsed["activeSetupID"])
            return receipt["nonce"]
        except Exception:
            raise ManagementBridgeError("transaction-conflict") from None

    def _source_app(self, value: Mapping[str, Any]) -> dict[str, Any]:
        raw = self.store.read_evidence("sourceAdmission")
        try:
            return _parse_object(raw or b"", limit=64 * 1024)["sourceApp"]
        except Exception:
            raise ManagementBridgeError("transaction-conflict") from None

    def _source_manifest_sha(self, value: Mapping[str, Any]) -> str:
        raw = self.store.read_evidence("sourceActivation")
        try:
            parsed = _parse_object(raw or b"", limit=256 * 1024)
            receipt = next(item for item in parsed["receipts"] if item.get("setupID") == parsed["activeSetupID"])
            return receipt["rawManifestSHA256"]
        except Exception:
            raise ManagementBridgeError("transaction-conflict") from None

    def _target_flow(self, device: Any, preparation: Any, request: ManagementRequest,
                     value: Mapping[str, Any], source: SourceActivation,
                     artifact: ArtifactIdentity | None) -> dict[str, Any]:
        from .management_target import ManagementTargetDriver
        driver = ManagementTargetDriver(self.config, self.store, device, preparation)
        identity = source.identity if artifact is None else PreparationAppIdentity(
            artifact.bundle_id, artifact.build, artifact.profile_sha256,
            artifact.executable_sha256, artifact.team_id, artifact.expires_at)
        if request.kind == "renew":
            if artifact is None:
                raise ManagementBridgeError("artifact-mismatch")
            driver.publish_readback_metadata(request, identity)
            current = self.store.read()
            state = current["stages"]["update"]["state"]
            if state == "pending":
                self._fresh_source_unchanged(device, preparation, current, require_pid=False)
                if self._source_pid(device, request.device_id) != 0:
                    raise ManagementBridgeError("app-running")
                self.store.record_intent("update")
                try:
                    result = device.explicit_upgrade(request.device_id, artifact)
                    if result.confirmed is not True:
                        raise ManagementBridgeError("update-unknown")
                    observation = {"version": 1, "deviceID": result.device_id,
                        "bundleID": result.bundle_id, "build": result.build,
                        "teamID": result.team_id, "artifactSHA256": artifact.artifact_sha256}
                    if (result.device_id.lower() != request.device_id or result.bundle_id != artifact.bundle_id or
                            result.build != artifact.build or result.team_id != artifact.team_id):
                        raise ManagementBridgeError("identity-mismatch")
                    self.store.put_evidence("updateObservation", _json(observation))
                    self.store.confirm("update", "updateObservation")
                except Exception as error:
                    self.store.mark_unknown("update", "update-unknown")
                    raise _error(error, "update-unknown")
            elif state != "confirmed":
                self._reconcile_upgrade_readonly(preparation, request, artifact, source)
        driver.advance(request, source, identity)
        return self.store.read()

    def _reconcile_upgrade_readonly(self, preparation: Any, request: ManagementRequest,
                                    artifact: ArtifactIdentity, source: SourceActivation) -> None:
        value = self.store.read()
        raw = preparation.read_file(request.device_id, "setupReadbackResponse")
        planned = self.store.read_evidence("readbackPlan")
        if raw is None or planned is None or preparation.read_file(request.device_id, "setupReadbackRequest") != planned:
            raise ManagementBridgeError("update-unknown")
        readback = PinnedPymobiledeviceAdapter._decode_readback(raw,
            device_id=request.device_id, setup_id=value["header"]["targetSetupID"], nonce=value["header"]["setupNonce"])
        if (readback.build != artifact.build or readback.executable_sha256 != artifact.executable_sha256 or
                readback.profile_sha256 != artifact.profile_sha256 or readback.pairing_sha256 != source.receipt.pairing_sha256):
            raise ManagementBridgeError("update-unknown")
        self.store.put_evidence("targetReadback", raw)
        self.store.confirm("update", "targetReadback")

    def _fresh_source_unchanged(self, device: Any, preparation: Any, value: Mapping[str, Any], *, require_pid: bool = True) -> None:
        evidence = self.store.read_evidence("sourceActivation")
        if evidence is None or device.read_activation(value["header"]["deviceID"]) != evidence:
            raise ManagementBridgeError("identity-mismatch")
        root = self.store.read_evidence("sourceRestoreRoot")
        if preparation.read_file(value["header"]["deviceID"], "restoreRoot") != root:
            raise ManagementBridgeError("identity-mismatch")
        if preparation.read_file(value["header"]["deviceID"], "restoreIntent") != self.store.read_evidence("sourceRestoreIntent"):
            raise ManagementBridgeError("identity-mismatch")
        # Core legitimately appends this operation's preparing/sealed record
        # after publication. Only the first publication compares the original
        # lineage snapshot; later gates validate the exact original request
        # and source lease/receipt instead.
        if (value["stages"]["sourceRequest"]["state"] == "pending" and
                preparation.read_management_root(value["header"]["deviceID"]) != self.store.read_evidence("sourceManagementRoot")):
            raise ManagementBridgeError("identity-mismatch")
        admission = _parse_object(self.store.read_evidence("sourceAdmission") or b"", limit=64 * 1024)
        source = decode_source_activation(evidence, device_id=value["header"]["deviceID"],
            installed_build=admission["sourceApp"]["build"], installed_team=admission["teamID"])
        source.require_new_receipt_capacity()
        installed = self._installed(device, value["header"]["deviceID"])
        if not installed.exists or installed.build != source.identity.build or installed.team_id != source.identity.team_id:
            raise ManagementBridgeError("identity-mismatch")
        self._observe(device, value["header"]["deviceID"])
        if require_pid and self._source_pid(device, value["header"]["deviceID"]) != admission["sourcePID"]:
            raise ManagementBridgeError("identity-mismatch")

    def _reconcile_candidate_readonly(self, device: Any, preparation: Any,
                                      request: ManagementRequest, value: Mapping[str, Any]) -> None:
        from .management_journal import _control_response
        if self.store.read_evidence("appRequest") is None or value["sourceAdmission"] is None:
            return
        source = self._load_source(value)
        admission = _parse_object(self.store.read_evidence("sourceAdmission"), limit=64 * 1024)
        raw = self.store.read_evidence("appRequest")
        if value["stages"]["sourceRequest"]["state"] in {"inflight", "unknown"}:
            if preparation.read_file(request.device_id, "managementRequest") == raw:
                self.store.confirm("sourceRequest", "appRequest")
        commands = value.get("commands", {})
        for action in ("quiesce", "seal", "release"):
            attempts = commands.get(action, {}).get("attempts", [])
            if not attempts or attempts[-1]["state"] not in {"inflight", "unknown", "absentAfterReconcile"}:
                continue
            before = self._source_pid(device, request.device_id)
            response = preparation.read_file(request.device_id, "managementResponse")
            if response is None or before != admission["sourcePID"] or before <= 0:
                continue
            try:
                _control_response(response, action, raw)
            except ManagementBridgeError:
                continue
            if self._source_pid(device, request.device_id) != before:
                raise ManagementBridgeError("identity-mismatch")
            self.store.confirm_command(action, response, actual_pid=before)
        for stage, evidence in (("sourceReady", "sourceReceipt"), ("sourceSeal", "sealedReceipt")):
            current = self.store.read()
            if self.store.read_evidence(evidence) is not None and current["stages"][stage]["state"] != "confirmed":
                if current["stages"][stage]["state"] == "pending":
                    self.store.record_intent(stage)
                self.store.confirm(stage, evidence)
        current = self.store.read()
        if current["stages"]["sourceStop"]["state"] in {"inflight", "unknown"}:
            if self._source_pid(device, request.device_id) == 0:
                self._fresh_source_unchanged(device, preparation, current, require_pid=False)
                self.store.confirm("sourceStop", "sealedReceipt" if admission["sourceAdmission"] == "live" else "sourceAdmission")
        # A durable removal intent plus its checked archive permits a genuine
        # absence to reconcile; it never permits deleting on the candidate.
        for logical, stage in (("setupIncoming", "legacyIncomingRemoval"),
                               ("setupReadbackRequest", "legacyReadbackRequestRemoval"),
                               ("setupReadbackResponse", "legacyReadbackResponseRemoval")):
            current = self.store.read()
            if current["stages"][stage]["state"] in {"inflight", "unknown"} and preparation.read_file(request.device_id, logical) is None:
                evidence = _LEGACY_EVIDENCE[logical]
                self.store.confirm(stage, evidence if self.store.read_evidence(evidence) is not None else "legacyInventory")
        current = self.store.read()
        artifact = self._load_candidate(request, current)
        if artifact is not None and current["stages"]["update"]["state"] in {"inflight", "unknown"}:
            try:
                self._reconcile_upgrade_readonly(preparation, request, artifact, source)
            except ManagementBridgeError as error:
                if error.code != "update-unknown":
                    raise
        target_stages = ("pairCreate", "pairDelivery", "readbackPublish", "readbackLaunch", "readbackStop",
                         "support", "formalInput", "formalLaunch", "activation", "finalSupport")
        current = self.store.read()
        if any(current["stages"][stage]["state"] in {"inflight", "unknown"} for stage in target_stages):
            from .management_target import ManagementTargetDriver
            identity = source.identity if artifact is None else PreparationAppIdentity(
                artifact.bundle_id, artifact.build, artifact.profile_sha256, artifact.executable_sha256,
                artifact.team_id, artifact.expires_at)
            ManagementTargetDriver(self.config, self.store, device, preparation).reconcile_readonly(request, source, identity)

    def _control_raw(self, value: Mapping[str, Any], action: str) -> bytes:
        request = self.store.read_evidence("appRequest")
        if request is None:
            raise ManagementBridgeError("transaction-conflict")
        parsed = _parse_object(request, limit=32 * 1024)
        return _json({
            "version": 1,
            "managementID": value["header"]["managementID"],
            "nonce": value["header"]["nonce"],
            "requestSHA256": _sha(request),
            "action": action,
        })

    def _put_optional(self, name: str, raw: bytes | None) -> None:
        if raw is not None:
            self.store.put_evidence(name, raw)

    def _record_failure(self, value: Mapping[str, Any], code: str) -> None:
        with contextlib.suppress(Exception):
            self.store.fail(code)

    def _target_identity(self) -> PreparationAppIdentity | None:
        raw = self.store.read_evidence("targetIdentity")
        if raw is None:
            return None
        identity = _parse_object(raw, limit=32 * 1024)
        if set(identity) != {"bundleID", "build", "profileSHA256", "executableSHA256", "teamID", "expiresAt"}:
            raise ManagementBridgeError("transaction-unknown")
        app = _validate_app({key: identity[key] for key in (
            "bundleID", "build", "profileSHA256", "executableSHA256")}, code="transaction-unknown")
        return _identity_from_app(app, _team(identity["teamID"], code="transaction-unknown"),
                                  _expiry(identity["expiresAt"], code="transaction-unknown"))

    def _validate_journal_typed(self, value: Mapping[str, Any]) -> None:
        """Revalidate saved full Core/App evidence without contacting a device.

        Stage flags and hashes alone are not completion proof. Partial local
        preparation remains readable, but any saved adoption must bind the
        actual full activation record and the exact frozen formal input.
        """
        from .management_preparation import _terminal_response_is_bound, _validate_management_request
        from .management_target import _receipt_matches
        try:
            header, stages = value["header"], value["stages"]
            identity = self._target_identity()
            app_raw = self.store.read_evidence("appRequest")
            if app_raw is None:
                if value["sourceAdmission"] is not None and self.store.read_evidence("sourceAdmission") is None:
                    raise ValueError()
                if any(stages[name]["state"] != "pending" for name in stages if name not in {"artifact", "release"}):
                    raise ValueError()
                return
            core = _validate_management_request(app_raw)
            core["_raw"] = app_raw
            for key, expected in (
                ("managementID", header["managementID"]), ("nonce", header["nonce"]),
                ("expectedDeviceUDID", header["deviceID"]), ("kind", header["kind"]),
                ("targetSetupID", header["targetSetupID"]),
            ):
                if core[key] != expected:
                    raise ValueError()
            if identity is None or identity.app() != core["targetApp"] or identity.team_id != core["teamID"]:
                raise ValueError()
            source = self._load_source(value)
            source.require_new_receipt_capacity()
            admission = _parse_object(self.store.read_evidence("sourceAdmission") or b"", limit=64 * 1024)
            pid = admission.get("sourcePID")
            root = self.store.read_evidence("sourceRestoreRoot")
            root_sha = _sha(root) if root is not None else None
            if (type(pid) is not int or not 0 <= pid <= 2_147_483_647 or
                    admission != {**source.admission_evidence(), "deviceID": header["deviceID"],
                        "sourcePID": pid, "sourceAdmission": "live" if pid > 0 else "cold",
                        "sourceRestoreRootSHA256": root_sha, "targetSetupID": header["targetSetupID"]} or
                    value["sourceAdmission"] != admission["sourceAdmission"] or
                    core["sourceActivationSHA256"] != source.sha256 or
                    core["sourceApp"] != source.identity.app() or
                    core["sourceSetupID"] != source.receipt.setup_id or
                    core["sourceRestoreRootSHA256"] != root_sha or
                    core["teamID"] != source.identity.team_id):
                raise ValueError()
            if header["kind"] == "repair" and identity != source.identity:
                raise ValueError()
            if header["options"] is not None and header["options"]["teamID"] != identity.team_id:
                raise ValueError()
            generation_ids(self.store.read_evidence("sourceManagementRoot"))
            artifact_raw = self.store.read_evidence("targetArtifact")
            artifact = None
            if artifact_raw is not None:
                artifact = _parse_object(artifact_raw, limit=32 * 1024)
                if (header["kind"] != "renew" or set(artifact) != {"app", "teamID", "expiresAt", "artifactSHA256"} or
                        artifact["app"] != identity.app() or artifact["teamID"] != identity.team_id or
                        artifact["expiresAt"] != identity.expires_at):
                    raise ValueError()
                _hash(artifact["artifactSHA256"], code="transaction-unknown")
            if header["kind"] == "renew" and artifact is None:
                raise ValueError()
            if header["kind"] == "repair" and any(stages[name]["state"] != "pending" for name in ("artifact", "update")):
                raise ValueError()
            if header["kind"] == "renew" and any(stages.get(name, {"state": "pending"})["state"] != "pending" for name in ("pairCreate", "pairDelivery")):
                raise ValueError()

            # Pairing plans carry no positive import authority. Their binding
            # is nevertheless immutable and required by every later proof.
            pairing_raw = self.store.read_evidence("pairingBinding")
            pairing = _parse_object(pairing_raw, limit=32 * 1024) if pairing_raw is not None else None
            if pairing is not None:
                tx = source.receipt.pairing_transaction_id if header["kind"] == "renew" else str(
                    uuid.uuid5(uuid.UUID(header["targetSetupID"]), "gofly-management-repair-pairing-v1"))
                digest = _hash(pairing.get("sha256"), code="transaction-unknown")
                if pairing != {"version": 1, "managementID": header["managementID"],
                        "targetSetupID": header["targetSetupID"], "deviceID": header["deviceID"],
                        "transactionID": tx, "sha256": digest}:
                    raise ValueError()
                if header["kind"] == "renew" and digest != source.receipt.pairing_sha256:
                    raise ValueError()
                planned = _parse_object(self.store.read_evidence("pairingPlan") or b"", limit=32 * 1024)
                if planned != {"version": 1, "kind": header["kind"], "managementID": header["managementID"],
                        "targetSetupID": header["targetSetupID"], "setupNonce": header["setupNonce"],
                        "deviceID": header["deviceID"], "pairingTransactionID": tx,
                        "pairingSHA256": digest if header["kind"] == "renew" else None}:
                    raise ValueError()
            readback_raw = self.store.read_evidence("targetReadback")
            readback_plan = self.store.read_evidence("readbackPlan")
            if readback_plan is not None and readback_plan != _json({
                    "version": 1, "setupID": header["targetSetupID"], "nonce": header["setupNonce"],
                    "expectedDeviceUDID": header["deviceID"], "app": identity.app()}):
                raise ValueError()
            if readback_raw is not None:
                if readback_plan is None:
                    raise ValueError()
                readback = PinnedPymobiledeviceAdapter._decode_readback(readback_raw,
                    device_id=header["deviceID"], setup_id=header["targetSetupID"], nonce=header["setupNonce"])
                expected_pair = pairing["sha256"] if pairing is not None else source.receipt.pairing_sha256
                if (readback.build != identity.build or readback.profile_sha256 != identity.profile_sha256 or
                        readback.executable_sha256 != identity.executable_sha256 or readback.pairing_sha256 != expected_pair):
                    raise ValueError()
            if stages["readback"]["state"] == "confirmed" and readback_raw is None:
                raise ValueError()
            absence_raw = self.store.read_evidence("readbackAbsenceObservation")
            if absence_raw is not None:
                absence = _parse_object(absence_raw, limit=32 * 1024)
                if (readback_raw is None or readback_plan is None or absence != {
                        "version": 1, "deviceID": header["deviceID"], "setupID": header["targetSetupID"],
                        "nonce": header["setupNonce"], "readbackPlanSHA256": _sha(readback_plan), "pid": 0}):
                    raise ValueError()
            for evidence_name, launch in (("readbackProcess", "readbackLaunch"), ("formalProcess", "formalLaunch")):
                process_raw = self.store.read_evidence(evidence_name)
                if process_raw is None:
                    continue
                process = _parse_object(process_raw, limit=32 * 1024)
                owned_pid = process.get("pid")
                if (type(owned_pid) is not int or not 0 < owned_pid <= 2_147_483_647 or
                        process != {"version": 1, "deviceID": header["deviceID"],
                            "setupID": header["targetSetupID"], "nonce": header["setupNonce"], "pid": owned_pid} or
                        stages.get(launch, {"state": "pending"})["state"] == "pending"):
                    raise ValueError()
            if stages.get("readbackStop", {"state": "pending"})["state"] == "confirmed":
                if self.store.read_evidence("readbackProcess") is None and absence_raw is None:
                    raise ValueError()
            if stages["update"]["state"] == "confirmed":
                observation_raw = self.store.read_evidence("updateObservation")
                if observation_raw is not None:
                    observation = _parse_object(observation_raw, limit=32 * 1024)
                    if observation != {"version": 1, "deviceID": header["deviceID"], "bundleID": identity.bundle_id,
                            "build": identity.build, "teamID": identity.team_id, "artifactSHA256": artifact["artifactSHA256"]}:
                        raise ValueError()
                elif readback_raw is None:
                    raise ValueError()

            support_raw = self.store.read_evidence("supportObservation")
            support = _parse_object(support_raw, limit=64 * 1024) if support_raw is not None else None
            formal_raw = self.store.read_evidence("formalPlan")
            plan = None
            if formal_raw is not None:
                if support is None or pairing is None:
                    raise ValueError()
                plan = build_formal_setup_input(device_id=header["deviceID"], setup_id=header["targetSetupID"],
                    nonce=header["setupNonce"], artifact=identity, pairing_transaction_id=pairing["transactionID"],
                    pairing_sha256=pairing["sha256"], support=support)
                if plan.raw_manifest != formal_raw:
                    raise ValueError()
            if stages["support"]["state"] == "confirmed" and support is None:
                raise ValueError()
            final_raw = self.store.read_evidence("finalSupportObservation")
            if final_raw is not None and _parse_object(final_raw, limit=64 * 1024) != support:
                raise ValueError()
            if stages["finalSupport"]["state"] == "confirmed" and final_raw is None:
                raise ValueError()
            target_raw = self.store.read_evidence("activationReceipt")
            if target_raw is not None:
                if plan is None or stages.get("formalLaunch", {"state": "pending"})["state"] == "pending":
                    raise ValueError()
                target = PinnedPymobiledeviceAdapter._decode_activation_receipt(target_raw,
                    device_id=header["deviceID"], setup_id=header["targetSetupID"], nonce=header["setupNonce"])
                _receipt_matches(target, device_id=header["deviceID"], setup_id=header["targetSetupID"],
                    nonce=header["setupNonce"], identity=identity, pairing_transaction_id=pairing["transactionID"],
                    pairing_sha256=pairing["sha256"], support=support, plan=plan)
            if stages["pairing"]["state"] == "confirmed" and target_raw is None:
                raise ValueError()
            adoption = self.store.read_evidence("adoptionReceipt")
            if adoption is not None:
                if (target_raw is None or not _terminal_response_is_bound(adoption, core) or
                        _parse_object(adoption, limit=64 * 1024)["targetActivationSHA256"] != _sha(target_raw)):
                    raise ValueError()
            if stages["activation"]["state"] == "confirmed" and adoption is None:
                raise ValueError()
        except Exception:
            raise ManagementBridgeError("transaction-unknown") from None

    def _guard_other_operations(self) -> None:
        try:
            try:
                from ..Setup.setup_journal import JournalStore
                from ..Reinstall.reinstall_journal import ReinstallJournalStore, is_terminal_journal
            except ImportError:
                from Setup.setup_journal import JournalStore
                from Reinstall.reinstall_journal import ReinstallJournalStore, is_terminal_journal
            setup_store = JournalStore(self.config.state_root)
            setup = setup_store.read()
            if setup is not None and not setup_store._completed_eligible(setup):
                raise ManagementBridgeError("transaction-conflict")
            reinstall = ReinstallJournalStore(self.config.state_root).read()
            if reinstall is not None and not is_terminal_journal(reinstall):
                raise ManagementBridgeError("transaction-conflict")
        except ManagementBridgeError:
            raise
        except SetupBridgeError as error:
            raise _error(error)
        except Exception as error:
            if isinstance(error, FileNotFoundError):
                return
            raise ManagementBridgeError("storage-unavailable") from error

    @staticmethod
    def _bind_identity(value: Mapping[str, Any], request: ManagementRequest, *, allow_options: bool, resume: bool = False) -> None:
        header = value.get("header")
        if not isinstance(header, Mapping):
            raise ManagementBridgeError("transaction-unknown")
        if any(header.get(key) != expected for key, expected in (
            ("managementID", request.management_id), ("deviceID", request.device_id),
            ("kind", request.kind), ("selectionID", request.selection_id), ("transport", request.transport),
        )):
            raise ManagementBridgeError("transaction-conflict")
        if request.connection_revision != len(value.get("revisions", [])) - 1:
            raise ManagementBridgeError("revision-conflict")
        if not resume and header.get("selectionID") != request.selection_id:
            raise ManagementBridgeError("transaction-conflict")
        if allow_options and request.options is not None and header.get("options") != request.options.as_dict():
            raise ManagementBridgeError("transaction-conflict")

    def _payload(self, value: Mapping[str, Any], request: ManagementRequest) -> ManagementPayload:
        self._validate_journal_typed(value)
        stages = value["stages"]
        skipped = {"artifact", "update"} if request.kind == "repair" else {"pairCreate", "pairDelivery"}
        if value.get("sourceAdmission") == "cold":
            skipped.add("sourceSeal")
        relevant = [(key, phase) for key, phase in _STAGE_MAP if key in stages and key not in skipped]
        stage = next((phase for key, phase in relevant if stages[key]["state"] != "confirmed"), "adoption")
        outcome = "failed" if value.get("outcome") == "failed" else "inProgress"
        # Submitted effects take priority over an earlier optional/pending
        # checkpoint; they cannot be presented as a safe fresh operation.
        for key, phase in relevant:
            if stages[key]["state"] in {"unknown", "inflight"}:
                stage, outcome = phase, "unknown"
                break
        for action, phase in (("release", "release"), ("seal", "seal"), ("quiesce", "source")):
            attempts = value.get("commands", {}).get(action, {}).get("attempts", [])
            if attempts and attempts[-1]["state"] in {"unknown", "inflight", "absentAfterReconcile"}:
                stage, outcome = phase, "unknown"
                break
        if stages["complete"]["state"] == "confirmed":
            stage, outcome = "complete", "confirmed"
        elif stages["release"]["state"] == "confirmed":
            stage, outcome = "release", "confirmed"
        proof = {
            "sourceBound": value.get("sourceAdmission") in {"live", "cold"},
            "sourceQuiescent": value.get("sourceAdmission") == "live" and stages["sourceReady"]["state"] == "confirmed",
            "mutationSealed": stages["sourceSeal"]["state"] == "confirmed",
            "updateConfirmed": stages["update"]["state"] == "confirmed",
            "pairingImported": stages["pairing"]["state"] == "confirmed",
            "supportObserved": stages["finalSupport"]["state"] == "confirmed" or stages["support"]["state"] == "confirmed",
            "adoptionCommitted": stages["activation"]["state"] == "confirmed" and "adoptionReceipt" in value["evidence"],
        }
        identity = self._target_identity()
        receipt_raw = self.store.read_evidence("adoptionReceipt")
        receipt = _parse_object(receipt_raw, limit=64 * 1024) if receipt_raw is not None else None
        # Metadata never becomes a committed adoption merely by existing.
        if not proof["adoptionCommitted"]:
            receipt = None
        forbidden = ("mutationIntent", "sourceSeal", "sourceStop", "legacy", "update", "pairing",
                     "support", "readback", "formalInput", "activation", "finalSupport",
                     "pairCreate", "pairDelivery", "readbackPublish", "readbackLaunch", "readbackStop", "formalLaunch")
        can_release = (
            stage in {"artifact", "source"} and outcome in {"inProgress", "unknown", "failed"}
            and all(stages.get(name, {"state": "pending"})["state"] == "pending" for name in forbidden)
            and stages["artifact"]["state"] not in {"inflight", "unknown"}
            and stages["sourceReady"]["state"] not in {"inflight", "unknown"}
            and (stages["sourceRequest"]["state"] == "pending" or (
                value.get("sourceAdmission") == "live" and
                bool(value.get("commands", {}).get("quiesce", {}).get("attempts"))))
            and not any(proof[key] for key in ("mutationSealed", "updateConfirmed", "pairingImported", "adoptionCommitted"))
        )
        can_resume = outcome != "confirmed"
        return ManagementPayload(
            stage, outcome, can_resume, can_release, value.get("sourceAdmission"),
            len(value["revisions"]) - 1, value["revisions"][-1]["transport"], proof,
            identity.app() if identity is not None else None,
            identity.team_id if identity is not None else None,
            identity.expires_at if identity is not None else None, receipt,
        )


__all__ = ["ManagementPayload", "ManagementProducer"]
