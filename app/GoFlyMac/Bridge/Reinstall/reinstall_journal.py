"""Durable, private journal for one protocol-3 reinstall transaction.

The reinstall journal is deliberately separate from the protocol codec.  It is
an on-disk authority and therefore validates its complete shape before a
caller may use any evidence from it.  The operation lock is the same lock
used by the protocol-2 ``JournalStore``; callers must hold it across every
physical operation and journal checkpoint.
"""

from __future__ import annotations

import contextlib
import copy
import errno
import fcntl
import hashlib
import json
import os
import re
import stat
import tempfile
from pathlib import Path
from typing import Any, Iterator, Mapping, Sequence

try:
    from ..Setup.setup_journal import JournalStore, _lock_file
    from ..Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, normalized_device
except ImportError:  # direct execution from the packaged Reinstall directory
    from Setup.setup_journal import JournalStore, _lock_file
    from Setup.setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, normalized_device

from .reinstall_protocol import CATEGORY_ORDER, ReinstallBridgeError

MAX_JOURNAL_BYTES = 2 * 1024 * 1024
MAX_HISTORY = 128
COUNT_LIMITS = {"favorites": 100, "importedRoutes": 100, "favoriteRoutes": 100, "draftNodes": 27, "gpxPoints": 2_010_000}
JOURNAL_NAME = "reinstall-journal.json"
HISTORY_DIRECTORY = "reinstall-history"
TRANSACTION_DIRECTORY = "reinstall-transactions"
PRIVATE_DIRECTORY_MODE = 0o700
PRIVATE_FILE_MODE = 0o600
UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\Z")
HEX64_RE = re.compile(r"[0-9a-f]{64}\Z")

_STAGES = (
    "artifact", "sourceRequest", "sourceReady", "backup", "abandonIntent",
    "destructiveIntent", "sourceSeal", "sourceStop", "uninstall", "install",
    "setup", "restoreDelivery", "restoreReceipt", "finalSupport", "complete", "abandon",
)
_STATES = frozenset({"pending", "inflight", "confirmed", "unknown", "failed"})
_TOP_LEVEL = {
    "version", "operation", "transferID", "deviceID", "dataSetID", "nonce", "setupID",
    "knownSource", "targetArtifact", "sourceApp", "requestSHA256", "rawManifestSHA256",
    "counts", "predecessor", "stages", "commands", "backup", "restoreIntent", "setup",
    "restoreReceipt", "errorCode", "outcome", "history",
    "options",
    "proof",
}
_REQUIRED = {
    "version", "operation", "transferID", "deviceID", "dataSetID", "nonce", "setupID",
    "knownSource", "targetArtifact", "sourceApp", "requestSHA256", "rawManifestSHA256",
    "counts", "predecessor", "stages", "commands", "backup", "restoreIntent", "setup",
    "restoreReceipt", "errorCode", "outcome",
    "options",
    "proof",
}


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SetupBridgeError("storage-unavailable")
        result[key] = value
    return result


def _uuid(value: Any, *, code: str = "storage-unavailable") -> str:
    if not isinstance(value, str) or UUID_RE.fullmatch(value) is None or value != value.lower():
        raise SetupBridgeError(code)
    return value


def _sha(value: Any) -> bool:
    return isinstance(value, str) and HEX64_RE.fullmatch(value) is not None


def _validate_counts(value: Any, *, categories: Sequence[str] | None = None) -> None:
    """Validate the bounded semantic-validator count record.

    Counts are evidence from the actual whole-package validator.  Keeping the
    lexical set and the selected-category zero rules in one helper prevents a
    journal checkpoint from accidentally treating a partial inventory as a
    complete backup proof.
    """
    if not isinstance(value, Mapping) or set(value) != set(COUNT_LIMITS):
        raise SetupBridgeError("storage-unavailable")
    if any(type(value[key]) is not int or value[key] < 0 or value[key] > COUNT_LIMITS[key] for key in value):
        raise SetupBridgeError("storage-unavailable")
    if categories is not None:
        selected = set(categories)
        if "favorites" not in selected and value["favorites"] != 0:
            raise SetupBridgeError("storage-unavailable")
        if "routes" not in selected and any(value[key] != 0 for key in ("importedRoutes", "favoriteRoutes", "draftNodes", "gpxPoints")):
            raise SetupBridgeError("storage-unavailable")


