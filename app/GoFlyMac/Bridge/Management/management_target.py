"""Transport-bound target preparation for protocol-5 management.

The management producer owns source admission and the Core request.  This
module owns the target half of the operation after those bytes have been
frozen.  Every device effect has a journal intent before it is entered and a
typed readback before the corresponding stage is confirmed.  In particular,
the Mac never manufactures a Core adoption receipt: the terminal response is
read from the App's fixed ``managementResponse`` file and validated against
the exact request bytes.

This driver deliberately accepts pathless :class:`PreparationAppIdentity`
metadata.  Artifact/path authority remains with the producer and Setup's
formal input adapter; this module only binds the metadata and the actual
closed Setup receipts.
"""

from __future__ import annotations

import hashlib
import json
import re
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

try:
    from ..Setup.setup_adapters import (
        FormalSetupInput,
        PairingObservation,
        PinnedPymobiledeviceAdapter,
        build_formal_setup_input,
    )
    from ..Setup.setup_producer import support_method
    from ..Setup.setup_support import validate_generation
    from .management_adapters import PinnedManagementDeviceAdapter
    from .management_journal import ManagementJournal
    from .management_preparation import (
        _strict_object,
        _terminal_response_is_bound,
        _validate_management_request,
        ManagementPreparationAdapter,
    )
    from .management_protocol import ManagementBridgeError, ManagementRequest
    from .management_source import PreparationAppIdentity, SourceActivation
except ImportError:  # direct execution from the packaged Bridge root
    from Setup.setup_adapters import (  # type: ignore
        FormalSetupInput,
        PairingObservation,
        PinnedPymobiledeviceAdapter,
        build_formal_setup_input,
    )
    from Setup.setup_producer import support_method  # type: ignore
    from Setup.setup_support import validate_generation  # type: ignore
    from Management.management_adapters import PinnedManagementDeviceAdapter  # type: ignore
    from Management.management_journal import ManagementJournal  # type: ignore
    from Management.management_preparation import (  # type: ignore
        _strict_object,
        _terminal_response_is_bound,
        _validate_management_request,
        ManagementPreparationAdapter,
    )
    from Management.management_protocol import ManagementBridgeError, ManagementRequest  # type: ignore
    from Management.management_source import PreparationAppIdentity, SourceActivation  # type: ignore


_UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
_HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")
_TARGET_PAIRING_NAMESPACE = "gofly-management-repair-pairing-v1"
_READBACK_POLL_SECONDS = 30.0
_ACTIVATION_POLL_SECONDS = 1800.0
_POLL_INTERVAL_SECONDS = 0.05


def _error(code: str = "operation-failed") -> ManagementBridgeError:
    return ManagementBridgeError(code)


def _json(value: Any) -> bytes:
    try:
        raw = json.dumps(
            value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
        ).encode("utf-8")
    except (TypeError, ValueError, UnicodeError, RecursionError):
        raise _error() from None
    return raw


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _uuid(value: Any) -> str:
    if not isinstance(value, str) or _UUID_RE.fullmatch(value) is None:
        raise _error("identity-mismatch")
    return value


def _hash(value: Any) -> str:
    if not isinstance(value, str) or _HEX64_RE.fullmatch(value) is None:
        raise _error("identity-mismatch")
    return value


def _bounded_text(value: Any, *, maximum: int = 256) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > maximum:
        raise _error("support-unavailable")
    if any(ord(character) < 0x20 or ord(character) == 0x7F for character in value):
        raise _error("support-unavailable")
    return value


def _identity_app(identity: PreparationAppIdentity) -> dict[str, str]:
    if not isinstance(identity, PreparationAppIdentity):
        raise _error("identity-unverified")
    try:
        value = identity.app()
    except Exception:
        raise _error("identity-unverified") from None
    if not isinstance(value, dict) or set(value) != {
        "bundleID", "build", "profileSHA256", "executableSHA256"
    }:
        raise _error("identity-unverified")
    return value


def _observation_value(value: Any, name: str, default: Any = None) -> Any:
    if isinstance(value, Mapping):
        return value.get(name, default)
    return getattr(value, name, default)


def _pairing_observation(value: Any, *, device_id: str) -> tuple[str, str]:
    if not isinstance(value, PairingObservation):
        state = _observation_value(value, "state")
        observed_device = _observation_value(value, "device_id")
        digest = _observation_value(value, "sha256")
    else:
        state, observed_device, digest = value.state, value.device_id, value.sha256
    if state != "verified" or not isinstance(observed_device, str) or observed_device.lower() != device_id.lower():
        raise _error("pairing-unknown")
    return _uuid_or_hashless_pairing_digest(digest)


def _uuid_or_hashless_pairing_digest(value: Any) -> tuple[str, str]:
    # PairingObservation does not carry its transaction ID.  The caller adds
    # the frozen transaction ID; this helper only closes the returned digest.
    if not isinstance(value, str) or _HEX64_RE.fullmatch(value) is None:
        raise _error("pairing-unknown")
    return "", value


def _support_map(observation: Any, generation: Any) -> dict[str, Any]:
    method = _observation_value(observation, "method")
    os_version = _observation_value(observation, "os_version")
    generation_id = _observation_value(observation, "generation_id")
    identifier = _observation_value(observation, "identifier")
    version = _observation_value(observation, "version")
    if (
        _observation_value(observation, "observed") is not True
        or method not in {"personalized", "cryptex"}
        or not isinstance(os_version, str)
    ):
        raise _error("support-unavailable")
    _bounded_text(generation_id)
    _bounded_text(identifier)
    _bounded_text(version)
    files = getattr(generation, "files", None)
    manifest_sha = getattr(generation, "manifest_sha256", None)
    if not isinstance(files, Mapping) or not isinstance(manifest_sha, str) or not _HEX64_RE.fullmatch(manifest_sha):
        raise _error("support-unavailable")
    normalized_files: dict[str, list[Any]] = {}
    for label, pair in files.items():
        if not isinstance(label, str) or not isinstance(pair, tuple) or len(pair) != 2:
            raise _error("support-unavailable")
        size, digest = pair
        if type(size) is not int or size <= 0 or not isinstance(digest, str) or _HEX64_RE.fullmatch(digest) is None:
            raise _error("support-unavailable")
        normalized_files[label] = [size, digest]
    return {
        "method": method,
        "osVersion": os_version,
        "generationID": generation_id,
        "identifier": identifier,
        "version": version,
        "inputFiles": normalized_files,
        "inputManifestSHA256": manifest_sha,
    }


