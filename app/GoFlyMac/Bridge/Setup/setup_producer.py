"""Closed protocol-2 setup orchestration over explicit production seams."""

from __future__ import annotations

import copy
import contextlib
import hashlib
import json
import re
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

try:
    from .setup_adapters import (
        ArtifactIdentity,
        FormalSetupInput,
        DeviceAdapter,
        DeviceObservation,
        FormalArtifactValidator,
        InstalledAppObservation,
        ProcessAdapter,
        snapshot_artifact,
        build_formal_setup_input,
        SupportAdapter,
    )
    from .setup_config import SetupConfiguration
    from .setup_delivery import deliver_v1_once
    from .setup_journal import JournalStore
    from .setup_protocol import SetupBridgeError, SetupOptions, SetupRequest
except ImportError:  # script execution from the packaged Setup directory
    from setup_adapters import (
        ArtifactIdentity,
        FormalSetupInput,
        DeviceAdapter,
        DeviceObservation,
        FormalArtifactValidator,
        InstalledAppObservation,
        ProcessAdapter,
        snapshot_artifact,
        build_formal_setup_input,
        SupportAdapter,
    )
    from setup_config import SetupConfiguration
    from setup_delivery import deliver_v1_once
    from setup_journal import JournalStore
    from setup_protocol import SetupBridgeError, SetupOptions, SetupRequest


def _safe_version(value: str) -> bool:
    return bool(re.fullmatch(r"(?:26|27)(?:\.\d+){1,2}", value))


def support_method(os_version: str) -> str:
    try:
        parts = [int(item) for item in os_version.split(".")]
    except (AttributeError, ValueError):
        raise SetupBridgeError("unsupported-os") from None
    if not parts or parts[0] < 26:
        raise SetupBridgeError("unsupported-os")
    if parts[0] == 26 and (len(parts) == 1 or parts[1] <= 3):
        return "personalized"
    return "cryptex"


@dataclass(frozen=True)
class ProducerPayload:
    stage: str
    outcome: str
    can_resume: bool
    installation_confirmed: bool = False
    pairing_imported: bool = False
    support_observed: bool = False
    app: Mapping[str, Any] | None = None
    team_id: str | None = None
    expires_at: str | None = None
    receipt_sha256: str | None = None

    def as_dict(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "stage": self.stage,
            "outcome": self.outcome,
            "proof": {
                "installationConfirmed": self.installation_confirmed,
                "pairingImported": self.pairing_imported,
                "supportObserved": self.support_observed,
            },
        }
        value["canResume"] = self.can_resume
        if self.app is not None:
            value["app"] = dict(self.app)
        if self.team_id is not None:
            value["teamID"] = self.team_id
        if self.expires_at is not None:
            value["expiresAt"] = self.expires_at
        if self.receipt_sha256 is not None:
            value["receiptSHA256"] = self.receipt_sha256
        return value