def _private_root(root: Path, *, create: bool) -> None:
    if not root.is_absolute() or root.is_symlink():
        raise SetupBridgeError("storage-unavailable")
    try:
        if create and not root.exists():
            root.mkdir(parents=True, mode=PRIVATE_DIRECTORY_MODE, exist_ok=False)
        if not root.exists():
            return
        fd = os.open(root, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0))
        try:
            info = os.fstat(fd)
        finally:
            os.close(fd)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != PRIVATE_DIRECTORY_MODE:
            raise SetupBridgeError("storage-unavailable")
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None


def _regular(path: Path, *, allow_missing: bool = False, max_bytes: int = MAX_JOURNAL_BYTES) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        if allow_missing:
            return
        raise SetupBridgeError("storage-unavailable") from None
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    if stat.S_ISLNK(info.st_mode):
        raise SetupBridgeError("storage-unavailable")
    fd: int | None = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != PRIVATE_FILE_MODE
            or info.st_size < 0
            or info.st_size > max_bytes
        ):
            raise SetupBridgeError("storage-unavailable")
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _read(path: Path, *, max_bytes: int = MAX_JOURNAL_BYTES) -> bytes:
    _regular(path, max_bytes=max_bytes)
    fd: int | None = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0))
        before = os.fstat(fd)
        data = bytearray()
        while len(data) < before.st_size:
            chunk = os.read(fd, min(1024 * 1024, before.st_size - len(data)))
            if not chunk:
                raise SetupBridgeError("storage-unavailable")
            data.extend(chunk)
        if os.read(fd, 1):
            raise SetupBridgeError("storage-unavailable")
        after = os.fstat(fd)
        if after.st_size != before.st_size or after.st_nlink != 1:
            raise SetupBridgeError("storage-unavailable")
        return bytes(data)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)


def _json(value: Mapping[str, Any]) -> bytes:
    try:
        data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        raise SetupBridgeError("storage-unavailable") from None
    if len(data) > MAX_JOURNAL_BYTES:
        raise SetupBridgeError("storage-unavailable")
    return data


def _fsync_directory(path: Path) -> None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    except OSError:
        raise SetupBridgeError("commit-unknown") from None


def _write_atomic(path: Path, value: Mapping[str, Any], *, require_absent: bool = False) -> None:
    data = _json(value)
    _private_root(path.parent, create=True)
    _regular(path, allow_missing=True)
    if require_absent and path.exists():
        raise SetupBridgeError("transaction-conflict")
    fd: int | None = None
    temporary: Path | None = None
    try:
        fd, name = tempfile.mkstemp(prefix=".reinstall-", dir=path.parent)
        temporary = Path(name)
        os.fchmod(fd, PRIVATE_FILE_MODE)
        offset = 0
        while offset < len(data):
            written = os.write(fd, data[offset:])
            if written <= 0:
                raise OSError("short write")
            offset += written
        os.fsync(fd)
        os.close(fd)
        fd = None
        _regular(path, allow_missing=True)
        if require_absent and path.exists():
            raise SetupBridgeError("transaction-conflict")
        os.replace(temporary, path)
        temporary = None
        _fsync_directory(path.parent)
    except SetupBridgeError:
        raise
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    finally:
        if fd is not None:
            with contextlib.suppress(OSError):
                os.close(fd)
        if temporary is not None:
            with contextlib.suppress(OSError):
                temporary.unlink()


def _validate_optional_identity(value: Any, *, allow_none: bool = True) -> None:
    if value is None and allow_none:
        return
    if not isinstance(value, Mapping):
        raise SetupBridgeError("storage-unavailable")
    allowed = {"bundleID", "build", "profileSHA256", "executableSHA256"}
    if set(value) != allowed or value.get("bundleID") != "com.neven.gofly":
        raise SetupBridgeError("storage-unavailable")
    if not isinstance(value.get("build"), str) or not value["build"] or any(ord(c) < 0x20 for c in value["build"]):
        raise SetupBridgeError("storage-unavailable")
    if not _sha(value.get("profileSHA256")) or not _sha(value.get("executableSHA256")):
        raise SetupBridgeError("storage-unavailable")