def _readback_dict(value: Any) -> dict[str, Any]:
    fields = (
        ("nonce", "nonce"), ("setupID", "setup_id"), ("deviceID", "device_id"),
        ("artifactSHA256", "artifact_sha256"), ("executableSHA256", "executable_sha256"),
        ("profileSHA256", "profile_sha256"), ("pairingSHA256", "pairing_sha256"),
        ("supportMethod", "support_method"), ("supportGenerationID", "support_generation_id"),
        ("build", "build"),
    )
    result = {key: _observation_value(value, attr) for key, attr in fields}
    if any(not isinstance(item, str) for item in result.values()):
        raise _error("handoff-unknown")
    return result


def _receipt_matches(
    receipt: Any,
    *,
    device_id: str,
    setup_id: str,
    nonce: str,
    identity: PreparationAppIdentity,
    pairing_transaction_id: str,
    pairing_sha256: str,
    support: Mapping[str, Any],
    plan: FormalSetupInput,
) -> None:
    values = {
        "setup_id": setup_id,
        "nonce": nonce,
        "device_id": device_id,
        "bundle_id": identity.bundle_id,
        "build": identity.build,
        "profile_sha256": identity.profile_sha256,
        "executable_sha256": identity.executable_sha256,
        "team_id": identity.team_id,
        "signing_expiry": identity.expires_at,
        "pairing_transaction_id": pairing_transaction_id,
        "pairing_sha256": pairing_sha256,
        "raw_manifest_sha256": plan.sha256,
        "method": support["method"],
        "generation_id": support["generationID"],
        "device_os": support["osVersion"],
    }
    if any(_observation_value(receipt, key) != expected for key, expected in values.items()):
        raise _error("adoption-unknown")
    records = _observation_value(receipt, "artifact_records")
    artifacts = _observation_value(receipt, "artifacts")
    if not isinstance(records, tuple) or records != plan.artifacts:
        raise _error("adoption-unknown")
    if not isinstance(artifacts, tuple) or tuple((name, count, digest) for _, name, count, digest in plan.artifacts) != artifacts:
        raise _error("adoption-unknown")


@dataclass(frozen=True)
class TargetReconciliation:
    """Read-only observations used to resolve an interrupted target phase."""

    setup_id: str
    nonce: str
    pairing_sha256: str | None
    readback: bool
    activation: bool
    adoption: bool
    installed: bool


