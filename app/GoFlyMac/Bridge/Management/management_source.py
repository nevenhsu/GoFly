"""Data-only source admission for an installed App's actual activation record.

The device adapter supplies fresh installed build/Team observations. Nothing in
this module opens a connection, creates pairing or authorizes a native action.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Any

from .management_protocol import ManagementBridgeError, TEAM_RE, _parse_object, _uuid, _validate_app

try:
    from ..Setup.setup_adapters import ActivationReceiptObservation, PinnedPymobiledeviceAdapter
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_NAME
except ImportError:  # fixed packaged Bridge root
    from Setup.setup_adapters import ActivationReceiptObservation, PinnedPymobiledeviceAdapter
    from Setup.setup_protocol import SetupBridgeError, TARGET_NAME


MAX_ACTIVATION_BYTES = 256 * 1024
MAX_ACTIVATION_RECEIPTS = 128


@dataclass(frozen=True)
class PreparationAppIdentity:
    """Formal metadata only; deliberately has no install path/archive digest."""

    bundle_id: str
    build: str
    profile_sha256: str
    executable_sha256: str
    team_id: str
    expires_at: str
    executable: str = TARGET_NAME

    @classmethod
    def from_receipt(cls, receipt: ActivationReceiptObservation) -> "PreparationAppIdentity":
        return cls(receipt.bundle_id, receipt.build, receipt.profile_sha256,
                   receipt.executable_sha256, receipt.team_id, receipt.signing_expiry)

    def app(self) -> dict[str, str]:
        return {"bundleID": self.bundle_id, "build": self.build,
                "profileSHA256": self.profile_sha256, "executableSHA256": self.executable_sha256}


@dataclass(frozen=True)
class SourceActivation:
    raw: bytes
    sha256: str
    receipt_count: int
    receipt: ActivationReceiptObservation

    @property
    def identity(self) -> PreparationAppIdentity:
        return PreparationAppIdentity.from_receipt(self.receipt)

    def require_new_receipt_capacity(self) -> None:
        if self.receipt_count >= MAX_ACTIVATION_RECEIPTS:
            raise ManagementBridgeError("receipt-capacity")

    def admission_evidence(self) -> dict[str, Any]:
        return {"activationSHA256": self.sha256, "receiptCount": self.receipt_count,
                "maximumReceipts": MAX_ACTIVATION_RECEIPTS, "sourceSetupID": self.receipt.setup_id,
                "sourceApp": self.identity.app(), "teamID": self.receipt.team_id}


def decode_source_activation(raw: bytes, *, device_id: str,
                             installed_build: str | None,
                             installed_team: str | None) -> SourceActivation:
    """Bind one active receipt using M1's actual closed full-record decoder.

    An unavailable installed Team is actionable, never guessed from a profile.
    This read-only decode does not replace the live PID/source acknowledgement.
    """
    if (not isinstance(installed_build, str) or not installed_build or
            not isinstance(installed_team, str) or TEAM_RE.fullmatch(installed_team) is None):
        raise ManagementBridgeError("identity-unverified")
    try:
        record = _parse_object(raw, limit=MAX_ACTIVATION_BYTES)
        active = _uuid(record.get("activeSetupID"))
        receipts = record.get("receipts")
        if not isinstance(receipts, list) or not 1 <= len(receipts) <= MAX_ACTIVATION_RECEIPTS:
            raise ManagementBridgeError("identity-mismatch")
        matches = [item for item in receipts if isinstance(item, dict) and item.get("setupID") == active]
        if len(matches) != 1:
            raise ManagementBridgeError("identity-mismatch")
        nonce = _uuid(matches[0].get("nonce"))
        receipt = PinnedPymobiledeviceAdapter._decode_activation_receipt(
            raw, device_id=device_id, setup_id=active, nonce=nonce)
    except (SetupBridgeError, ManagementBridgeError, ValueError, TypeError):
        raise ManagementBridgeError("identity-mismatch") from None
    if receipt.build != installed_build or receipt.team_id != installed_team:
        raise ManagementBridgeError("identity-mismatch")
    _validate_app(PreparationAppIdentity.from_receipt(receipt).app(), code="identity-mismatch")
    return SourceActivation(raw, hashlib.sha256(raw).hexdigest(), len(receipts), receipt)