def validate_journal(value: Any) -> None:
    """Validate a complete journal before returning it to a producer."""
    if not isinstance(value, Mapping) or set(value) - _TOP_LEVEL or not _REQUIRED.issubset(value):
        raise SetupBridgeError("storage-unavailable")
    if value.get("version") != 1 or value.get("operation") != "reinstall":
        raise SetupBridgeError("storage-unavailable")
    for key in ("transferID", "dataSetID", "nonce", "setupID"):
        _uuid(value.get(key))
    device = normalized_device(value.get("deviceID"))
    if value.get("deviceID") != device:
        raise SetupBridgeError("storage-unavailable")
    source = value.get("knownSource")
    if not isinstance(source, Mapping) or set(source) != {"bundleID", "build"} or source.get("bundleID") != "com.neven.gofly" or not isinstance(source.get("build"), str) or not source["build"]:
        raise SetupBridgeError("storage-unavailable")
    artifact = value.get("targetArtifact")
    if artifact is not None:
        if not isinstance(artifact, Mapping) or set(artifact) != {"path", "bundleID", "build", "teamID", "artifactSHA256", "profileSHA256", "executableSHA256", "expiresAt"}:
            raise SetupBridgeError("storage-unavailable")
        if artifact.get("bundleID") != "com.neven.gofly" or not isinstance(artifact.get("path"), str) or not artifact["path"].startswith("/"):
            raise SetupBridgeError("storage-unavailable")
        if not isinstance(artifact.get("build"), str) or not artifact["build"] or not isinstance(artifact.get("teamID"), str) or not re.fullmatch(r"[A-Z0-9]{10}", artifact["teamID"]):
            raise SetupBridgeError("storage-unavailable")
        if any(not _sha(artifact.get(key)) for key in ("artifactSHA256", "profileSHA256", "executableSHA256")):
            raise SetupBridgeError("storage-unavailable")
        if not isinstance(artifact.get("expiresAt"), str) or not artifact["expiresAt"]:
            raise SetupBridgeError("storage-unavailable")
    _validate_optional_identity(value.get("sourceApp"))
    for key in ("requestSHA256", "rawManifestSHA256"):
        if value.get(key) is not None and not _sha(value[key]):
            raise SetupBridgeError("storage-unavailable")
    counts = value.get("counts")
    if counts is not None:
        _validate_counts(counts, categories=value["options"].get("categories") if isinstance(value.get("options"), Mapping) else None)
    predecessor = value.get("predecessor")
    if predecessor is not None:
        if not isinstance(predecessor, Mapping) or set(predecessor) != {"setupID", "deviceID", "rawJournalSHA256", "archived"} or not isinstance(predecessor.get("archived"), bool) or not _sha(predecessor.get("rawJournalSHA256")):
            raise SetupBridgeError("storage-unavailable")
        _uuid(predecessor.get("setupID"))
        if normalized_device(predecessor.get("deviceID")) != predecessor.get("deviceID"):
            raise SetupBridgeError("storage-unavailable")
    stages = value.get("stages")
    if not isinstance(stages, Mapping) or set(stages) != set(_STAGES):
        raise SetupBridgeError("storage-unavailable")
    for stage in _STAGES:
        item = stages[stage]
        if not isinstance(item, Mapping) or item.get("state") not in _STATES:
            raise SetupBridgeError("storage-unavailable")
        if set(item) - {"state", "detail", "evidence"}:
            raise SetupBridgeError("storage-unavailable")
        if "detail" in item and (not isinstance(item["detail"], str) or len(item["detail"]) > 160):
            raise SetupBridgeError("storage-unavailable")
        if "evidence" in item:
            evidence = item["evidence"]
            if not isinstance(evidence, Mapping) or set(evidence) - {"receipt", "pairingImported", "supportObserved", "observed"}:
                raise SetupBridgeError("storage-unavailable")
            for key in ("pairingImported", "supportObserved", "observed"):
                if key in evidence and type(evidence[key]) is not bool:
                    raise SetupBridgeError("storage-unavailable")
    commands = value.get("commands")
    if not isinstance(commands, Mapping) or set(commands) - {"sourceRequest", "seal", "release"}:
        raise SetupBridgeError("storage-unavailable")
    for slot, command in commands.items():
        if not isinstance(command, Mapping) or set(command) - {"action", "commandID", "controlSHA256", "sourcePID"}:
            raise SetupBridgeError("storage-unavailable")
        if not isinstance(command.get("action"), str) or command.get("action") != {"sourceRequest": "export", "seal": "seal", "release": "release"}.get(slot) or not _sha(command.get("controlSHA256")):
            raise SetupBridgeError("storage-unavailable")
        _uuid(command.get("commandID"))
        if "sourcePID" in command and (type(command["sourcePID"]) is not int or command["sourcePID"] < 0):
            raise SetupBridgeError("storage-unavailable")
    backup = value.get("backup")
    if backup is not None:
        if not isinstance(backup, Mapping) or set(backup) != {"dataSetID", "rawManifestSHA256", "inventory", "counts"} or not _sha(backup.get("rawManifestSHA256")):
            raise SetupBridgeError("storage-unavailable")
        _uuid(backup.get("dataSetID"))
        inventory = backup.get("inventory")
        if not isinstance(inventory, Mapping) or set(inventory) != {"categories"} or not isinstance(inventory["categories"], list) or len(inventory["categories"]) != len(set(inventory["categories"])) or tuple(inventory["categories"]) != tuple(item for item in CATEGORY_ORDER if item in inventory["categories"]):
            raise SetupBridgeError("storage-unavailable")
        if backup.get("dataSetID") != value.get("dataSetID") or backup.get("rawManifestSHA256") != value.get("rawManifestSHA256"):
            raise SetupBridgeError("storage-unavailable")
        _validate_counts(backup.get("counts"), categories=inventory["categories"])
        if value.get("counts") != backup.get("counts"):
            raise SetupBridgeError("storage-unavailable")
    intent = value.get("restoreIntent")
    if intent is not None:
        if not isinstance(intent, Mapping) or set(intent) != {"version", "transferID", "dataSetID", "nonce", "rawManifestSHA256", "sourceDeviceUDID", "destinationDeviceUDID", "sourceApp", "targetApp", "setupID", "categories"} or intent.get("version") != 1:
            raise SetupBridgeError("storage-unavailable")
        for key in ("transferID", "dataSetID", "nonce", "setupID"):
            if intent.get(key) != value.get(key):
                raise SetupBridgeError("storage-unavailable")
        if normalized_device(intent.get("sourceDeviceUDID")) != value.get("deviceID") or normalized_device(intent.get("destinationDeviceUDID")) != value.get("deviceID") or not isinstance(intent.get("categories"), list) or len(intent["categories"]) != len(set(intent["categories"])) or tuple(intent["categories"]) != tuple(item for item in CATEGORY_ORDER if item in intent["categories"]):
            raise SetupBridgeError("storage-unavailable")
        if intent.get("rawManifestSHA256") != value.get("rawManifestSHA256") or intent.get("sourceDeviceUDID") != value.get("deviceID") or intent.get("destinationDeviceUDID") != value.get("deviceID"):
            raise SetupBridgeError("storage-unavailable")
        if not isinstance(intent.get("sourceApp"), Mapping) or not isinstance(intent.get("targetApp"), Mapping):
            raise SetupBridgeError("storage-unavailable")
        _validate_optional_identity(intent["sourceApp"], allow_none=False)
        target = intent["targetApp"]
        if set(target) != {"bundleID", "build", "profileSHA256", "executableSHA256"} or target.get("bundleID") != TARGET_BUNDLE_ID or not isinstance(target.get("build"), str) or not target["build"] or not _sha(target.get("profileSHA256")) or not _sha(target.get("executableSHA256")):
            raise SetupBridgeError("storage-unavailable")
        artifact = value.get("targetArtifact")
        if not isinstance(artifact, Mapping) or any(target.get(key) != artifact.get(key) for key in ("bundleID", "build", "profileSHA256", "executableSHA256")):
            raise SetupBridgeError("storage-unavailable")
    setup = value.get("setup")
    if setup is not None:
        # The M2 parent owns this nested record while the embedded M1 stages
        # run.  Validate it with the exact M1 journal validator rather than
        # reducing it to an identity-shaped success marker; otherwise a
        # producer could claim pairing/support/handoff without retaining the
        # evidence those stages require on resume.
        if not isinstance(setup, Mapping) or setup.get("setupID") != value.get("setupID") or setup.get("deviceID") != value.get("deviceID"):
            raise SetupBridgeError("storage-unavailable")
        try:
            JournalStore._validate(setup)
        except SetupBridgeError:
            raise SetupBridgeError("storage-unavailable") from None
    receipt = value.get("restoreReceipt")
    if receipt is not None:
        if not isinstance(receipt, Mapping) or set(receipt) != {"categories", "receiptSHA256"} or not _sha(receipt.get("receiptSHA256")) or not isinstance(receipt.get("categories"), list):
            raise SetupBridgeError("storage-unavailable")
        for item in receipt["categories"]:
            if not isinstance(item, Mapping) or set(item) != {"category", "state", "receiptSHA256"} or item.get("category") not in CATEGORY_ORDER or item.get("state") != "committed" or not _sha(item.get("receiptSHA256")):
                raise SetupBridgeError("storage-unavailable")
        selected = value["options"].get("categories") if isinstance(value.get("options"), Mapping) else []
        receipt_categories = [item["category"] for item in receipt["categories"]]
        if len(receipt_categories) != len(set(receipt_categories)) or tuple(receipt_categories) != tuple(item for item in CATEGORY_ORDER if item in receipt_categories) or receipt_categories != list(selected):
            raise SetupBridgeError("storage-unavailable")
    if value.get("errorCode") is not None and (not isinstance(value["errorCode"], str) or not re.fullmatch(r"[a-z][a-z0-9-]{1,80}", value["errorCode"])):
        raise SetupBridgeError("storage-unavailable")
    if value.get("outcome") not in {"inProgress", "confirmed", "unknown", "failed"}:
        raise SetupBridgeError("storage-unavailable")
    history = value.get("history", [])
    if not isinstance(history, list) or len(history) > MAX_HISTORY:
        raise SetupBridgeError("storage-unavailable")
    proof = value.get("proof")
    if not isinstance(proof, Mapping) or set(proof) != {"backupValidated", "sourceSealed", "removalConfirmed", "installationConfirmed", "pairingImported", "supportObserved", "restoreCommitted"} or any(type(proof[key]) is not bool for key in proof):
        raise SetupBridgeError("storage-unavailable")
    options = value.get("options")
    if not isinstance(options, Mapping) or set(options) != {"source", "artifactPath", "teamID", "allowProvisioningUpdates", "categories"}:
        raise SetupBridgeError("storage-unavailable")
    if options.get("source") not in {"project", "signedApp"} or not isinstance(options.get("allowProvisioningUpdates"), bool):
        raise SetupBridgeError("storage-unavailable")
    if not isinstance(options.get("teamID"), str) or not re.fullmatch(r"[A-Z0-9]{10}", options["teamID"]):
        raise SetupBridgeError("storage-unavailable")
    if options.get("source") == "project" and options.get("artifactPath") is not None:
        raise SetupBridgeError("storage-unavailable")
    if options.get("source") == "signedApp" and (not isinstance(options.get("artifactPath"), str) or not options["artifactPath"].startswith("/") or options.get("allowProvisioningUpdates") is not False):
        raise SetupBridgeError("storage-unavailable")
    categories = options.get("categories")
    if not isinstance(categories, list) or len(categories) != len(set(categories)) or tuple(categories) != tuple(item for item in CATEGORY_ORDER if item in categories):
        raise SetupBridgeError("storage-unavailable")
    proof_stage = {
        "backupValidated": "backup",
        "sourceSealed": "sourceSeal",
        "removalConfirmed": "uninstall",
        "installationConfirmed": "install",
        "pairingImported": "setup",
        "supportObserved": "finalSupport",
        "restoreCommitted": "restoreReceipt",
    }
    for proof_name, stage_name in proof_stage.items():
        if proof[proof_name] and stages[stage_name]["state"] != "confirmed":
            raise SetupBridgeError("storage-unavailable")
    if stages["sourceRequest"]["state"] == "confirmed" and "sourceRequest" not in commands:
        raise SetupBridgeError("storage-unavailable")
    if stages["sourceReady"]["state"] == "confirmed" and (value.get("sourceApp") is None or not _sha(value.get("rawManifestSHA256"))):
        raise SetupBridgeError("storage-unavailable")
    if stages["backup"]["state"] == "confirmed" and (not isinstance(backup, Mapping) or not proof["backupValidated"]):
        raise SetupBridgeError("storage-unavailable")
    if stages["restoreDelivery"]["state"] == "confirmed" and not isinstance(intent, Mapping):
        raise SetupBridgeError("storage-unavailable")
    if stages["restoreReceipt"]["state"] == "confirmed" and (not isinstance(receipt, Mapping) or not proof["restoreCommitted"]):
        raise SetupBridgeError("storage-unavailable")
    if stages["finalSupport"]["state"] == "confirmed" and (not isinstance(stages["finalSupport"].get("evidence"), Mapping) or stages["finalSupport"]["evidence"].get("pairingImported") is not True or stages["finalSupport"]["evidence"].get("supportObserved") is not True):
        raise SetupBridgeError("storage-unavailable")
    if stages["complete"]["state"] == "confirmed" and (value.get("outcome") != "confirmed" or not all(proof.values())):
        raise SetupBridgeError("storage-unavailable")
    if stages["abandon"]["state"] == "confirmed" and stages["destructiveIntent"]["state"] == "confirmed":
        raise SetupBridgeError("storage-unavailable")