class ManagementTargetDriver:
    """Execute the bounded, journaled target half of one M3 operation."""

    def __init__(
        self,
        config: Any,
        store: ManagementJournal,
        device: PinnedManagementDeviceAdapter,
        preparation: ManagementPreparationAdapter,
    ) -> None:
        self.config = config
        self.store = store
        self.device = device
        self.preparation = preparation

    def _value(self) -> dict[str, Any]:
        value = self.store.read()
        if not isinstance(value, dict):
            raise _error("transaction-conflict")
        return value

    def _stage(self, name: str) -> dict[str, Any]:
        value = self._value()
        stage = value.get("stages", {}).get(name)
        if not isinstance(stage, dict):
            # Root's journal owns the closed stage vocabulary.  A missing
            # stage is a transaction conflict, never permission to reuse an
            # older, weaker stage.
            raise _error("transaction-conflict")
        return stage

    def _record(self, name: str) -> None:
        if self._stage(name)["state"] == "pending":
            self.store.record_intent(name)

    def _confirm(self, name: str, evidence: str) -> None:
        state = self._stage(name)["state"]
        if state in {"inflight", "unknown"}:
            self.store.confirm(name, evidence)

    def _unknown(self, name: str, code: str) -> None:
        if self._stage(name)["state"] in {"inflight", "unknown"}:
            self.store.mark_unknown(name, code)

    def _put_once(self, name: str, raw: bytes) -> None:
        previous = self.store.read_evidence(name)
        if previous is None:
            self.store.put_evidence(name, raw)
        elif previous != raw:
            raise _error("transaction-conflict")

    def _poll_deadline(self, name: str, default: float) -> float:
        # ReinstallConfiguration is intentionally closed and has no mutable
        # timeout authority.  Tests may provide a bounded adapter config
        # override, while production uses the protocol's fixed deadlines.
        candidate = getattr(self.config, name, default)
        if type(candidate) not in {int, float} or candidate <= 0 or candidate > _ACTIVATION_POLL_SECONDS:
            return default
        return float(candidate)

    def _poll_readback(self, device_id: str, setup_id: str, nonce: str) -> tuple[Any, bytes] | None:
        deadline = time.monotonic() + self._poll_deadline("management_readback_timeout", _READBACK_POLL_SECONDS)
        while True:
            typed = self.preparation.readback(device_id, setup_id, nonce)
            raw = self.preparation.read_file(device_id, "setupReadbackResponse")
            if typed is not None and raw is not None:
                return typed, raw
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            time.sleep(min(_POLL_INTERVAL_SECONDS, remaining))

    def _poll_activation_receipt(self, device_id: str, setup_id: str, nonce: str) -> Any | None:
        deadline = time.monotonic() + self._poll_deadline("management_activation_timeout", _ACTIVATION_POLL_SECONDS)
        while True:
            receipt = self.preparation.read_activation_receipt(device_id, setup_id, nonce)
            if receipt is not None:
                return receipt
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            time.sleep(min(_POLL_INTERVAL_SECONDS, remaining))

    def _validated_readback(
        self,
        header: Mapping[str, Any],
        identity: PreparationAppIdentity,
        pairing_sha: str,
        typed: Any,
        raw: bytes,
    ) -> Any:
        try:
            decoded = PinnedPymobiledeviceAdapter._decode_readback(
                raw,
                device_id=header["deviceID"],
                setup_id=header["targetSetupID"],
                nonce=header["setupNonce"],
            )
        except Exception:
            raise _error("handoff-unknown") from None
        if decoded != typed:
            raise _error("handoff-unknown")
        values = _readback_dict(decoded)
        expected = {
            "nonce": header["setupNonce"], "setupID": header["targetSetupID"],
            "deviceID": header["deviceID"], "build": identity.build,
            "executableSHA256": identity.executable_sha256,
            "profileSHA256": identity.profile_sha256,
            "pairingSHA256": pairing_sha,
        }
        if any(values[key] != expected[key] for key in expected):
            raise _error("identity-mismatch")
        target_identity = self.store.read_evidence("targetIdentity")
        if target_identity is not None:
            try:
                parsed_identity = _strict_object(target_identity, limit=32 * 1024)
                artifact_sha = parsed_identity.get("artifactSHA256")
                if artifact_sha is not None and values["artifactSHA256"] != artifact_sha:
                    raise _error("identity-mismatch")
            except ManagementBridgeError:
                raise
            except Exception:
                raise _error("transaction-conflict") from None
        return decoded

    def _stable_activation(self, device_id: str) -> bytes:
        """Read the App-owned activation record twice as one stable snapshot."""
        first = self.device.read_activation(device_id)
        second = self.device.read_activation(device_id)
        if (
            not isinstance(first, bytes)
            or not first
            or second != first
        ):
            raise _error("adoption-unknown")
        return first

    def _formal_snapshot(
        self,
        header: Mapping[str, Any],
        identity: PreparationAppIdentity,
        pairing_sha: str,
    ) -> tuple[Any, bytes, FormalSetupInput, dict[str, Any]] | None:
        """Read and validate a complete existing formal activation only."""
        support_raw = self.store.read_evidence("supportObservation")
        plan_raw = self.store.read_evidence("formalPlan")
        pairing_plan_raw = self.store.read_evidence("pairingPlan")
        if support_raw is None or plan_raw is None or pairing_plan_raw is None:
            return None
        try:
            support = _strict_object(support_raw, limit=64 * 1024)
            pairing_plan = _strict_object(pairing_plan_raw, limit=32 * 1024)
            pairing_tx = _uuid(pairing_plan.get("pairingTransactionID"))
            if (
                pairing_plan.get("managementID") != header["managementID"]
                or pairing_plan.get("targetSetupID") != header["targetSetupID"]
                or pairing_plan.get("setupNonce") != header["setupNonce"]
                or pairing_plan.get("deviceID") != header["deviceID"]
                or pairing_plan.get("pairingSHA256") != pairing_sha
            ):
                raise ValueError()
            binding_raw = self.store.read_evidence("pairingBinding")
            if binding_raw is not None:
                binding = _strict_object(binding_raw, limit=32 * 1024)
                if (
                    binding.get("managementID") != header["managementID"]
                    or binding.get("targetSetupID") != header["targetSetupID"]
                    or binding.get("deviceID") != header["deviceID"]
                    or binding.get("transactionID") != pairing_tx
                    or binding.get("sha256") != pairing_sha
                ):
                    raise ValueError()
            plan = build_formal_setup_input(
                device_id=header["deviceID"], setup_id=header["targetSetupID"], nonce=header["setupNonce"],
                artifact=identity, pairing_transaction_id=pairing_tx,
                pairing_sha256=pairing_sha, support=support,
            )
        except Exception:
            raise _error("transaction-conflict") from None
        if plan.raw_manifest != plan_raw:
            raise _error("transaction-conflict")
        receipt = self.preparation.read_activation_receipt(
            header["deviceID"], header["targetSetupID"], header["setupNonce"]
        )
        if receipt is None:
            return None
        try:
            target_raw = self._stable_activation(header["deviceID"])
        except ManagementBridgeError:
            return None
        try:
            decoded = PinnedPymobiledeviceAdapter._decode_activation_receipt(
                target_raw, device_id=header["deviceID"],
                setup_id=header["targetSetupID"], nonce=header["setupNonce"],
            )
        except Exception:
            raise _error("adoption-unknown") from None
        if decoded != receipt:
            raise _error("adoption-unknown")
        _receipt_matches(
            receipt, device_id=header["deviceID"], setup_id=header["targetSetupID"],
            nonce=header["setupNonce"], identity=identity,
            pairing_transaction_id=pairing_tx, pairing_sha256=pairing_sha,
            support=support, plan=plan,
        )
        return receipt, target_raw, plan, support

    def _header_bindings(
        self,
        request: ManagementRequest,
        source: SourceActivation,
        identity: PreparationAppIdentity,
        *,
        candidate_transport: bool = False,
    ) -> tuple[dict[str, Any], dict[str, Any], bytes]:
        if not isinstance(request, ManagementRequest) or not isinstance(source, SourceActivation):
            raise _error("invalid-request")
        if not isinstance(identity, PreparationAppIdentity):
            raise _error("identity-unverified")
        value = self._value()
        header = value.get("header")
        if not isinstance(header, Mapping):
            raise _error("transaction-conflict")
        if request.action not in {"apply", "resume"}:
            raise _error("invalid-request")
        if (
            header.get("managementID") != request.management_id
            or header.get("deviceID") != request.device_id
            or header.get("kind") != request.kind
            or header.get("transport") != request.transport
            or header.get("selectionID") != request.selection_id
        ):
            raise _error("identity-mismatch")
        revisions = value.get("revisions")
        if (
            not isinstance(revisions, list)
            or not revisions
            or request.connection_revision != len(revisions) - 1
        ):
            raise _error("revision-conflict")
        current_transport = revisions[-1].get("transport") if isinstance(revisions[-1], Mapping) else None
        if current_transport not in {"USB", "Network"}:
            raise _error("transaction-conflict")
        selected_transport = current_transport
        if candidate_transport and request.resume_selection is not None:
            selected_transport = request.resume_selection.transport
        if (
            selected_transport not in {"USB", "Network"}
            or getattr(self.device, "transport", None) != selected_transport
            or getattr(self.preparation, "transport", None) != selected_transport
        ):
            raise _error("revision-conflict")
        if not candidate_transport and current_transport != selected_transport:
            raise _error("revision-conflict")
        if candidate_transport and request.action != "resume":
            raise _error("invalid-request")
        app_raw = self.store.read_evidence("appRequest")
        if app_raw is None:
            raise _error("transaction-conflict")
        core = _validate_management_request(app_raw)
        core["_raw"] = app_raw
        if (
            core["managementID"] != header.get("managementID")
            or core["expectedDeviceUDID"] != header.get("deviceID")
            or core["kind"] != header.get("kind")
            or core["targetSetupID"] != header.get("targetSetupID")
            or core["sourceSetupID"] != source.receipt.setup_id
            or core["sourceActivationSHA256"] != source.sha256
            or core["targetApp"] != _identity_app(identity)
            or core["teamID"] != identity.team_id
        ):
            raise _error("identity-mismatch")
        source_raw = self.store.read_evidence("sourceActivation")
        if source_raw != source.raw or _sha(source.raw) != source.sha256:
            raise _error("identity-mismatch")
        root_raw = self.store.read_evidence("sourceRestoreRoot")
        root_sha = core["sourceRestoreRootSHA256"]
        if root_sha is None:
            if root_raw is not None:
                raise _error("identity-mismatch")
        elif root_raw is None or _sha(root_raw) != root_sha:
            raise _error("identity-mismatch")
        if source.identity.app() != core["sourceApp"] or source.receipt.team_id != core["teamID"]:
            raise _error("identity-mismatch")
        _uuid(header.get("targetSetupID"))
        _uuid(header.get("setupNonce"))
        return dict(header), core, app_raw

    def _candidate(self, management_id: str) -> Path:
        try:
            root = self.store.transaction_root(management_id)
            if root.is_symlink() or not root.is_dir():
                raise OSError()
            candidate = root / "pairing.candidate"
            if candidate.is_symlink() or (candidate.exists() and not candidate.is_file()):
                raise OSError()
            return candidate
        except (OSError, ManagementBridgeError):
            raise _error("storage-unavailable") from None

    def _pairing_plan(
        self, header: Mapping[str, Any], source: SourceActivation
    ) -> tuple[str, str | None]:
        kind = header["kind"]
        if kind == "renew":
            tx = _uuid(source.receipt.pairing_transaction_id)
            pairing_sha = _hash(source.receipt.pairing_sha256)
        elif kind == "repair":
            tx = str(uuid.uuid5(uuid.UUID(header["targetSetupID"]), _TARGET_PAIRING_NAMESPACE))
            pairing_sha = None
        else:
            raise _error("invalid-request")
        raw = _json({
            "version": 1,
            "kind": kind,
            "managementID": header["managementID"],
            "targetSetupID": header["targetSetupID"],
            "setupNonce": header["setupNonce"],
            "deviceID": header["deviceID"],
            "pairingTransactionID": tx,
            "pairingSHA256": pairing_sha,
        })
        self._put_once("pairingPlan", raw)
        return tx, pairing_sha

    def _pairing(
        self, header: Mapping[str, Any], source: SourceActivation, action: str
    ) -> tuple[str, str]:
        tx, source_pairing_sha = self._pairing_plan(header, source)
        if header["kind"] == "renew":
            # Renewal deliberately preserves the original source pairing.  No
            # pair setup or LocalGo v1 delivery is entered for this branch.
            pairing_sha = source_pairing_sha or ""
            self._put_once("pairingBinding", _json({
                "version": 1, "managementID": header["managementID"],
                "targetSetupID": header["targetSetupID"], "deviceID": header["deviceID"],
                "transactionID": tx, "sha256": pairing_sha,
            }))
            return tx, pairing_sha

        candidate = self._candidate(header["managementID"])
        binding_existing = self.store.read_evidence("pairingBinding")
        if binding_existing is not None:
            try:
                binding = _strict_object(binding_existing, limit=32 * 1024)
            except ManagementBridgeError:
                raise _error("transaction-conflict") from None
            if (
                binding.get("transactionID") != tx
                or binding.get("deviceID") != header["deviceID"]
                or not isinstance(binding.get("sha256"), str)
                or _HEX64_RE.fullmatch(binding["sha256"]) is None
            ):
                raise _error("transaction-conflict")
            pairing_sha = binding["sha256"]
        else:
            pair_create_state = self._stage("pairCreate")["state"]
            if pair_create_state in {"unknown", "inflight"}:
                if action != "resume":
                    raise _error("handoff-unknown")
                # Resume is read-only at this boundary.  verify_pairing may
                # authenticate an exact candidate but never creates/replaces
                # it or invokes LocalGo delivery.
                try:
                    verified = self.preparation.verify_pairing(header["deviceID"], candidate)
                    _, pairing_sha = _pairing_observation(verified, device_id=header["deviceID"])
                except ManagementBridgeError:
                    self._unknown("pairCreate", "pairing-unknown")
                    raise
                except Exception:
                    self._unknown("pairCreate", "pairing-unknown")
                    raise _error("pairing-unknown") from None
            else:
                self._record("pairCreate")
                try:
                    self.preparation.prepare_pairing(header["deviceID"], candidate)
                    paired = self.preparation.pair(header["deviceID"], candidate)
                    _, pairing_sha = _pairing_observation(paired, device_id=header["deviceID"])
                    verified = self.preparation.verify_pairing(header["deviceID"], candidate)
                    _, verified_sha = _pairing_observation(verified, device_id=header["deviceID"])
                    if verified_sha != pairing_sha:
                        raise _error("pairing-unknown")
                except ManagementBridgeError:
                    self._unknown("pairCreate", "pairing-unknown")
                    raise
                except Exception:
                    self._unknown("pairCreate", "pairing-unknown")
                    raise _error("pairing-unknown") from None
            binding_raw = _json({
                "version": 1, "managementID": header["managementID"],
                "targetSetupID": header["targetSetupID"], "deviceID": header["deviceID"],
                "transactionID": tx, "sha256": pairing_sha,
            })
            self._put_once("pairingBinding", binding_raw)
            self._confirm("pairCreate", "pairingBinding")

        # A prior verified candidate may have left pairCreate inflight or
        # unknown while the process boundary was interrupted.  The immutable
        # binding is only written after exact candidate verification, so it is
        # safe to close that stage now without creating or replacing a pair.
        self._confirm("pairCreate", "pairingBinding")

        delivery_state = self._stage("pairDelivery")["state"]
        if delivery_state in {"unknown", "inflight"} and action != "resume":
            raise _error("handoff-unknown")
        self._put_once("pairingBinding", _json({
            "version": 1, "managementID": header["managementID"],
            "targetSetupID": header["targetSetupID"], "deviceID": header["deviceID"],
            "transactionID": tx, "sha256": pairing_sha,
        }))
        if delivery_state == "pending":
            self._record("pairDelivery")
            try:
                self.preparation.deliver_pairing(header["deviceID"], candidate, tx, pairing_sha)
            except ManagementBridgeError:
                self._unknown("pairDelivery", "pairing-unknown")
                raise
            except Exception:
                self._unknown("pairDelivery", "pairing-unknown")
                raise _error("pairing-unknown") from None
        # ``pairDelivery`` is confirmed only by the target readback below.
        # This evidence is the immutable transaction/hash binding, not a Mac
        # assertion that a remote peer imported it.
        return tx, pairing_sha

    def _readback_publication(
        self, header: Mapping[str, Any], identity: PreparationAppIdentity, request: ManagementRequest
    ) -> bytes:
        plan = _json({
            "version": 1,
            "setupID": header["targetSetupID"],
            "nonce": header["setupNonce"],
            "expectedDeviceUDID": header["deviceID"],
            "app": _identity_app(identity),
        })
        existing = self.store.read_evidence("readbackPlan")
        if existing is not None and existing != plan:
            raise _error("transaction-conflict")
        self._put_once("readbackPlan", plan)
        state = self._stage("readbackPublish")["state"]
        current = self.preparation.read_file(header["deviceID"], "setupReadbackRequest")
        if state == "confirmed":
            if current != plan:
                raise _error("transaction-conflict")
            return plan
        if current == plan:
            self._confirm("readbackPublish", "readbackPlan")
            return plan
        if current is not None:
            raise _error("transaction-conflict")
        if state in {"unknown", "inflight"} and request.action != "resume":
            raise _error("handoff-unknown")
        if state == "pending":
            self._record("readbackPublish")
        try:
            self.preparation.prepare_readback(
                header["deviceID"], header["targetSetupID"], header["setupNonce"], identity
            )
            published = self.preparation.read_file(header["deviceID"], "setupReadbackRequest")
            if published != plan:
                raise _error("handoff-unknown")
            self._confirm("readbackPublish", "readbackPlan")
            return plan
        except ManagementBridgeError:
            self._unknown("readbackPublish", "handoff-unknown")
            raise
        except Exception:
            self._unknown("readbackPublish", "handoff-unknown")
            raise _error("handoff-unknown") from None

    def prepare_readback_metadata(
        self,
        request: ManagementRequest,
        identity: PreparationAppIdentity,
    ) -> bytes:
        """Freeze the candidate-bound readback bytes before an app upgrade.

        This is intentionally local and data-only.  It does not publish to a
        device, launch the target, or invoke any pairing/support primitive.
        The later ``advance`` call reuses these exact bytes after the upgrade;
        an unknown upgrade therefore cannot be followed by a newly invented
        readback request.
        """
        if not isinstance(request, ManagementRequest) or request.action not in {"apply", "resume"}:
            raise _error("invalid-request")
        value = self._value()
        header = value.get("header")
        if not isinstance(header, Mapping) or (
            header.get("managementID") != request.management_id
            or header.get("deviceID") != request.device_id
            or header.get("kind") != request.kind
            or header.get("transport") != request.transport
            or header.get("selectionID") != request.selection_id
        ):
            raise _error("identity-mismatch")
        revisions = value.get("revisions")
        if (
            not isinstance(revisions, list)
            or not revisions
            or request.connection_revision != len(revisions) - 1
            or not isinstance(revisions[-1], Mapping)
            or revisions[-1].get("transport") not in {"USB", "Network"}
            or getattr(self.device, "transport", None) != revisions[-1].get("transport")
            or getattr(self.preparation, "transport", None) != revisions[-1].get("transport")
        ):
            raise _error("revision-conflict")
        app_request = self.store.read_evidence("appRequest")
        if app_request is None:
            raise _error("transaction-conflict")
        core = _validate_management_request(app_request)
        if (
            core["managementID"] != header.get("managementID")
            or core["expectedDeviceUDID"] != header.get("deviceID")
            or core["targetSetupID"] != header.get("targetSetupID")
            or core["targetApp"] != _identity_app(identity)
            or core["teamID"] != identity.team_id
        ):
            raise _error("identity-mismatch")
        source_raw = self.store.read_evidence("sourceActivation")
        if source_raw is None or _sha(source_raw) != core["sourceActivationSHA256"]:
            raise _error("identity-mismatch")
        raw = _json({
            "version": 1,
            "setupID": header["targetSetupID"],
            "nonce": header["setupNonce"],
            "expectedDeviceUDID": header["deviceID"],
            "app": _identity_app(identity),
        })
        existing = self.store.read_evidence("readbackPlan")
        if existing is not None and existing != raw:
            raise _error("transaction-conflict")
        self._put_once("readbackPlan", raw)
        if self._stage("readbackPublish")["state"] == "confirmed":
            if self.preparation.read_file(header["deviceID"], "setupReadbackRequest") != raw:
                raise _error("transaction-conflict")
        return raw

    def _readback(
        self,
        header: Mapping[str, Any],
        identity: PreparationAppIdentity,
        pairing_sha: str,
        request: ManagementRequest,
    ) -> None:
        self._readback_publication(header, identity, request)
        process_state = self._stage("readbackLaunch")["state"]
        process_raw = self.store.read_evidence("readbackProcess")
        frozen_target_readback = self.store.read_evidence("targetReadback")
        if frozen_target_readback is not None and process_raw is None:
            # A previous unknown upgrade may have left an actual response in
            # the App.  It is useful read-only evidence, but it cannot create
            # the missing launch/stop PID facts or authorize a new launch.
            if process_state == "pending":
                self._unknown("readbackLaunch", "handoff-unknown")
            raise _error("handoff-unknown")
        pid: int | None = None
        if process_raw is not None:
            process = _strict_object(process_raw, limit=32 * 1024)
            pid_value = process.get("pid")
            if type(pid_value) is not int or pid_value <= 0:
                raise _error("transaction-conflict")
            if (
                process.get("deviceID") != header["deviceID"]
                or process.get("setupID") != header["targetSetupID"]
                or process.get("nonce") != header["setupNonce"]
            ):
                raise _error("transaction-conflict")
            pid = pid_value
            self._confirm("readbackLaunch", "readbackProcess")
        elif process_state == "confirmed":
            raise _error("transaction-conflict")
        elif process_state in {"unknown", "inflight"}:
            self._unknown("readbackLaunch", "handoff-unknown")
            raise _error("handoff-unknown")
        else:
            self._record("readbackLaunch")
            try:
                actual_pid = self.preparation.launch(header["deviceID"])
                if type(actual_pid) is not int or actual_pid <= 0:
                    raise _error("handoff-unknown")
                pid = actual_pid
                self._put_once("readbackProcess", _json({
                    "version": 1, "deviceID": header["deviceID"],
                    "setupID": header["targetSetupID"], "nonce": header["setupNonce"],
                    "pid": pid,
                }))
                self._confirm("readbackLaunch", "readbackProcess")
            except ManagementBridgeError:
                self._unknown("readbackLaunch", "handoff-unknown")
                raise
            except Exception:
                self._unknown("readbackLaunch", "handoff-unknown")
                raise _error("handoff-unknown") from None

        polled = self._poll_readback(
            header["deviceID"], header["targetSetupID"], header["setupNonce"]
        )
        if polled is None:
            raise _error("handoff-unknown")
        readback, response_raw = polled
        self._validated_readback(header, identity, pairing_sha, readback, response_raw)
        # Preserve the exact Core/App response bytes.  A derived observation
        # object cannot reconcile a prior unknown upgrade because it loses
        # the immutable response serialization and duplicate-key protection.
        self._put_once("targetReadback", response_raw)
        self._record("readback")
        self._confirm("readback", "targetReadback")

        stop_state = self._stage("readbackStop")["state"]
        if stop_state == "confirmed":
            return
        if stop_state in {"unknown", "inflight"}:
            self._unknown("readbackStop", "handoff-unknown")
            raise _error("handoff-unknown")
        self._record("readbackStop")
        try:
            if pid is None:
                raise _error("handoff-unknown")
            # Only the PID returned by this exact launch is ever passed to the
            # owned-stop primitive.  A fresh process lookup is never adopted.
            self.device.stop_owned_process(header["deviceID"], pid)
            self._confirm("readbackStop", "readbackProcess")
        except ManagementBridgeError:
            self._unknown("readbackStop", "handoff-unknown")
            raise
        except Exception:
            self._unknown("readbackStop", "handoff-unknown")
            raise _error("handoff-unknown") from None

    def _support(
        self, header: Mapping[str, Any], identity: PreparationAppIdentity
    ) -> dict[str, Any]:
        existing = self.store.read_evidence("supportObservation")
        if existing is not None:
            support = _strict_object(existing, limit=64 * 1024)
            if not isinstance(support.get("method"), str) or not isinstance(support.get("generationID"), str):
                raise _error("transaction-conflict")
            self._confirm("support", "supportObservation")
            return support
        restore = self.store.transaction_root(header["managementID"]) / "support"
        try:
            observed_device = self.device.observe(header["deviceID"])
            os_version = _observation_value(observed_device, "os_version")
            method = support_method(os_version)
            self.preparation.prepare_generation(method, restore)
            generation = validate_generation(method, restore)
        except ManagementBridgeError:
            raise
        except Exception:
            raise _error("support-unavailable") from None
        support_state = self._stage("support")["state"]
        if support_state == "pending":
            self._record("support")
        elif support_state not in {"inflight", "unknown"}:
            raise _error("transaction-conflict")
        try:
            support_observed = self.preparation.query_support(header["deviceID"], method, restore)
            if _observation_value(support_observed, "observed") is not True:
                # Query-first is mandatory.  Only a fresh pending stage may
                # enter its one install effect.  An inflight/unknown install
                # is reconciled by a positive fresh query and otherwise
                # remains pending for explicit user resolution.
                if support_state != "pending":
                    self._unknown("support", "support-unavailable")
                    raise _error("support-unavailable")
                support_observed = self.preparation.install_support(header["deviceID"], method, restore)
            support = _support_map(support_observed, generation)
            if support["method"] != method:
                raise _error("support-unavailable")
            support_raw = _json(support)
            self._put_once("supportObservation", support_raw)
            self._confirm("support", "supportObservation")
            return support
        except ManagementBridgeError:
            self._unknown("support", "support-unavailable")
            raise
        except Exception:
            self._unknown("support", "support-unavailable")
            raise _error("support-unavailable") from None

    def _formal(
        self,
        header: Mapping[str, Any],
        identity: PreparationAppIdentity,
        pairing_transaction_id: str,
        pairing_sha: str,
        support: Mapping[str, Any],
    ) -> FormalSetupInput:
        existing = self.store.read_evidence("formalPlan")
        if existing is not None:
            plan = build_formal_setup_input(
                device_id=header["deviceID"], setup_id=header["targetSetupID"], nonce=header["setupNonce"],
                artifact=identity, pairing_transaction_id=pairing_transaction_id,
                pairing_sha256=pairing_sha, support=support,
            )
            if existing != plan.raw_manifest:
                raise _error("transaction-conflict")
            formal = plan
        else:
            try:
                formal = build_formal_setup_input(
                    device_id=header["deviceID"], setup_id=header["targetSetupID"], nonce=header["setupNonce"],
                    artifact=identity, pairing_transaction_id=pairing_transaction_id,
                    pairing_sha256=pairing_sha, support=support,
                )
            except Exception:
                raise _error("handoff-unknown") from None
            self._put_once("formalPlan", formal.raw_manifest)
        state = self._stage("formalInput")["state"]
        if state == "confirmed":
            return formal
        if state in {"inflight", "unknown"}:
            # An interrupted upload is never repeated.  A committed actual
            # receipt is the only read-only resolution.
            receipt = self._poll_activation_receipt(
                header["deviceID"], header["targetSetupID"], header["setupNonce"]
            )
            if receipt is None:
                self._unknown("formalInput", "handoff-unknown")
                raise _error("handoff-unknown")
            # Support is already frozen and the receipt is checked later in
            # _activation; this check only authorizes skipping re-upload.
            return formal
        self._record("formalInput")
        try:
            digest = self.preparation.prepare_setup_input(
                header["deviceID"], header["targetSetupID"], header["setupNonce"], identity,
                pairing_transaction_id, pairing_sha, support, plan=formal,
            )
            if digest != formal.sha256:
                raise _error("handoff-unknown")
            self._confirm("formalInput", "formalPlan")
            return formal
        except ManagementBridgeError:
            self._unknown("formalInput", "handoff-unknown")
            raise
        except Exception:
            self._unknown("formalInput", "handoff-unknown")
            raise _error("handoff-unknown") from None

    def _activation(
        self,
        header: Mapping[str, Any],
        core_request: Mapping[str, Any],
        identity: PreparationAppIdentity,
        pairing_transaction_id: str,
        pairing_sha: str,
        support: Mapping[str, Any],
        plan: FormalSetupInput,
    ) -> None:
        activation_state = self._stage("activation")["state"]
        if activation_state == "confirmed":
            return
        formal_process = self.store.read_evidence("formalProcess")
        formal_state = self._stage("formalLaunch")["state"]
        preexisting_receipt = None
        if formal_process is not None:
            process = _strict_object(formal_process, limit=32 * 1024)
            pid = process.get("pid")
            if (
                type(pid) is not int
                or pid <= 0
                or process.get("deviceID") != header["deviceID"]
                or process.get("setupID") != header["targetSetupID"]
                or process.get("nonce") != header["setupNonce"]
            ):
                raise _error("transaction-conflict")
            self._confirm("formalLaunch", "formalProcess")
        elif formal_state in {"unknown", "inflight"}:
            # A positive receipt below can reconcile an unknown launch.  No
            # fresh launch or guessed PID is permitted.
            self._unknown("formalLaunch", "handoff-unknown")
            pid = None
        else:
            # A prior unknown formal upload may already have activated the
            # exact target.  Read first so a positive full receipt is never
            # followed by a duplicate launch.  With no returned PID the
            # formalLaunch stage remains pending and cannot be promoted by a
            # guessed process lookup.
            preexisting_receipt = self.preparation.read_activation_receipt(
                header["deviceID"], header["targetSetupID"], header["setupNonce"]
            )
            if preexisting_receipt is None:
                self._record("formalLaunch")
                try:
                    pid = self.preparation.launch(header["deviceID"])
                    if type(pid) is not int or pid <= 0:
                        raise _error("handoff-unknown")
                    self._put_once("formalProcess", _json({
                        "version": 1, "deviceID": header["deviceID"],
                        "setupID": header["targetSetupID"], "nonce": header["setupNonce"],
                        "pid": pid,
                    }))
                    self._confirm("formalLaunch", "formalProcess")
                except ManagementBridgeError:
                    self._unknown("formalLaunch", "handoff-unknown")
                    raise
                except Exception:
                    self._unknown("formalLaunch", "handoff-unknown")
                    raise _error("handoff-unknown") from None
        receipt = preexisting_receipt or self._poll_activation_receipt(
            header["deviceID"], header["targetSetupID"], header["setupNonce"]
        )
        if receipt is None:
            self._unknown("activation", "adoption-unknown")
            raise _error("adoption-unknown")
        _receipt_matches(
            receipt, device_id=header["deviceID"], setup_id=header["targetSetupID"],
            nonce=header["setupNonce"], identity=identity,
            pairing_transaction_id=pairing_transaction_id, pairing_sha256=pairing_sha,
            support=support, plan=plan,
        )
        self._confirm("formalInput", "formalPlan")
        # The committed formal activation receipt is the final pairing-import
        # proof.  AFC readback and the preparation adapter's local response
        # only bind bytes; neither is native pairing authority.
        self._record("pairing")
        self._confirm("pairDelivery", "pairingBinding")
        self._confirm("pairing", "pairingBinding")
        target_raw = self._stable_activation(header["deviceID"])
        try:
            decoded_target = PinnedPymobiledeviceAdapter._decode_activation_receipt(
                target_raw,
                device_id=header["deviceID"],
                setup_id=header["targetSetupID"],
                nonce=header["setupNonce"],
            )
        except Exception:
            raise _error("adoption-unknown") from None
        if decoded_target != receipt:
            raise _error("adoption-unknown")
        target_sha = _sha(target_raw)
        response_raw = self.preparation.read_file(header["deviceID"], "managementResponse")
        if response_raw is None:
            self._unknown("activation", "adoption-unknown")
            raise _error("adoption-unknown")
        if not _terminal_response_is_bound(response_raw, core_request):
            self._unknown("activation", "adoption-unknown")
            raise _error("adoption-unknown")
        response = _strict_object(response_raw, limit=64 * 1024)
        if response.get("targetActivationSHA256") != target_sha:
            self._unknown("activation", "adoption-unknown")
            raise _error("adoption-unknown")
        self._put_once("activationReceipt", target_raw)
        self._put_once("adoptionReceipt", response_raw)
        self._confirm("activation", "adoptionReceipt")

    def _final_support(
        self, header: Mapping[str, Any], identity: PreparationAppIdentity, support: Mapping[str, Any]
    ) -> None:
        if self._stage("finalSupport")["state"] == "confirmed":
            return
        self._record("finalSupport")
        restore = self.store.transaction_root(header["managementID"]) / "support"
        try:
            final = self.preparation.query_support(header["deviceID"], support["method"], restore)
            final_map = _support_map(final, validate_generation(support["method"], restore))
            for key in (
                "method", "osVersion", "generationID", "identifier", "version",
                "inputFiles", "inputManifestSHA256",
            ):
                if final_map.get(key) != support.get(key):
                    raise _error("support-unavailable")
            installed = self.device.installed_identity(header["deviceID"])
            if (
                _observation_value(installed, "exists") is not True
                or _observation_value(installed, "bundle_id") != identity.bundle_id
                or _observation_value(installed, "build") != identity.build
                or _observation_value(installed, "team_id") != identity.team_id
            ):
                raise _error("identity-mismatch")
            raw = _json(final_map)
            self._put_once("finalSupportObservation", raw)
            self._confirm("finalSupport", "finalSupportObservation")
        except ManagementBridgeError:
            self._unknown("finalSupport", "support-unavailable")
            raise
        except Exception:
            self._unknown("finalSupport", "support-unavailable")
            raise _error("support-unavailable") from None

    def advance(
        self,
        request: ManagementRequest,
        source: SourceActivation,
        identity: PreparationAppIdentity,
    ) -> None:
        """Advance target preparation after the producer froze Core bindings."""
        if request.action not in {"apply", "resume"}:
            raise _error("invalid-request")
        header, core_request, _ = self._header_bindings(request, source, identity)
        if request.action != "resume":
            # An ordinary apply owns only a newly-created target.  It cannot
            # resequence an effect left inflight by an earlier invocation;
            # only the explicit Resume path may perform readonly recovery.
            for stage in (
                "pairCreate", "pairDelivery", "readbackPublish", "readbackLaunch",
                "readbackStop", "readback", "support", "formalInput", "formalLaunch",
                "activation", "finalSupport",
            ):
                if self._stage(stage)["state"] in {"inflight", "unknown"}:
                    raise _error("handoff-unknown")
        pairing_tx, pairing_sha = self._pairing(header, source, request.action)
        self._readback(header, identity, pairing_sha, request)
        support = self._support(header, identity)
        plan = self._formal(header, identity, pairing_tx, pairing_sha, support)
        self._record("activation")
        self._activation(header, core_request, identity, pairing_tx, pairing_sha, support, plan)
        self._final_support(header, identity, support)

    def reconcile_readonly(
        self,
        request: ManagementRequest,
        source: SourceActivation,
        identity: PreparationAppIdentity,
    ) -> TargetReconciliation:
        """Checkpoint only fresh, exact read-only observations.

        A pending physical stage is never promoted merely because a later
        receipt exists.  Inflight/unknown stages may be closed when their
        immutable evidence is independently re-read; no pairing, publish,
        launch, stop, support preparation, or support installation is entered
        here.
        """
        if request.action != "resume":
            raise _error("invalid-request")
        header, core_request, _ = self._header_bindings(
            request, source, identity, candidate_transport=True
        )

        def checkpoint(stage: str, evidence: str, raw: bytes | None = None) -> None:
            state = self._stage(stage)["state"]
            if state not in {"inflight", "unknown"}:
                return
            if raw is not None:
                self._put_once(evidence, raw)
            self._confirm(stage, evidence)

        pairing_sha: str | None = None
        binding = self.store.read_evidence("pairingBinding")
        if binding is not None:
            parsed = _strict_object(binding, limit=32 * 1024)
            pairing_sha = parsed.get("sha256")
            if not isinstance(pairing_sha, str) or _HEX64_RE.fullmatch(pairing_sha) is None:
                raise _error("transaction-conflict")
        elif header["kind"] == "renew":
            pairing_sha = _hash(source.receipt.pairing_sha256)

        # An interrupted candidate pair may be verified, but never recreated.
        pair_create_state = self._stage("pairCreate")["state"]
        if pairing_sha is None and pair_create_state in {"inflight", "unknown"}:
            candidate = self._candidate(header["managementID"])
            try:
                verified = self.preparation.verify_pairing(header["deviceID"], candidate)
                _, pairing_sha = _pairing_observation(verified, device_id=header["deviceID"])
            except ManagementBridgeError:
                raise _error("pairing-unknown") from None
            except Exception:
                raise _error("pairing-unknown") from None
            pairing_tx = str(uuid.uuid5(uuid.UUID(header["targetSetupID"]), _TARGET_PAIRING_NAMESPACE))
            binding_raw = _json({
                "version": 1, "managementID": header["managementID"],
                "targetSetupID": header["targetSetupID"], "deviceID": header["deviceID"],
                "transactionID": pairing_tx, "sha256": pairing_sha,
            })
            self._put_once("pairingBinding", binding_raw)
            checkpoint("pairCreate", "pairingBinding")

        # The fixed request is a read-only reconciliation of an already
        # published exact plan; it never republishes bytes.
        readback_plan = self.store.read_evidence("readbackPlan")
        if readback_plan is not None:
            current_plan = self.preparation.read_file(header["deviceID"], "setupReadbackRequest")
            if current_plan == readback_plan:
                checkpoint("readbackPublish", "readbackPlan")

        readback_ok = False
        readback_raw = self.preparation.read_file(header["deviceID"], "setupReadbackResponse")
        readback_typed = self.preparation.readback(
            header["deviceID"], header["targetSetupID"], header["setupNonce"]
        )
        if readback_raw is not None and readback_typed is not None and pairing_sha is not None:
            try:
                self._validated_readback(header, identity, pairing_sha, readback_typed, readback_raw)
                readback_ok = True
                checkpoint("readback", "targetReadback", readback_raw)
                if header["kind"] == "repair":
                    checkpoint("pairDelivery", "pairingBinding")
            except ManagementBridgeError:
                readback_ok = False

        # A durable process fact is required before stopping.  If the stop
        # effect itself was interrupted, a fresh PID==0 observation may close
        # that stop intent; no new kill is attempted.
        process_raw = self.store.read_evidence("readbackProcess")
        stop_state = self._stage("readbackStop")["state"]
        if process_raw is not None and stop_state in {"inflight", "unknown"}:
            try:
                process = _strict_object(process_raw, limit=32 * 1024)
                pid = process.get("pid")
                if (
                    type(pid) is int
                    and pid > 0
                    and process.get("deviceID") == header["deviceID"]
                    and process.get("setupID") == header["targetSetupID"]
                    and process.get("nonce") == header["setupNonce"]
                    and self.device.source_pid(header["deviceID"]) == 0
                ):
                    checkpoint("readbackStop", "readbackProcess")
            except Exception:
                pass

        activation_ok = False
        adoption_ok = False
        formal_snapshot = None
        if pairing_sha is not None:
            try:
                formal_snapshot = self._formal_snapshot(header, identity, pairing_sha)
            except ManagementBridgeError:
                formal_snapshot = None
        if formal_snapshot is not None:
            _receipt, target_raw, _plan, _support = formal_snapshot
            activation_ok = True
            formal_input_state = self._stage("formalInput")["state"]
            formal_checkpoint_intent = formal_input_state in {"inflight", "unknown"}
            formal_launch_checkpoint_intent = self._stage("formalLaunch")["state"] in {"inflight", "unknown"}
            activation_checkpoint_intent = self._stage("activation")["state"] in {"inflight", "unknown"}
            if formal_input_state in {"inflight", "unknown"}:
                checkpoint("formalInput", "formalPlan")
            # The formal receipt closes pairing proof only when that stage had
            # already entered.  A pending pairing stage is never promoted by
            # read-only reconciliation.
            checkpoint("pairing", "pairingBinding")
            activation_receipt_raw = self.store.read_evidence("activationReceipt")
            if activation_receipt_raw is None or activation_receipt_raw != target_raw:
                if formal_checkpoint_intent or formal_launch_checkpoint_intent or activation_checkpoint_intent:
                    self._put_once("activationReceipt", target_raw)
                    activation_receipt_raw = target_raw

            adoption_raw = self.preparation.read_file(header["deviceID"], "managementResponse")
            request_raw = self.store.read_evidence("appRequest")
            if adoption_raw is not None and request_raw is not None:
                parsed_request = _validate_management_request(request_raw)
                parsed_request["_raw"] = request_raw
                response = _strict_object(adoption_raw, limit=64 * 1024)
                adoption_ok = (
                    _terminal_response_is_bound(adoption_raw, parsed_request)
                    and response.get("targetActivationSHA256") == _sha(target_raw)
                )
                if adoption_ok and any(self._stage(name)["state"] in {"inflight", "unknown"}
                                       for name in ("formalLaunch", "activation")):
                    self._put_once("adoptionReceipt", adoption_raw)
                    checkpoint("formalLaunch", "activationReceipt")
                    checkpoint("activation", "adoptionReceipt")
                    checkpoint("pairDelivery", "pairingBinding")

        # Final support is read-only here: reuse the already frozen restore
        # directory and query the same method/generation without preparing or
        # installing anything.
        support_raw = self.store.read_evidence("supportObservation")
        final_state = self._stage("finalSupport")["state"]
        if support_raw is not None and final_state in {"inflight", "unknown"}:
            try:
                support = _strict_object(support_raw, limit=64 * 1024)
                restore = self.store.transaction_root(header["managementID"]) / "support"
                final = self.preparation.query_support(header["deviceID"], support["method"], restore)
                generation = validate_generation(support["method"], restore)
                final_map = _support_map(final, generation)
                if any(final_map.get(key) != support.get(key) for key in (
                    "method", "osVersion", "generationID", "identifier", "version",
                    "inputFiles", "inputManifestSHA256",
                )):
                    raise _error("support-unavailable")
                installed = self.device.installed_identity(header["deviceID"])
                if (
                    _observation_value(installed, "exists") is not True
                    or _observation_value(installed, "bundle_id") != identity.bundle_id
                    or _observation_value(installed, "build") != identity.build
                    or _observation_value(installed, "team_id") != identity.team_id
                ):
                    raise _error("identity-mismatch")
                final_support_raw = _json(final_map)
                checkpoint("finalSupport", "finalSupportObservation", final_support_raw)
            except ManagementBridgeError:
                pass
            except Exception:
                pass

        installed = self.device.installed_identity(header["deviceID"])
        installed_ok = (
            _observation_value(installed, "exists") is True
            and _observation_value(installed, "bundle_id") == identity.bundle_id
            and _observation_value(installed, "build") == identity.build
            and _observation_value(installed, "team_id") == identity.team_id
        )
        return TargetReconciliation(
            header["targetSetupID"], header["setupNonce"], pairing_sha,
            readback_ok, activation_ok, adoption_ok, installed_ok,
        )


__all__ = ["ManagementTargetDriver", "TargetReconciliation"]