class SetupProducer:
    """One explicit transaction coordinator for preflight/apply/status/resume."""

    def __init__(
        self,
        config: SetupConfiguration,
        *,
        store: JournalStore | None = None,
        device: DeviceAdapter,
        process: ProcessAdapter | None = None,
        artifact_validator: FormalArtifactValidator | None = None,
        support: SupportAdapter | None = None,
    ):
        self.config = config
        self.store = store or JournalStore(config.state_root)
        self.device = device
        self.process = process
        self.artifact_validator = artifact_validator or FormalArtifactValidator()
        self.support = support

    def handle(self, request: SetupRequest) -> ProducerPayload:
        if request.action == "preflight":
            assert request.options is not None
            return self.preflight(request)
        if request.action == "status":
            return self.status(request)
        if request.action == "resume":
            return self.resume(request)
        if request.action == "apply":
            assert request.options is not None
            return self.apply(request)
        raise SetupBridgeError("invalid-request")

    def preflight(self, request: SetupRequest) -> ProducerPayload:
        options = request.options
        if options is None:
            raise SetupBridgeError("invalid-request")
        self.config.validate_read_only_paths()
        observed = self._observe_device(request.device_id)
        existing = self.device.installed(request.device_id)
        if request.mode == "renew":
            if not existing.present:
                raise SetupBridgeError("app-not-installed")
        elif existing.present:
            raise SetupBridgeError("app-already-installed")
        artifact = None
        if options.source == "signedApp":
            assert options.artifact_path is not None
            artifact = self.artifact_validator.inspect(
                options.artifact_path,
                device_id=request.device_id,
                team_id=options.team_id,
            )
        elif options.source != "project":
            raise SetupBridgeError("invalid-request")
        return self._payload(
            stage="preflight",
            outcome="ready",
            can_resume=False,
            artifact=artifact,
            team_id=options.team_id,
            observed=observed,
        )

    def apply(self, request: SetupRequest) -> ProducerPayload:
        options = request.options
        if options is None:
            raise SetupBridgeError("invalid-request")
        if request.mode == "renew":
            return self._apply_renew(request)
        # State-root creation is a write-side operation.  The CLI validates
        # the frozen paths before constructing this producer; direct injected
        # seams may use a temporary SetupConfiguration for controlled tests.
        self.config.ensure_state_root()
        with self.store.lock():
            # Apply is explicit, but still rechecks the selected USB device
            # and refuses an already-installed GoFly before creating a new
            # transaction record.
            self._observe_device(request.device_id)
            if self.device.installed(request.device_id).present:
                raise SetupBridgeError("app-already-installed")
            existing = self.store.read()
            if existing is not None:
                if existing.get("setupID") == request.setup_id and existing.get("deviceID") == request.device_id:
                    raise SetupBridgeError("transaction-conflict")
                if existing.get("deviceID") == request.device_id:
                    raise SetupBridgeError("transaction-conflict")
                # A proven completed transaction is the only record eligible
                # for replacement, and only for a later explicit setup on a
                # different selected device.  The archive and new intent are
                # serialized by this one already-held global lease.
                if self._journal_is_completed(existing):
                    self.store.archive_completed_locked(existing["setupID"], existing["deviceID"])
                else:
                    raise SetupBridgeError("transaction-conflict")
            journal = self.store.create(
                request.setup_id,
                request.device_id,
                {
                    "source": options.source,
                    "artifactPath": options.artifact_path,
                    "teamID": options.team_id,
                    "allowProvisioningUpdates": options.allow_provisioning_updates,
                    "targetBundleID": self.config.target_bundle_id,
                    "targetName": self.config.target_name,
                    "artifact": None,
                },
            )
            try:
                observed = self._observe_device(request.device_id)
                journal["intent"]["deviceObservation"] = {
                    "deviceID": observed.device_id,
                    "osVersion": observed.os_version,
                    "transport": observed.transport,
                    "developerMode": True,
                    "trust": True,
                }
                journal = self.store.update(journal)
                journal = self.store.checkpoint(journal, "artifact", "inflight")
                artifact = self._build_or_validate(request, observed)
                artifact = snapshot_artifact(
                    artifact,
                    self.store.transaction_root(request.setup_id) / "artifact" / "GoFly.app",
                    self.artifact_validator,
                    device_id=request.device_id,
                    team_id=artifact.team_id,
                )
                journal["intent"]["artifact"] = self._artifact_dict(artifact)
                journal = self.store.checkpoint(journal, "artifact", "confirmed")
                journal = self.store.checkpoint(journal, "pairing", "inflight")
                journal = self._pair(journal, request)
                journal = self.store.checkpoint(
                    journal,
                    "pairing",
                    "confirmed",
                    proof={"pairingImported": False},
                )
                # Installation is the irreversible device boundary.  Journal
                # inflight before calling the injected production adapter.
                if self.device.installed(request.device_id).present:
                    raise SetupBridgeError("app-already-installed")
                journal = self.store.checkpoint(journal, "install", "inflight")
                self._observe_device(request.device_id)
                # Revalidate the immutable local bundle immediately before the
                # irreversible device call.  A check performed earlier in the
                # transaction cannot cover a changed bundle on disk.
                current_artifact = self.artifact_validator.inspect(
                    artifact.path, device_id=request.device_id, team_id=artifact.team_id
                )
                if current_artifact != artifact:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="artifact-changed")
                    raise SetupBridgeError("artifact-mismatch")
                installed = self.device.install(request.device_id, artifact)
                if not self._install_result_confirms(installed, artifact):
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="postcondition-unconfirmed")
                    return self._payload_from_journal(journal, artifact=artifact, can_resume=True)
                # Persist the successful InstallationProxy result together
                # with the confirmed install stage.  A later nonce receipt
                # must still match all exact bundle digests, but it cannot
                # manufacture this ownership record after a lost result.
                journal["installOwnership"] = {
                    "transactionID": request.setup_id,
                    "bundleID": artifact.bundle_id,
                    "build": artifact.build,
                    "artifactSHA256": artifact.artifact_sha256,
                    "executableSHA256": artifact.executable_sha256,
                    "profileSHA256": artifact.profile_sha256,
                }
                journal = self.store.checkpoint(
                    journal,
                    "install",
                    "confirmed",
                    proof={"installationConfirmed": True},
                )
                journal = self._handoff(journal, request, artifact)
                journal = self.store.checkpoint(
                    journal,
                    "complete",
                    "confirmed",
                    proof={
                        "installationConfirmed": True,
                        "pairingImported": True,
                        "supportObserved": True,
                    },
                )
                receipt = self._receipt_digest(journal)
                journal["receiptSHA256"] = receipt
                # This final write records the receipt itself.  If it is
                # interrupted, the complete stage remains durable but the
                # transaction is conservatively resumed from the journal.
                journal = self.store.update(journal)
                return self._payload_from_journal(journal, artifact=artifact, can_resume=False, receipt=receipt)
            except SetupBridgeError as error:
                # Adapter-safe failures after an install checkpoint are still
                # unknown.  The error code is surfaced, while the durable
                # stage prevents any blind install retry on resume.
                stage = self._inflight_stage(journal)
                if stage is not None:
                    with _suppress_journal_errors():
                        journal = self.store.checkpoint(journal, stage, "unknown", detail=error.code)
                raise
            except TimeoutError:
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="timeout")
                raise SetupBridgeError("timeout") from None
            except KeyboardInterrupt:
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="cancelled")
                raise SetupBridgeError("cancelled") from None
            except Exception:
                # Once the irreversible boundary has been entered, process
                # loss and adapter errors are unknown.  They never authorize
                # resubmission or adoption of matching external metadata.
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="operation-failed")
                raise SetupBridgeError("operation-failed") from None

    def _apply_renew(self, request: SetupRequest) -> ProducerPayload:
        options = request.options
        assert options is not None
        self.config.ensure_state_root()
        with self.store.lock():
            observed = self._observe_device(request.device_id)
            if not self.device.installed(request.device_id).present:
                raise SetupBridgeError("app-not-installed")
            existing = self.store.read()
            if existing is not None:
                if existing.get("setupID") == request.setup_id and existing.get("deviceID") == request.device_id:
                    raise SetupBridgeError("transaction-conflict")
                if not self._journal_is_completed(existing):
                    raise SetupBridgeError("transaction-conflict")
                self.store.archive_completed_locked(existing["setupID"], existing["deviceID"])
            journal = self.store.create(
                request.setup_id,
                request.device_id,
                {
                    "source": options.source,
                    "artifactPath": options.artifact_path,
                    "teamID": options.team_id,
                    "allowProvisioningUpdates": options.allow_provisioning_updates,
                    "targetBundleID": self.config.target_bundle_id,
                    "targetName": self.config.target_name,
                    "artifact": None,
                },
                mode="renew",
            )
            try:
                journal["intent"]["deviceObservation"] = {
                    "deviceID": observed.device_id,
                    "osVersion": observed.os_version,
                    "transport": observed.transport,
                    "developerMode": True,
                    "trust": True,
                }
                journal = self.store.update(journal)
                journal = self.store.checkpoint(journal, "artifact", "inflight")
                artifact = self._build_or_validate(request, observed)
                artifact = snapshot_artifact(
                    artifact,
                    self.store.transaction_root(request.setup_id) / "artifact" / "GoFly.app",
                    self.artifact_validator,
                    device_id=request.device_id,
                    team_id=artifact.team_id,
                )
                journal["intent"]["artifact"] = self._artifact_dict(artifact)
                journal = self.store.checkpoint(journal, "artifact", "confirmed")
                journal = self.store.checkpoint(journal, "install", "inflight")
                self._observe_device(request.device_id)
                if not self.device.installed(request.device_id).present:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="app-not-installed")
                    raise SetupBridgeError("app-not-installed")
                current_artifact = self.artifact_validator.inspect(
                    artifact.path, device_id=request.device_id, team_id=artifact.team_id
                )
                if current_artifact != artifact:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="artifact-changed")
                    raise SetupBridgeError("artifact-mismatch")
                installed = self.device.install(request.device_id, artifact)
                if not self._install_result_confirms(installed, artifact):
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="postcondition-unconfirmed")
                    return self._payload_from_journal(journal, artifact=artifact, can_resume=True)
                journal["installOwnership"] = {
                    "transactionID": request.setup_id,
                    "bundleID": artifact.bundle_id,
                    "build": artifact.build,
                    "artifactSHA256": artifact.artifact_sha256,
                    "executableSHA256": artifact.executable_sha256,
                    "profileSHA256": artifact.profile_sha256,
                }
                journal = self.store.checkpoint(
                    journal, "install", "confirmed", proof={"installationConfirmed": True}
                )
                journal = self.store.checkpoint(
                    journal, "complete", "confirmed", proof={"installationConfirmed": True}
                )
                receipt = self._receipt_digest(journal)
                journal["receiptSHA256"] = receipt
                journal = self.store.update(journal)
                return self._payload_from_journal(journal, artifact=artifact, can_resume=False, receipt=receipt)
            except SetupBridgeError as error:
                stage = self._inflight_stage(journal)
                if stage is not None:
                    with _suppress_journal_errors():
                        journal = self.store.checkpoint(journal, stage, "unknown", detail=error.code)
                raise
            except TimeoutError:
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="timeout")
                raise SetupBridgeError("timeout") from None
            except KeyboardInterrupt:
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="cancelled")
                raise SetupBridgeError("cancelled") from None
            except Exception:
                stage = self._inflight_stage(journal)
                with _suppress_journal_errors():
                    if stage is not None:
                        journal = self.store.checkpoint(journal, stage, "unknown", detail="operation-failed")
                raise SetupBridgeError("operation-failed") from None

    def status(self, request: SetupRequest) -> ProducerPayload:
        journal = self.store.read()
        if journal is None:
            raise SetupBridgeError("transaction-unknown")
        self._bind(journal, request)
        return self._payload_from_journal(journal, can_resume=self._can_resume(journal))

    def resume(self, request: SetupRequest) -> ProducerPayload:
        with self.store.lock():
            journal = self.store.read()
            if journal is None:
                raise SetupBridgeError("transaction-unknown")
            self._bind(journal, request)
            if journal.get("mode", "install") == "renew":
                return self._resume_renew(journal, request)
            stages = journal["stages"]
            if stages["artifact"]["state"] in {"pending", "unknown", "inflight"}:
                journal = self._resume_artifact(journal, request)
                stages = journal["stages"]
            if stages["pairing"]["state"] in {"unknown", "inflight"}:
                # Pair setup may have completed while the Mac lost its
                # process.  Verify the retained candidate over a fresh USB
                # connection; never generate or upload another record.
                observed = self._observe_device(request.device_id)
                candidate = self.store.transaction_root(request.setup_id) / "pairing.candidate"
                verified = self.device.verify_pairing(request.device_id, candidate)
                if verified.state != "verified" or not verified.sha256:
                    with _suppress_journal_errors():
                        self.store.checkpoint(journal, "pairing", "unknown", detail="candidate-unverified")
                    raise SetupBridgeError("pairing-unknown")
                journal["pairing"] = {
                    "candidate": "transactions/%s/pairing.candidate" % request.setup_id,
                    "sha256": verified.sha256,
                }
                journal = self.store.checkpoint(journal, "pairing", "confirmed", proof={"pairingImported": False})
                stages = journal["stages"]
            elif stages["pairing"]["state"] == "pending":
                journal = self.store.checkpoint(journal, "pairing", "inflight")
                journal = self._pair(journal, request)
                journal = self.store.checkpoint(journal, "pairing", "confirmed", proof={"pairingImported": False})
                stages = journal["stages"]
            if stages["install"]["state"] == "pending":
                artifact = self._artifact_from_journal(journal)
                if artifact is None:
                    raise SetupBridgeError("transaction-unknown")
                installed_probe = getattr(self.device, "installed", None)
                if not callable(installed_probe):
                    return self._payload_from_journal(journal, can_resume=True)
                if installed_probe(request.device_id).present:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="unexpected-existing-app")
                    return self._payload_from_journal(journal, can_resume=True)
                journal = self.store.checkpoint(journal, "install", "inflight")
                self._observe_device(request.device_id)
                current_artifact = self.artifact_validator.inspect(
                    artifact.path, device_id=request.device_id, team_id=artifact.team_id
                )
                if current_artifact != artifact:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="artifact-changed")
                    raise SetupBridgeError("artifact-mismatch")
                try:
                    installed = self.device.install(request.device_id, artifact)
                except SetupBridgeError as error:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail=error.code)
                    return self._payload_from_journal(journal, can_resume=True)
                except Exception:
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="operation-failed")
                    return self._payload_from_journal(journal, can_resume=True)
                if not self._install_result_confirms(installed, artifact):
                    journal = self.store.checkpoint(journal, "install", "unknown", detail="postcondition-unconfirmed")
                    return self._payload_from_journal(journal, can_resume=True)
                journal["installOwnership"] = {
                    "transactionID": request.setup_id,
                    "bundleID": artifact.bundle_id,
                    "build": artifact.build,
                    "artifactSHA256": artifact.artifact_sha256,
                    "executableSHA256": artifact.executable_sha256,
                    "profileSHA256": artifact.profile_sha256,
                }
                journal = self.store.checkpoint(
                    journal, "install", "confirmed", proof={"installationConfirmed": True}
                )
                stages = journal["stages"]
            # A lost install result is permanently conservative for M1.  A
            # matching external app is observed only for diagnostics and is
            # never adopted, launched, stopped, handed off, or reinstalled.
            if stages["install"]["state"] in {"inflight", "unknown"}:
                self._observe_device(request.device_id)
                with _suppress_journal_errors():
                    self.device.installed(request.device_id)
                return self._payload_from_journal(journal, can_resume=True)
            if stages["install"]["state"] != "confirmed":
                return self._payload_from_journal(journal, can_resume=self._can_resume(journal))
            # A handoff resume must consume its frozen pre-effect plan before
            # any support query/install.  The first App readback and PID stop
            # establish the safe phase for those device boundaries.
            if stages["handoff"]["state"] in {"unknown", "inflight"}:
                return self._resume_handoff(journal, request)
            if stages["handoff"]["state"] == "pending":
                artifact = self._artifact_from_journal(journal)
                if artifact is None:
                    raise SetupBridgeError("transaction-unknown")
                journal = self._handoff(journal, request, artifact)
            stages = journal["stages"]
            if stages["support"]["state"] != "confirmed":
                observed = self._boundary_observe(journal, request.device_id)
                expected_support = journal.get("support") if isinstance(journal.get("support"), Mapping) else None
                journal = self._support(journal, request, observed, expected=expected_support)
            if stages["complete"]["state"] != "confirmed":
                journal = self.store.checkpoint(
                    journal,
                    "complete",
                    "confirmed",
                    proof={
                        "installationConfirmed": True,
                        "pairingImported": True,
                        "supportObserved": True,
                    },
                )
                receipt = self._receipt_digest(journal)
                journal["receiptSHA256"] = receipt
                journal = self.store.update(journal)
            elif not (
                isinstance(journal.get("receiptSHA256"), str)
                and re.fullmatch(r"[0-9a-f]{64}", journal["receiptSHA256"]) is not None
            ):
                # Complete-stage durability and receipt durability are two
                # writes; finish the latter on an explicit resume.
                receipt = self._receipt_digest(journal)
                journal["receiptSHA256"] = receipt
                journal = self.store.update(journal)
            return self._payload_from_journal(journal, can_resume=self._can_resume(journal))

    def _observe_device(self, device_id: str) -> DeviceObservation:
        observed = self.device.observe(device_id)
        if observed.device_id.lower() != device_id.lower():
            raise SetupBridgeError("identity-mismatch")
        if observed.transport.upper() != "USB":
            raise SetupBridgeError("device-disconnected")
        if not _safe_version(observed.os_version) or int(observed.os_version.split(".")[0]) < 26:
            raise SetupBridgeError("unsupported-os")
        if observed.developer_mode is not True:
            raise SetupBridgeError("developer-mode-required")
        if observed.trust is not True:
            raise SetupBridgeError("trust-required")
        return observed

    def _boundary_observe(self, journal: Mapping[str, Any], device_id: str) -> DeviceObservation:
        """Re-read identity and security state immediately before each write boundary."""
        observed = self._observe_device(device_id)
        intent = journal.get("intent", {})
        frozen = intent.get("deviceObservation") if isinstance(intent, Mapping) else None
        if not isinstance(frozen, Mapping):
            raise SetupBridgeError("transaction-unknown")
        if (
            frozen.get("deviceID") != observed.device_id
            or frozen.get("deviceID") != device_id
            or frozen.get("transport") != observed.transport
            or frozen.get("osVersion") != observed.os_version
        ):
            raise SetupBridgeError("identity-mismatch")
        if frozen.get("developerMode") is not True or observed.developer_mode is not True:
            raise SetupBridgeError("developer-mode-required")
        if frozen.get("trust") is not True or observed.trust is not True:
            raise SetupBridgeError("trust-required")
        support = journal.get("support")
        if isinstance(support, Mapping) and support.get("method"):
            if support.get("osVersion") != observed.os_version:
                raise SetupBridgeError("unsupported-os")
            if support.get("method") != support_method(observed.os_version):
                raise SetupBridgeError("support-unavailable")
        return observed

    def _journal_is_completed(self, journal: Mapping[str, Any]) -> bool:
        return self.store._completed_eligible(journal)

    def _build_or_validate(self, request: SetupRequest, observed: DeviceObservation) -> ArtifactIdentity:
        options = request.options
        assert options is not None
        if options.source == "signedApp":
            assert options.artifact_path is not None
            return self.artifact_validator.inspect(options.artifact_path, device_id=request.device_id, team_id=options.team_id)
        if self.process is None:
            raise SetupBridgeError("configuration-invalid")
        try:
            path = self.process.build(
                request.setup_id,
                options.team_id,
                options.allow_provisioning_updates,
            )
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("operation-failed") from None
        if not isinstance(path, Path):
            path = Path(path)
        expected_root = (self.store.transaction_root(request.setup_id) / "build").resolve()
        try:
            path.resolve().relative_to(expected_root)
        except ValueError:
            raise SetupBridgeError("artifact-mismatch") from None
        return self.artifact_validator.inspect(path, device_id=request.device_id, team_id=options.team_id)

    def _pair(self, journal: dict[str, Any], request: SetupRequest) -> dict[str, Any]:
        transaction = self.store.transaction_root(request.setup_id)
        candidate = transaction / "pairing.candidate"
        if candidate.exists() and candidate.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        prepare = getattr(self.device, "prepare_pairing", None)
        if not callable(prepare):
            raise SetupBridgeError("runtime-api-mismatch")
        prepare(request.device_id, candidate)
        observed = self.device.pair(request.device_id, candidate)
        if observed.state != "verified":
            raise SetupBridgeError("pairing-unknown")
        verified = self.device.verify_pairing(request.device_id, candidate)
        if verified.state != "verified":
            raise SetupBridgeError("pairing-unknown")
        journal["pairing"] = {
            "candidate": "transactions/%s/pairing.candidate" % request.setup_id,
            "sha256": verified.sha256,
        }
        return self.store.update(journal)

    def _support(
        self,
        journal: dict[str, Any],
        request: SetupRequest,
        observed: DeviceObservation,
        *,
        expected: Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        method = support_method(observed.os_version)
        transaction = self.store.transaction_root(request.setup_id)
        restore_dir = transaction / "support"
        if self.support is not None and hasattr(self.support, "restore_dir"):
            # The support adapter is bound to this transaction's immutable
            # inventory before query, so an observed service cannot be treated
            # as ready from a cache-only/global flag.
            self.support.restore_dir = restore_dir

        def support_unknown(detail: str) -> None:
            with _suppress_journal_errors():
                self.store.checkpoint(journal, "support", "unknown", detail=detail)
            raise SetupBridgeError("support-unavailable")

        def require_actual_support(value: Any, planned_support: Mapping[str, Any] | None = None) -> None:
            """Require an actual, complete same-device support observation."""
            if (
                getattr(value, "observed", None) is not True
                or getattr(value, "method", None) != method
                or getattr(value, "os_version", None) != observed.os_version
            ):
                support_unknown("postcondition-unconfirmed")
            generation_id = getattr(value, "generation_id", None)
            identifier = getattr(value, "identifier", None)
            version = getattr(value, "version", None)
            if (
                not isinstance(generation_id, str)
                or not generation_id
                or generation_id.lower() != request.setup_id.lower()
                or not isinstance(identifier, str)
                or not identifier
                or not isinstance(version, str)
                or not version
            ):
                support_unknown("postcondition-unconfirmed")
            if planned_support is not None:
                if (
                    planned_support.get("method") != method
                    or planned_support.get("osVersion") != observed.os_version
                    or (
                        isinstance(planned_support.get("generationID"), str)
                        and planned_support.get("generationID")
                        and generation_id.lower() != planned_support["generationID"].lower()
                    )
                    or (
                        planned_support.get("identifier")
                        and identifier != planned_support.get("identifier")
                    )
                    or (
                        planned_support.get("version")
                        and version != planned_support.get("version")
                    )
                ):
                    support_unknown("identity-changed")

        query = self.support.query if self.support is not None else self.device.query_support
        current = query(request.device_id, method)
        if current.method != method or current.os_version != observed.os_version:
            support_unknown("identity-changed")

        try:
            from .setup_support import validate_generation
        except ImportError:
            from setup_support import validate_generation

        def validated_generation() -> Any:
            try:
                return validate_generation(method, restore_dir)
            except SetupBridgeError:
                raise
            except Exception:
                raise SetupBridgeError("support-unavailable") from None

        def frozen_files(generation: Any) -> dict[str, list[Any]]:
            files = getattr(generation, "files", None)
            if not isinstance(files, Mapping) or not files:
                raise SetupBridgeError("support-unavailable")
            result: dict[str, list[Any]] = {}
            for label, pair in files.items():
                if not isinstance(label, str) or not isinstance(pair, tuple) or len(pair) != 2:
                    raise SetupBridgeError("support-unavailable")
                size, digest = pair
                if type(size) is not int or size <= 0 or not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                    raise SetupBridgeError("support-unavailable")
                result[label] = [size, digest]
            return result

        planned = expected if expected is not None else journal.get("support")
        planned_files = planned.get("inputFiles") if isinstance(planned, Mapping) else None
        if planned_files is not None:
            if not isinstance(planned, Mapping) or not isinstance(planned.get("inputManifestSHA256"), str):
                support_unknown("input-changed")
            generation = validated_generation()
            current_files = frozen_files(generation)
            current_manifest = getattr(generation, "manifest_sha256", None)
            if current_files != planned_files or current_manifest != planned.get("inputManifestSHA256"):
                support_unknown("input-changed")
            if not current.observed:
                installer = self.support.install if self.support is not None else self.device.install_support
                current = installer(request.device_id, method, transaction / "support")
            require_actual_support(current, planned)
            frozen_support = copy.deepcopy(dict(planned))
            frozen_support["generationID"] = current.generation_id
            frozen_support["identifier"] = current.identifier
            frozen_support["version"] = current.version
            journal["support"] = frozen_support
            return self.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})
        if expected is not None:
            support_unknown("input-changed")

        # The generation is fetched/copied and fully validated before any
        # installer/mounter call.  Its closed file hashes are journaled before
        # crossing that irreversible service boundary.
        prepare = getattr(self.support, "prepare_generation", None) if self.support is not None else None
        if not callable(prepare):
            prepare = getattr(self.device, "prepare_generation", None)
        if not callable(prepare):
            raise SetupBridgeError("support-unavailable")
        try:
            prepare(method, restore_dir)
            generation = validated_generation()
            input_files = frozen_files(generation)
            input_manifest = getattr(generation, "manifest_sha256", None)
            if not isinstance(input_manifest, str) or re.fullmatch(r"[0-9a-f]{64}", input_manifest) is None:
                raise SetupBridgeError("support-unavailable")
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("support-unavailable") from None
        journal = self.store.checkpoint(journal, "support", "inflight")
        journal["support"] = {
            "method": method,
            "osVersion": observed.os_version,
            "generationID": current.generation_id if isinstance(current.generation_id, str) else "",
            "identifier": current.identifier if isinstance(current.identifier, str) else "",
            "version": current.version if isinstance(current.version, str) else "",
            "inputFiles": input_files,
            "inputManifestSHA256": input_manifest,
        }
        journal = self.store.update(journal)
        if current.observed:
            # An observed service with incomplete identity is not repaired by
            # another query or remount; it is an unknown proof state.
            require_actual_support(current)
        else:
            installer = self.support.install if self.support is not None else self.device.install_support
            current = installer(request.device_id, method, transaction / "support")
            require_actual_support(current)
        journal["support"] = {
            "method": current.method,
            "osVersion": current.os_version,
            "generationID": current.generation_id,
            "identifier": current.identifier,
            "version": current.version,
            "inputFiles": input_files,
            "inputManifestSHA256": input_manifest,
        }
        return self.store.checkpoint(journal, "support", "confirmed", proof={"supportObserved": True})

    @staticmethod
    def _validate_activation_receipt(
        receipt: Any,
        *,
        request: SetupRequest,
        artifact: ArtifactIdentity,
        journal: Mapping[str, Any],
        manifest_sha256: str,
    ) -> None:
        """Require the exact App committed receipt before handoff success."""
        if receipt is None:
            raise SetupBridgeError("handoff-unknown")
        support = journal.get("support", {})
        intent = journal.get("intent", {})
        pairing = journal.get("pairing", {})
        if not isinstance(support, Mapping) or not isinstance(intent, Mapping) or not isinstance(pairing, Mapping):
            raise SetupBridgeError("handoff-unknown")
        expected_tx = intent.get("pairingTransactionID")
        expected_pairing = pairing.get("sha256")
        try:
            matches = (
                receipt.setup_id.lower() == request.setup_id.lower()
                and receipt.nonce.lower() == str(journal.get("handoff", {}).get("nonce", "")).lower()
                and receipt.device_id.lower() == request.device_id.lower()
                and receipt.raw_manifest_sha256 == manifest_sha256
                and receipt.pairing_transaction_id.lower() == str(expected_tx).lower()
                and receipt.pairing_sha256 == expected_pairing
                and receipt.bundle_id == artifact.bundle_id
                and receipt.build == artifact.build
                and receipt.profile_sha256 == artifact.profile_sha256
                and receipt.executable_sha256 == artifact.executable_sha256
                and receipt.team_id == artifact.team_id
                and receipt.signing_expiry == artifact.expires_at
                and receipt.device_os == support.get("osVersion")
                and receipt.method == support.get("method")
                and receipt.generation_id.lower() == str(support.get("generationID", "")).lower()
            )
        except (AttributeError, TypeError):
            matches = False
        if not matches:
            raise SetupBridgeError("handoff-unknown")
        expected_inventory = journal.get("handoff", {}).get("formalArtifacts")
        if expected_inventory is not None:
            if not isinstance(expected_inventory, list):
                raise SetupBridgeError("handoff-unknown")
            expected_records = tuple(
                (
                    entry.get("id"), entry.get("filename"), entry.get("byteCount"), entry.get("sha256")
                )
                for entry in expected_inventory
                if isinstance(entry, Mapping)
            )
            if len(expected_records) != len(expected_inventory) or tuple(getattr(receipt, "artifact_records", ())) != expected_records:
                raise SetupBridgeError("handoff-unknown")

    @staticmethod
    def _activation_binding(receipt: Any) -> dict[str, Any]:
        records = [
            {"id": item[0], "filename": item[1], "byteCount": item[2], "sha256": item[3]}
            for item in getattr(receipt, "artifact_records", ())
        ]
        return {
            "setupID": receipt.setup_id,
            "nonce": receipt.nonce,
            "deviceID": receipt.device_id,
            "rawManifestSHA256": receipt.raw_manifest_sha256,
            "pairingTransactionID": receipt.pairing_transaction_id,
            "pairingSHA256": receipt.pairing_sha256,
            "bundleID": receipt.bundle_id,
            "build": receipt.build,
            "profileSHA256": receipt.profile_sha256,
            "executableSHA256": receipt.executable_sha256,
            "teamID": receipt.team_id,
            "signingExpiry": receipt.signing_expiry,
            "deviceOS": receipt.device_os,
            "method": receipt.method,
            "generationID": receipt.generation_id,
            "artifacts": records,
        }

    @staticmethod
    def _validate_readback(
        result: Any,
        *,
        request: SetupRequest,
        nonce: str,
        artifact: ArtifactIdentity,
        journal: Mapping[str, Any],
    ) -> None:
        if result is None:
            raise SetupBridgeError("handoff-unknown")
        if (
            result.nonce.lower() != nonce.lower()
            or result.setup_id.lower() != request.setup_id.lower()
            or result.device_id.lower() != request.device_id.lower()
            or result.executable_sha256 != artifact.executable_sha256
            or result.profile_sha256 != artifact.profile_sha256
            or (result.artifact_sha256 and result.artifact_sha256 != artifact.artifact_sha256)
            or (result.build and result.build != artifact.build)
        ):
            raise SetupBridgeError("handoff-unknown")
        pairing = journal.get("pairing", {})
        if result.pairing_sha256 and result.pairing_sha256 != pairing.get("sha256"):
            raise SetupBridgeError("handoff-unknown")
        support = journal.get("support", {})
        if result.support_method and result.support_method != support.get("method"):
            raise SetupBridgeError("handoff-unknown")
        if result.support_generation_id and result.support_generation_id != support.get("generationID"):
            raise SetupBridgeError("handoff-unknown")

    @staticmethod
    def _bounded_read(
        reader: Any,
        *,
        validate: Any,
        deadline: float = 30.0,
        poll: float = 0.05,
    ) -> Any:
        """Poll a just-launched App at a fixed deadline, then validate once."""
        end = time.monotonic() + deadline
        while True:
            value = reader()
            if value is not None:
                validate(value)
                return value
            remaining = end - time.monotonic()
            if remaining <= 0:
                raise SetupBridgeError("timeout")
            time.sleep(min(poll, remaining))

    def _prepare_local_support(self, journal: dict[str, Any], request: SetupRequest, observed: DeviceObservation) -> dict[str, Any]:
        """Prepare and freeze local support bytes without touching the device."""
        method = support_method(observed.os_version)
        existing = journal.get("support")
        if isinstance(existing, Mapping) and existing.get("inputFiles") is not None:
            frozen = copy.deepcopy(dict(existing))
            if frozen.get("method") != method or frozen.get("osVersion") != observed.os_version:
                raise SetupBridgeError("support-unavailable")
            # A pending handoff may carry an input map from an earlier local
            # preparation attempt.  Revalidate that map against the private
            # generation before freezing a new formal plan; a confirmed
            # support checkpoint may be reused because _support rechecks the
            # device identity at its service boundary.
            if journal.get("stages", {}).get("support", {}).get("state") != "confirmed":
                try:
                    from .setup_support import validate_generation
                except ImportError:
                    from setup_support import validate_generation
                restore_dir = self.store.transaction_root(request.setup_id) / "support"
                try:
                    generation = validate_generation(method, restore_dir)
                    files = getattr(generation, "files", None)
                    manifest_sha = getattr(generation, "manifest_sha256", None)
                    if not isinstance(files, Mapping) or manifest_sha != frozen.get("inputManifestSHA256"):
                        raise SetupBridgeError("support-unavailable")
                    actual_files: dict[str, list[Any]] = {}
                    for label, pair in files.items():
                        if (
                            not isinstance(label, str)
                            or not isinstance(pair, tuple)
                            or len(pair) != 2
                            or type(pair[0]) is not int
                            or pair[0] <= 0
                            or not isinstance(pair[1], str)
                            or re.fullmatch(r"[0-9a-f]{64}", pair[1]) is None
                        ):
                            raise SetupBridgeError("support-unavailable")
                        actual_files[label] = [pair[0], pair[1]]
                    if actual_files != frozen.get("inputFiles"):
                        raise SetupBridgeError("support-unavailable")
                except SetupBridgeError:
                    raise
                except Exception:
                    raise SetupBridgeError("support-unavailable") from None
            return frozen
        prepare = getattr(self.support, "prepare_generation", None) if self.support is not None else None
        if not callable(prepare):
            prepare = getattr(self.device, "prepare_generation", None)
        if not callable(prepare):
            raise SetupBridgeError("support-unavailable")
        restore_dir = self.store.transaction_root(request.setup_id) / "support"
        try:
            prepare(method, restore_dir)
            try:
                from .setup_support import validate_generation
            except ImportError:
                from setup_support import validate_generation
            generation = validate_generation(method, restore_dir)
            files = getattr(generation, "files", None)
            manifest_sha = getattr(generation, "manifest_sha256", None)
            if not isinstance(files, Mapping) or not isinstance(manifest_sha, str):
                raise SetupBridgeError("support-unavailable")
            frozen_files: dict[str, list[Any]] = {}
            for label, pair in files.items():
                if not isinstance(label, str) or not isinstance(pair, tuple) or len(pair) != 2:
                    raise SetupBridgeError("support-unavailable")
                size, digest = pair
                if type(size) is not int or size <= 0 or not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                    raise SetupBridgeError("support-unavailable")
                frozen_files[label] = [size, digest]
            if re.fullmatch(r"[0-9a-f]{64}", manifest_sha) is None or frozen_files.get("manifest", [None, None])[1] != manifest_sha:
                raise SetupBridgeError("support-unavailable")
            return {
                "method": method,
                "osVersion": observed.os_version,
                "generationID": request.setup_id.lower(),
                "identifier": existing.get("identifier", "") if isinstance(existing, Mapping) else "",
                "version": existing.get("version", "") if isinstance(existing, Mapping) else "",
                "inputFiles": frozen_files,
                "inputManifestSHA256": manifest_sha,
            }
        except SetupBridgeError:
            raise
        except Exception:
            raise SetupBridgeError("support-unavailable") from None

    @staticmethod
    def _formal_plan(
        journal: Mapping[str, Any],
        *,
        request: SetupRequest,
        artifact: ArtifactIdentity,
        nonce: str,
    ) -> FormalSetupInput:
        intent = journal.get("intent")
        pairing = journal.get("pairing")
        support = journal.get("support")
        tx = intent.get("pairingTransactionID") if isinstance(intent, Mapping) else None
        pairing_sha = pairing.get("sha256") if isinstance(pairing, Mapping) else None
        if not isinstance(tx, str) or not isinstance(pairing_sha, str) or not isinstance(support, Mapping):
            raise SetupBridgeError("handoff-unknown")
        return build_formal_setup_input(
            device_id=request.device_id,
            setup_id=request.setup_id,
            nonce=nonce,
            artifact=artifact,
            pairing_transaction_id=tx,
            pairing_sha256=pairing_sha,
            support=support,
        )

    def _frozen_plan_from_handoff(
        self,
        journal: Mapping[str, Any],
        *,
        request: SetupRequest,
        artifact: ArtifactIdentity,
    ) -> FormalSetupInput:
        handoff = journal.get("handoff")
        if not isinstance(handoff, Mapping):
            raise SetupBridgeError("transaction-unknown")
        nonce = handoff.get("nonce")
        raw = handoff.get("rawManifest")
        stored_sha = handoff.get("manifestSHA256")
        stored_records = handoff.get("formalArtifacts")
        if (
            not isinstance(nonce, str)
            or not isinstance(raw, str)
            or not isinstance(stored_sha, str)
            or not isinstance(stored_records, list)
        ):
            raise SetupBridgeError("transaction-unknown")
        expected = self._formal_plan(journal, request=request, artifact=artifact, nonce=nonce)
        if (
            raw.encode("utf-8") != expected.raw_manifest
            or stored_sha != expected.sha256
            or tuple(
                (item.get("id"), item.get("filename"), item.get("byteCount"), item.get("sha256"))
                for item in stored_records
                if isinstance(item, Mapping)
            ) != expected.artifacts
            or len(stored_records) != len(expected.artifacts)
        ):
            raise SetupBridgeError("transaction-unknown")
        return expected

    def _handoff(self, journal: dict[str, Any], request: SetupRequest, artifact: ArtifactIdentity) -> dict[str, Any]:
        frozen_observation = journal.get("intent", {}).get("deviceObservation") if isinstance(journal.get("intent"), Mapping) else None
        existing_support = journal.get("support")
        if isinstance(existing_support, Mapping) and existing_support.get("inputFiles") is not None and isinstance(frozen_observation, Mapping):
            observed = DeviceObservation(
                request.device_id,
                str(frozen_observation.get("osVersion")),
                str(frozen_observation.get("transport", "USB")),
                True,
                True,
            )
        else:
            observed = self._observe_device(request.device_id)
        nonce = str(uuid.uuid4()).upper()
        support = self._prepare_local_support(journal, request, observed)
        journal["support"] = support
        plan = self._formal_plan(journal, request=request, artifact=artifact, nonce=nonce)
        journal["handoff"] = {
            "nonce": nonce,
            "setupID": request.setup_id,
            "formalPublished": False,
            "rawManifest": plan.raw_manifest.decode("utf-8"),
            "manifestSHA256": plan.sha256,
            "formalArtifacts": [
                {"id": item[0], "filename": item[1], "byteCount": item[2], "sha256": item[3]}
                for item in plan.artifacts
            ],
        }
        # This is the single atomic begin of the handoff.  Until this write,
        # the stage remains pending and no remote handoff boundary is entered.
        journal["stages"]["handoff"] = {"state": "inflight"}
        journal = self.store.update(journal)
        prepare = getattr(self.device, "prepare_readback", None)
        if not callable(prepare):
            raise SetupBridgeError("handoff-unknown")
        self._boundary_observe(journal, request.device_id)
        prepare(request.device_id, request.setup_id, nonce, artifact)
        launch = getattr(self.device, "launch", None)
        stop = getattr(self.device, "stop", None)
        readback = getattr(self.device, "readback", None)
        if not callable(launch) or not callable(stop) or not callable(readback):
            raise SetupBridgeError("handoff-unknown")
        # The first launch only establishes the transaction-owned process and
        # exact Bundle readback.  Stop it before staging support or formal
        # setup input, as required by the App bootstrap boundary.
        self._boundary_observe(journal, request.device_id)
        launched_pid = launch(request.device_id)
        if type(launched_pid) is not int or launched_pid <= 0:
            raise SetupBridgeError("handoff-unknown")
        journal["handoff"]["launchedPID"] = launched_pid
        journal = self.store.update(journal)
        result = self._bounded_read(
            lambda: readback(request.device_id, request.setup_id, nonce),
            validate=lambda value: self._validate_readback(
                value, request=request, nonce=nonce, artifact=artifact, journal=journal
            ),
        )
        # Stop only after the entire current-Bundle identity has been proven.
        # If validation or stop fails, launchedPID remains durable and resume
        # must reobserve the same identity before attempting a kill.
        self._boundary_observe(journal, request.device_id)
        stop(request.device_id, launched_pid)
        journal["handoff"]["launchedPID"] = None
        journal = self.store.update(journal)

        # Pairing import is deliberately after the clean first readback.  The
        # App may report absent/invalid stored pairing during bootstrap; the
        # final activation receipt is the sole pairing proof.
        delivery = journal.get("delivery", {}).get("state", "notStarted")
        if delivery == "notStarted":
            deliver = getattr(self.device, "deliver_pairing", None)
            if not callable(deliver):
                raise SetupBridgeError("handoff-unknown")
            self._boundary_observe(journal, request.device_id)
            journal, _ = deliver_v1_once(
                self.store,
                journal,
                device_id=request.device_id,
                setup_id=request.setup_id,
                deliver=deliver,
            )
        elif delivery in {"inflight", "unknown"}:
            raise SetupBridgeError("transaction-unknown")

        # Support query/install is reached only after the clean first launch
        # identity has been validated and stopped.  This also keeps a clean
        # install from requiring a pre-existing pairing hash during bootstrap.
        if journal.get("stages", {}).get("support", {}).get("state") != "confirmed":
            observed = self._boundary_observe(journal, request.device_id)
            journal = self._support(journal, request, observed, expected=copy.deepcopy(journal.get("support", {})))

        prepare_input = getattr(self.device, "prepare_setup_input", None)
        read_receipt = getattr(self.device, "read_activation_receipt", None)
        intent = journal.get("intent", {})
        pairing = journal.get("pairing", {})
        pairing_transaction_id = intent.get("pairingTransactionID") if isinstance(intent, Mapping) else None
        pairing_sha256 = pairing.get("sha256") if isinstance(pairing, Mapping) else None
        support = journal.get("support", {})
        if (
            not callable(prepare_input)
            or not callable(read_receipt)
            or not isinstance(pairing_transaction_id, str)
            or not isinstance(pairing_sha256, str)
            or not isinstance(support, Mapping)
        ):
            raise SetupBridgeError("handoff-unknown")
        self._boundary_observe(journal, request.device_id)
        manifest_sha256 = prepare_input(
            request.device_id,
            request.setup_id,
            nonce,
            artifact,
            pairing_transaction_id,
            pairing_sha256,
            support,
            plan=plan,
        )
        if manifest_sha256 != plan.sha256:
            raise SetupBridgeError("handoff-unknown")
        inventory_getter = getattr(self.device, "formal_inventory", None)
        if callable(inventory_getter):
            inventory = inventory_getter(request.setup_id, nonce)
            if not isinstance(inventory, tuple) or inventory != plan.artifacts:
                raise SetupBridgeError("handoff-unknown")
        # This marker is the durable phase boundary for activation receipt
        # polling.  It must follow the validated formal upload and precede
        # the second launch; a manifest digest alone is not evidence that the
        # first launch has completed cleanly.
        journal["handoff"]["formalPublished"] = True
        journal = self.store.update(journal)

        # A second, transaction-owned launch consumes the immutable formal
        # envelope.  The App-owned activation record is the completion proof;
        # readback metadata alone never upgrades the handoff stage.
        self._boundary_observe(journal, request.device_id)
        launched_pid = launch(request.device_id)
        if type(launched_pid) is not int or launched_pid <= 0:
            raise SetupBridgeError("handoff-unknown")
        journal["handoff"]["launchedPID"] = launched_pid
        journal = self.store.update(journal)
        activation = self._bounded_read(
            lambda: read_receipt(request.device_id, request.setup_id, nonce),
            validate=lambda value: self._validate_activation_receipt(
                value,
                request=request,
                artifact=artifact,
                journal=journal,
                manifest_sha256=manifest_sha256,
            ),
        )
        self._boundary_observe(journal, request.device_id)
        stop(request.device_id, launched_pid)
        journal["handoff"]["launchedPID"] = None
        journal = self.store.update(journal)
        self._validate_activation_receipt(
            activation,
            request=request,
            artifact=artifact,
            journal=journal,
            manifest_sha256=manifest_sha256,
        )
        journal["activationReceipt"] = self._activation_binding(activation)
        journal = self.store.update(journal)

        # Query first; install only when that query proves the selected
        # generation is absent.  This is a fresh same-device observation after
        # the App data commit.
        expected_support = copy.deepcopy(journal.get("support", {}))
        observed = self._boundary_observe(journal, request.device_id)
        journal = self._support(journal, request, observed, expected=expected_support)
        journal = self.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})
        return journal

    def _resume_renew(self, journal: dict[str, Any], request: SetupRequest) -> ProducerPayload:
        stages = journal["stages"]
        if stages["artifact"]["state"] in {"pending", "unknown", "inflight"}:
            journal = self._resume_artifact(journal, request)
            stages = journal["stages"]
        if stages["install"]["state"] == "pending":
            artifact = self._artifact_from_journal(journal)
            if artifact is None:
                raise SetupBridgeError("transaction-unknown")
            self._observe_device(request.device_id)
            if not self.device.installed(request.device_id).present:
                journal = self.store.checkpoint(journal, "install", "unknown", detail="app-not-installed")
                return self._payload_from_journal(journal, can_resume=True)
            journal = self.store.checkpoint(journal, "install", "inflight")
            current_artifact = self.artifact_validator.inspect(
                artifact.path, device_id=request.device_id, team_id=artifact.team_id
            )
            if current_artifact != artifact:
                journal = self.store.checkpoint(journal, "install", "unknown", detail="artifact-changed")
                raise SetupBridgeError("artifact-mismatch")
            try:
                installed = self.device.install(request.device_id, artifact)
            except SetupBridgeError as error:
                journal = self.store.checkpoint(journal, "install", "unknown", detail=error.code)
                return self._payload_from_journal(journal, can_resume=True)
            except Exception:
                journal = self.store.checkpoint(journal, "install", "unknown", detail="operation-failed")
                return self._payload_from_journal(journal, can_resume=True)
            if not self._install_result_confirms(installed, artifact):
                journal = self.store.checkpoint(journal, "install", "unknown", detail="postcondition-unconfirmed")
                return self._payload_from_journal(journal, can_resume=True)
            journal["installOwnership"] = {
                "transactionID": request.setup_id,
                "bundleID": artifact.bundle_id,
                "build": artifact.build,
                "artifactSHA256": artifact.artifact_sha256,
                "executableSHA256": artifact.executable_sha256,
                "profileSHA256": artifact.profile_sha256,
            }
            journal = self.store.checkpoint(
                journal, "install", "confirmed", proof={"installationConfirmed": True}
            )
            stages = journal["stages"]
        if stages["install"]["state"] in {"inflight", "unknown"}:
            self._observe_device(request.device_id)
            with _suppress_journal_errors():
                self.device.installed(request.device_id)
            return self._payload_from_journal(journal, can_resume=True)
        if stages["install"]["state"] != "confirmed":
            return self._payload_from_journal(journal, can_resume=self._can_resume(journal))
        if stages["complete"]["state"] != "confirmed":
            journal = self.store.checkpoint(
                journal, "complete", "confirmed", proof={"installationConfirmed": True}
            )
            receipt = self._receipt_digest(journal)
            journal["receiptSHA256"] = receipt
            journal = self.store.update(journal)
        elif not (
            isinstance(journal.get("receiptSHA256"), str)
            and re.fullmatch(r"[0-9a-f]{64}", journal["receiptSHA256"]) is not None
        ):
            receipt = self._receipt_digest(journal)
            journal["receiptSHA256"] = receipt
            journal = self.store.update(journal)
        return self._payload_from_journal(journal, can_resume=self._can_resume(journal))

    def _resume_handoff(self, journal: dict[str, Any], request: SetupRequest) -> ProducerPayload:
        artifact = self._artifact_from_journal(journal)
        handoff = journal.get("handoff")
        delivery = journal.get("delivery", {}).get("state")
        nonce = handoff.get("nonce") if isinstance(handoff, Mapping) else None
        formal_published = handoff.get("formalPublished") if isinstance(handoff, Mapping) else None
        if (
            artifact is None
            or delivery not in {"notStarted", "delivered"}
            or not isinstance(nonce, str)
            or type(formal_published) is not bool
        ):
            # Delivery ambiguity and a missing phase marker are permanently
            # query-only.  They never authorize another v1 upload.
            raise SetupBridgeError("transaction-unknown")
        plan = self._frozen_plan_from_handoff(journal, request=request, artifact=artifact)
        journal = self.store.checkpoint(journal, "handoff", "inflight")

        readback = getattr(self.device, "readback", None)
        read_receipt = getattr(self.device, "read_activation_receipt", None)
        stop = getattr(self.device, "stop", None)
        launch = getattr(self.device, "launch", None)
        if not callable(readback) or not callable(read_receipt) or not callable(stop) or not callable(launch):
            raise SetupBridgeError("handoff-unknown")

        # A marker-false transaction is still before formal publication.  A
        # durable PID must therefore be reconciled with the first readback,
        # never with an activation receipt whose digest merely exists.
        launched_pid = handoff.get("launchedPID") if isinstance(handoff, Mapping) else None
        activation: Any | None = None
        if not formal_published and launched_pid is None:
            prepare = getattr(self.device, "prepare_readback", None)
            if not callable(prepare):
                raise SetupBridgeError("handoff-unknown")
            self._boundary_observe(journal, request.device_id)
            prepare(request.device_id, request.setup_id, nonce, artifact)
            self._boundary_observe(journal, request.device_id)
            launched_pid = launch(request.device_id)
            if type(launched_pid) is not int or launched_pid <= 0:
                raise SetupBridgeError("handoff-unknown")
            journal["handoff"]["launchedPID"] = launched_pid
            journal = self.store.update(journal)

        if launched_pid is not None:
            self._boundary_observe(journal, request.device_id)
            if formal_published:
                activation = self._bounded_read(
                    lambda: read_receipt(request.device_id, request.setup_id, nonce),
                    validate=lambda value: self._validate_activation_receipt(
                        value,
                        request=request,
                        artifact=artifact,
                        journal=journal,
                        manifest_sha256=plan.sha256,
                    ),
                )
            else:
                self._bounded_read(
                    lambda: readback(request.device_id, request.setup_id, nonce),
                    validate=lambda value: self._validate_readback(
                        value, request=request, nonce=nonce, artifact=artifact, journal=journal
                    ),
                )
            self._boundary_observe(journal, request.device_id)
            stop(request.device_id, launched_pid)
            journal["handoff"]["launchedPID"] = None
            journal = self.store.update(journal)

        # Before the marker, delivery may still be safely unentered.  Reuse
        # only the frozen candidate and nonce; ambiguous delivery remains
        # rejected by the entry guard above.
        if not formal_published:
            if delivery == "notStarted":
                deliver = getattr(self.device, "deliver_pairing", None)
                if not callable(deliver):
                    raise SetupBridgeError("handoff-unknown")
                self._boundary_observe(journal, request.device_id)
                journal, _ = deliver_v1_once(
                    self.store,
                    journal,
                    device_id=request.device_id,
                    setup_id=request.setup_id,
                    deliver=deliver,
                )
                delivery = journal.get("delivery", {}).get("state")
            if delivery != "delivered":
                raise SetupBridgeError("transaction-unknown")

            # Support query/install is permitted only after the clean first
            # readback and PID stop.  It revalidates the frozen local input.
            observed = self._boundary_observe(journal, request.device_id)
            journal = self._support(
                journal,
                request,
                observed,
                expected=copy.deepcopy(journal.get("support", {})),
            )
            support = journal.get("support", {})
            if not isinstance(support, Mapping):
                raise SetupBridgeError("handoff-unknown")
            intent = journal.get("intent", {})
            pairing = journal.get("pairing", {})
            pairing_transaction_id = intent.get("pairingTransactionID") if isinstance(intent, Mapping) else None
            pairing_sha256 = pairing.get("sha256") if isinstance(pairing, Mapping) else None
            prepare_input = getattr(self.device, "prepare_setup_input", None)
            if (
                not callable(prepare_input)
                or not isinstance(pairing_transaction_id, str)
                or not isinstance(pairing_sha256, str)
            ):
                raise SetupBridgeError("handoff-unknown")
            self._boundary_observe(journal, request.device_id)
            manifest_sha256 = prepare_input(
                request.device_id,
                request.setup_id,
                nonce,
                artifact,
                pairing_transaction_id,
                pairing_sha256,
                support,
                plan=plan,
            )
            if manifest_sha256 != plan.sha256:
                raise SetupBridgeError("handoff-unknown")
            inventory_getter = getattr(self.device, "formal_inventory", None)
            if callable(inventory_getter):
                inventory = inventory_getter(request.setup_id, nonce)
                if not isinstance(inventory, tuple) or inventory != plan.artifacts:
                    raise SetupBridgeError("handoff-unknown")
            journal["handoff"]["formalPublished"] = True
            journal = self.store.update(journal)
            formal_published = True

        # Once formalPublished is durable, activation polling is the only
        # remaining handoff phase.  Reuse the same nonce and immutable plan.
        if not formal_published or journal.get("delivery", {}).get("state") != "delivered":
            raise SetupBridgeError("transaction-unknown")
        if activation is None:
            # The first activation read after a durable formal publication is
            # still a device boundary.  A process restart must not trust the
            # old observation that created the journal before reading a
            # receipt from a newly attached or changed device.
            self._boundary_observe(journal, request.device_id)
            activation = read_receipt(request.device_id, request.setup_id, nonce)
        if activation is None:
            # Receipt absence causes one recovery launch only after a second
            # fresh binding check.  This keeps changed OS/developer/trust
            # state from reaching the device process boundary.
            self._boundary_observe(journal, request.device_id)
            launched_pid = launch(request.device_id)
            if type(launched_pid) is not int or launched_pid <= 0:
                raise SetupBridgeError("handoff-unknown")
            journal["handoff"]["launchedPID"] = launched_pid
            journal = self.store.update(journal)
            activation = self._bounded_read(
                lambda: read_receipt(request.device_id, request.setup_id, nonce),
                validate=lambda value: self._validate_activation_receipt(
                    value,
                    request=request,
                    artifact=artifact,
                    journal=journal,
                    manifest_sha256=plan.sha256,
                ),
            )
            self._boundary_observe(journal, request.device_id)
            stop(request.device_id, launched_pid)
            journal["handoff"]["launchedPID"] = None
            journal = self.store.update(journal)
        self._validate_activation_receipt(
            activation,
            request=request,
            artifact=artifact,
            journal=journal,
            manifest_sha256=plan.sha256,
        )
        journal["activationReceipt"] = self._activation_binding(activation)
        journal = self.store.update(journal)
        expected_support = copy.deepcopy(journal.get("support", {}))
        observed = self._boundary_observe(journal, request.device_id)
        journal = self._support(journal, request, observed, expected=expected_support)
        journal = self.store.checkpoint(journal, "handoff", "confirmed", proof={"pairingImported": True})
        journal = self.store.checkpoint(
            journal,
            "complete",
            "confirmed",
            proof={"installationConfirmed": True, "pairingImported": True, "supportObserved": True},
        )
        receipt = self._receipt_digest(journal)
        journal["receiptSHA256"] = receipt
        journal = self.store.update(journal)
        return self._payload_from_journal(journal, can_resume=False, receipt=receipt)

    @staticmethod
    def _install_result_confirms(installed: InstalledAppObservation, artifact: ArtifactIdentity) -> bool:
        """Check only the install API result; exact app identity is read back later."""
        return (
            installed.present
            and installed.bundle_id == artifact.bundle_id
            and (installed.build is None or installed.build == artifact.build)
        )

    @staticmethod
    def _artifact_dict(artifact: ArtifactIdentity) -> dict[str, Any]:
        return {
            "path": artifact.path,
            "bundleID": artifact.bundle_id,
            "executable": artifact.executable,
            "teamID": artifact.team_id,
            "artifactSHA256": artifact.artifact_sha256,
            "executableSHA256": artifact.executable_sha256,
            "profileSHA256": artifact.profile_sha256,
            "expiresAt": artifact.expires_at,
            "build": artifact.build,
        }

    @staticmethod
    def _artifact_from_journal(journal: Mapping[str, Any]) -> ArtifactIdentity | None:
        value = journal.get("intent", {}).get("artifact") if isinstance(journal.get("intent"), Mapping) else None
        if not isinstance(value, Mapping):
            return None
        fields = ("path", "bundleID", "executable", "teamID", "artifactSHA256", "executableSHA256", "profileSHA256", "expiresAt", "build")
        if any(not isinstance(value.get(field), str) or not value.get(field) for field in fields):
            return None
        if value.get("bundleID") != "com.neven.gofly" or value.get("executable") != "GoFly":
            return None
        if any(re.fullmatch(r"[0-9a-f]{64}", value.get(field, "")) is None for field in ("artifactSHA256", "executableSHA256", "profileSHA256")):
            return None
        return ArtifactIdentity(
            value["path"], value["bundleID"], value["executable"], value["teamID"],
            value["artifactSHA256"], value["executableSHA256"], value["profileSHA256"],
            value["expiresAt"], {}, value["build"],
        )

    @staticmethod
    def _receipt_digest(journal: Mapping[str, Any]) -> str:
        copy_value = copy.deepcopy(dict(journal))
        copy_value.pop("receiptSHA256", None)
        return hashlib.sha256(json.dumps(copy_value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()

    @staticmethod
    def _bind(journal: Mapping[str, Any], request: SetupRequest) -> None:
        if journal.get("setupID") != request.setup_id:
            raise SetupBridgeError("transaction-conflict")
        if journal.get("deviceID") != request.device_id:
            raise SetupBridgeError("identity-mismatch")
        if journal.get("mode", "install") != request.mode:
            raise SetupBridgeError("transaction-conflict")

    @staticmethod
    def _can_resume(journal: Mapping[str, Any]) -> bool:
        if journal.get("delivery", {}).get("state") in {"inflight", "unknown"}:
            return False
        return any(stage["state"] in {"pending", "inflight", "unknown"} for stage in journal["stages"].values())

    @staticmethod
    def _inflight_stage(journal: Mapping[str, Any]) -> str | None:
        order = ("artifact", "install", "complete") if journal.get("mode") == "renew" else (
            "artifact", "pairing", "install", "support", "handoff", "complete"
        )
        for stage in order:
            if journal.get("stages", {}).get(stage, {}).get("state") == "inflight":
                return stage
        return None

    def _resume_artifact(self, journal: dict[str, Any], request: SetupRequest) -> dict[str, Any]:
        intent = journal.get("intent", {})
        source = intent.get("source")
        artifact_path = intent.get("artifactPath")
        team_id = intent.get("teamID")
        if source not in {"project", "signedApp"} or not isinstance(team_id, str):
            raise SetupBridgeError("transaction-unknown")
        options = SetupOptions(source, artifact_path, team_id, intent.get("allowProvisioningUpdates") is True)
        rebound = SetupRequest(request.request_id, "apply", request.setup_id, request.device_id, request.mode, options)
        try:
            observed = self._observe_device(request.device_id)
            journal = self.store.checkpoint(journal, "artifact", "inflight")
            artifact = self._build_or_validate(rebound, observed)
            artifact = snapshot_artifact(
                artifact,
                self.store.transaction_root(request.setup_id) / "artifact" / "GoFly.app",
                self.artifact_validator,
                device_id=request.device_id,
                team_id=artifact.team_id,
            )
            journal["intent"]["artifact"] = self._artifact_dict(artifact)
            journal = self.store.checkpoint(journal, "artifact", "confirmed")
        except SetupBridgeError as error:
            with _suppress_journal_errors():
                journal = self.store.checkpoint(journal, "artifact", "unknown", detail=error.code)
            raise
        return journal

    def _payload(
        self,
        *,
        stage: str,
        outcome: str,
        can_resume: bool,
        artifact: ArtifactIdentity | None = None,
        team_id: str | None = None,
        observed: DeviceObservation | None = None,
    ) -> ProducerPayload:
        return ProducerPayload(
            stage,
            outcome,
            can_resume,
            app=self._app_payload(artifact) if artifact is not None else None,
            team_id=team_id,
            expires_at=artifact.expires_at if artifact is not None else None,
        )

    def _payload_from_journal(
        self,
        journal: Mapping[str, Any],
        *,
        artifact: ArtifactIdentity | None = None,
        can_resume: bool,
        receipt: str | None = None,
    ) -> ProducerPayload:
        stages = journal["stages"]
        proof = journal.get("proof", {})
        mode = journal.get("mode", "install")
        order = ("artifact", "install", "complete") if mode == "renew" else (
            "artifact", "pairing", "install", "support", "handoff", "complete"
        )
        for stage in order:
            state = stages[stage]["state"]
            if state in {"unknown", "inflight"}:
                current = stage
                outcome = "unknown"
                break
            if state != "confirmed":
                current = stage
                outcome = "inProgress"
                break
        else:
            # A crash can occur after the complete stage checkpoint but
            # before the receipt digest write. Keep that state resumable and
            # below the protocol's confirmed-complete boundary.
            receipt_value = journal.get("receiptSHA256")
            proof_complete = (
                proof.get("installationConfirmed") is True
                if mode == "renew"
                else all(proof.get(key) is True for key in (
                    "installationConfirmed", "pairingImported", "supportObserved"
                ))
            ) if isinstance(proof, Mapping) else False
            if proof_complete and isinstance(receipt_value, str) and re.fullmatch(r"[0-9a-f]{64}", receipt_value):
                current = "complete"
                outcome = "confirmed"
            else:
                current = "complete"
                outcome = "unknown"
                can_resume = True
        intent_artifact = journal.get("intent", {}).get("artifact")
        app = self._app_payload_from_dict(intent_artifact) if isinstance(intent_artifact, Mapping) else None
        if journal.get("delivery", {}).get("state") in {"inflight", "unknown"}:
            can_resume = False
        return ProducerPayload(
            current,
            outcome,
            can_resume,
            installation_confirmed=proof.get("installationConfirmed") is True,
            pairing_imported=proof.get("pairingImported") is True,
            support_observed=proof.get("supportObserved") is True,
            app=app,
            team_id=journal.get("intent", {}).get("teamID"),
            expires_at=intent_artifact.get("expiresAt") if isinstance(intent_artifact, Mapping) else None,
            receipt_sha256=receipt or journal.get("receiptSHA256"),
        )

    @staticmethod
    def _app_payload(artifact: ArtifactIdentity) -> dict[str, Any]:
        return {
            "bundleID": artifact.bundle_id,
            "build": artifact.build,
            "profileSHA256": artifact.profile_sha256,
            "executableSHA256": artifact.executable_sha256,
        }

    @staticmethod
    def _app_payload_from_dict(value: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "bundleID": value.get("bundleID"),
            "build": value.get("build"),
            "executableSHA256": value.get("executableSHA256"),
            "profileSHA256": value.get("profileSHA256"),
        }


class _suppress_journal_errors:
    def __enter__(self):
        return self

    def __exit__(self, *_args: Any) -> bool:
        return True