def _new_journal(transfer_id: str, device_id: str, *, data_set_id: str, nonce: str, setup_id: str, known_source: Mapping[str, Any], options: Mapping[str, Any], predecessor: Mapping[str, Any] | None = None) -> dict[str, Any]:
    stages = {name: {"state": "pending"} for name in _STAGES}
    return {
        "version": 1,
        "operation": "reinstall",
        "transferID": transfer_id,
        "deviceID": device_id,
        "dataSetID": data_set_id,
        "nonce": nonce,
        "setupID": setup_id,
        "knownSource": dict(known_source),
        "targetArtifact": None,
        "sourceApp": None,
        "requestSHA256": None,
        "rawManifestSHA256": None,
        "counts": None,
        "proof": {"backupValidated": False, "sourceSealed": False, "removalConfirmed": False, "installationConfirmed": False, "pairingImported": False, "supportObserved": False, "restoreCommitted": False},
        "predecessor": copy.deepcopy(dict(predecessor)) if predecessor is not None else None,
        "stages": stages,
        "commands": {},
        "backup": None,
        "restoreIntent": None,
        "setup": None,
        "restoreReceipt": None,
        "errorCode": None,
        "outcome": "inProgress",
        "history": [],
        "options": dict(options),
    }


class ReinstallJournalStore:
    """Read, validate and atomically checkpoint the current M2 journal."""

    def __init__(self, state_root: str | Path):
        self.root = Path(state_root)

    @property
    def journal_path(self) -> Path:
        return self.root / JOURNAL_NAME

    @property
    def lock_path(self) -> Path:
        return self.root / "operation.lock"

    def lock(self):
        # This is the same implementation and path as M1's JournalStore.
        return _lock_file(self.root)

    def _ensure_lock_path(self) -> None:
        _private_root(self.root, create=True)
        _regular(self.lock_path, allow_missing=True)
        try:
            fd = os.open(self.lock_path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, PRIVATE_FILE_MODE)
            try:
                os.fchmod(fd, PRIVATE_FILE_MODE)
                os.fsync(fd)
            finally:
                os.close(fd)
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None

    def read(self) -> dict[str, Any] | None:
        _private_root(self.root, create=False)
        if not self.root.exists() or not self.journal_path.exists():
            return None
        raw = _read(self.journal_path)
        try:
            value = json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs, parse_constant=lambda _: (_ for _ in ()).throw(ValueError()), parse_float=lambda _: (_ for _ in ()).throw(ValueError()))
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError, SetupBridgeError):
            raise SetupBridgeError("storage-unavailable") from None
        validate_journal(value)
        return copy.deepcopy(dict(value))

    def read_header(self, transfer_id: str | None = None, device_id: str | None = None) -> dict[str, Any] | None:
        value = self.read()
        if value is None:
            return None
        # This is the interoperability fixture consumed by the Swift Mac
        # continuation reader.  It deliberately exposes identity and frozen
        # selection only; proof/stage fields are never promoted from a header.
        header: dict[str, Any] = {
            "version": value["version"],
            "operation": value["operation"],
            "transferID": value["transferID"],
            "deviceID": value["deviceID"],
            "options": {"categories": list(value["options"]["categories"])},
        }
        if transfer_id is not None and header["transferID"] != transfer_id:
            raise SetupBridgeError("transaction-conflict")
        if device_id is not None and header["deviceID"] != device_id:
            raise SetupBridgeError("transaction-conflict")
        return header

    def create(self, transfer_id: str, device_id: str, *, data_set_id: str, nonce: str, setup_id: str, known_source: Mapping[str, Any], options: Mapping[str, Any], predecessor: Mapping[str, Any] | None = None) -> dict[str, Any]:
        _private_root(self.root, create=True)
        self._ensure_lock_path()
        _uuid(transfer_id)
        device_id = normalized_device(device_id)
        for value in (data_set_id, nonce, setup_id):
            _uuid(value)
        if self.read() is not None:
            raise SetupBridgeError("transaction-conflict")
        transactions = self.root / TRANSACTION_DIRECTORY
        _private_root(transactions, create=True)
        transaction = transactions / transfer_id
        _private_root(transaction, create=True)
        backup = transaction / "backup"
        _private_root(backup, create=True)
        journal = _new_journal(transfer_id, device_id, data_set_id=data_set_id, nonce=nonce, setup_id=setup_id, known_source=known_source, options=options, predecessor=predecessor)
        validate_journal(journal)
        _write_atomic(self.journal_path, journal, require_absent=True)
        return copy.deepcopy(journal)

    def update(self, journal: Mapping[str, Any]) -> dict[str, Any]:
        value = copy.deepcopy(dict(journal))
        validate_journal(value)
        _write_atomic(self.journal_path, value)
        return value

    def checkpoint(self, journal: Mapping[str, Any], stage: str, state: str, *, detail: str | None = None, evidence: Mapping[str, Any] | None = None) -> dict[str, Any]:
        if stage not in _STAGES or state not in _STATES:
            raise SetupBridgeError("storage-unavailable")
        value = copy.deepcopy(dict(journal))
        validate_journal(value)
        item: dict[str, Any] = {"state": state}
        if detail is not None:
            item["detail"] = str(detail)[:160]
        if evidence is not None:
            item["evidence"] = copy.deepcopy(dict(evidence))
        value["stages"][stage] = item
        return self.update(value)

    def transaction_root(self, transfer_id: str) -> Path:
        _uuid(transfer_id)
        _private_root(self.root, create=True)
        parent = self.root / TRANSACTION_DIRECTORY
        _private_root(parent, create=True)
        child = parent / transfer_id
        _private_root(child, create=True)
        return child

    def history_path(self, transfer_id: str) -> Path:
        _uuid(transfer_id)
        return self.root / HISTORY_DIRECTORY / f"{transfer_id}.json"

    def archive_completed(self, journal: Mapping[str, Any]) -> Path:
        value = copy.deepcopy(dict(journal))
        validate_journal(value)
        terminal = value["outcome"] == "confirmed" and (
            value["stages"]["complete"]["state"] == "confirmed"
            or value["stages"]["abandon"]["state"] == "confirmed"
        )
        if not terminal:
            raise SetupBridgeError("transaction-unknown")
        parent = self.root / HISTORY_DIRECTORY
        _private_root(parent, create=True)
        try:
            history_files = list(parent.glob("*.json"))
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        for history_file in history_files:
            _regular(history_file)
        if len(history_files) >= MAX_HISTORY:
            raise SetupBridgeError("transaction-conflict")
        destination = self.history_path(value["transferID"])
        _write_atomic(destination, value, require_absent=True)
        _regular(self.journal_path)
        try:
            self.journal_path.unlink()
            _fsync_directory(self.root)
        except OSError:
            raise SetupBridgeError("commit-unknown") from None
        return destination


__all__ = ["MAX_HISTORY", "MAX_JOURNAL_BYTES", "ReinstallJournalStore", "validate_journal"]
