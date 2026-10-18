"""Private durable setup journal with one authoritative current state file."""

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
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Mapping

try:
    from .setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device
except ImportError:  # script execution from the packaged Setup directory
    from setup_protocol import SetupBridgeError, TARGET_BUNDLE_ID, TARGET_NAME, normalized_device

MAX_JOURNAL_BYTES = 256 * 1024
_UUID_RE = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
    r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\Z"
)
_STAGES = ("artifact", "pairing", "install", "support", "handoff", "complete")
_STATES = frozenset({"pending", "inflight", "confirmed", "unknown", "failed"})
_TEAM_RE = re.compile(r"[A-Z0-9]{10}\Z")
_OS_RE = re.compile(r"(?:26|27)(?:\.\d+){1,2}\Z")
_PRIVATE_DIR_MODE = 0o700
_PRIVATE_FILE_MODE = 0o600


def _validate_private_dir(path: Path) -> None:
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_DIRECTORY", 0)
            | getattr(os, "O_NONBLOCK", 0)
            | getattr(os, "O_CLOEXEC", 0),
        )
        info = os.fstat(fd)
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink < 1
            or stat.S_IMODE(info.st_mode) != _PRIVATE_DIR_MODE
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


def _pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SetupBridgeError("storage-unavailable")
        result[key] = value
    return result


def _validate_setup_id(value: Any) -> str:
    if not isinstance(value, str) or _UUID_RE.fullmatch(value) is None:
        raise SetupBridgeError("storage-unavailable")
    return value.lower()


def _private_root(root: Path) -> None:
    if not root.is_absolute() or root.is_symlink():
        raise SetupBridgeError("storage-unavailable")
    try:
        if not root.exists():
            root.mkdir(parents=True, exist_ok=False, mode=_PRIVATE_DIR_MODE)
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    _validate_private_dir(root)


def _existing_private_root(root: Path) -> None:
    """Validate an existing state root without creating or changing it."""
    if not root.is_absolute() or root.is_symlink():
        raise SetupBridgeError("storage-unavailable")
    try:
        root.lstat()
    except FileNotFoundError:
        return
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    _validate_private_dir(root)


def _regular(path: Path, *, allow_missing: bool = False) -> None:
    fd: int | None = None
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
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != _PRIVATE_FILE_MODE
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


def _json_bytes(value: Mapping[str, Any]) -> bytes:
    try:
        data = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    except (TypeError, ValueError, UnicodeError):
        raise SetupBridgeError("storage-unavailable") from None
    if len(data) > MAX_JOURNAL_BYTES:
        raise SetupBridgeError("storage-unavailable")
    return data


def _read_regular_bytes(path: Path, *, max_bytes: int) -> bytes:
    """Read a journal file through one no-follow descriptor."""
    fd: int | None = None
    try:
        fd = os.open(
            path,
            os.O_RDONLY
            | os.O_NOFOLLOW
            | getattr(os, "O_NONBLOCK", 0)
            | getattr(os, "O_CLOEXEC", 0),
        )
        info = os.fstat(fd)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_uid != os.getuid()
            or info.st_nlink != 1
            or stat.S_IMODE(info.st_mode) != _PRIVATE_FILE_MODE
            or info.st_size < 0
            or info.st_size > max_bytes
        ):
            raise SetupBridgeError("storage-unavailable")
        data = bytearray()
        while len(data) < info.st_size:
            try:
                chunk = os.read(fd, min(1024 * 1024, info.st_size - len(data)))
            except InterruptedError:
                continue
            if not chunk:
                raise SetupBridgeError("storage-unavailable")
            data.extend(chunk)
        try:
            extra = os.read(fd, 1)
        except InterruptedError:
            extra = os.read(fd, 1)
        if extra:
            raise SetupBridgeError("storage-unavailable")
        final = os.fstat(fd)
        if (
            not stat.S_ISREG(final.st_mode)
            or final.st_uid != os.getuid()
            or final.st_nlink != 1
            or stat.S_IMODE(final.st_mode) != _PRIVATE_FILE_MODE
            or final.st_size != info.st_size
        ):
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


def _completed_eligible(journal: Mapping[str, Any], transaction: Path) -> bool:
    """Pure eligibility predicate for replacing one current completed record."""
    try:
        stages = journal["stages"]
        proof = journal["proof"]
        if not all(stages[name]["state"] == "confirmed" for name in _STAGES):
            return False
        if not all(proof[name] is True for name in ("installationConfirmed", "pairingImported", "supportObserved")):
            return False
        if journal.get("delivery", {}).get("state") != "delivered":
            return False
        intent = journal["intent"]
        artifact = intent["artifact"]
        pairing = journal["pairing"]
        ownership = journal["installOwnership"]
        support = journal["support"]
        handoff = journal["handoff"]
        activation = journal["activationReceipt"]
        if not all(isinstance(value, Mapping) for value in (artifact, pairing, ownership, support, handoff, activation)):
            return False
        if ownership != {
            "transactionID": journal["setupID"],
            "bundleID": artifact["bundleID"],
            "build": artifact["build"],
            "artifactSHA256": artifact["artifactSHA256"],
            "executableSHA256": artifact["executableSHA256"],
            "profileSHA256": artifact["profileSHA256"],
        }:
            return False
        candidate = transaction / "pairing.candidate"
        _regular(candidate)
        artifact_path = Path(str(artifact["path"]))
        if artifact_path.is_symlink() or not artifact_path.is_dir():
            return False
        if artifact_path.resolve() != (transaction / "artifact" / "GoFly.app").resolve():
            return False
        formal = handoff.get("formalArtifacts")
        if not isinstance(formal, list) or not formal:
            return False
        if activation.get("setupID") != journal["setupID"] or activation.get("deviceID") != journal["deviceID"]:
            return False
        if activation.get("nonce") != handoff.get("nonce"):
            return False
        if activation.get("rawManifestSHA256") != handoff.get("manifestSHA256"):
            return False
        if activation.get("pairingTransactionID") != intent.get("pairingTransactionID"):
            return False
        if activation.get("pairingSHA256") != pairing.get("sha256"):
            return False
        for key in ("bundleID", "build", "profileSHA256", "executableSHA256", "teamID"):
            if activation.get(key) != artifact.get(key):
                return False
        if activation.get("signingExpiry") != artifact.get("expiresAt"):
            return False
        for key, activation_key in (("osVersion", "deviceOS"), ("method", "method"), ("generationID", "generationID")):
            if activation.get(activation_key) != support.get(key):
                return False
        if activation.get("artifacts") != formal:
            return False
        raw_manifest = handoff.get("rawManifest")
        if not isinstance(raw_manifest, str) or len(raw_manifest.encode("utf-8")) > MAX_JOURNAL_BYTES:
            return False
        if hashlib.sha256(raw_manifest.encode("utf-8")).hexdigest() != handoff.get("manifestSHA256"):
            return False
        receipt = journal.get("receiptSHA256")
        if not isinstance(receipt, str) or re.fullmatch(r"[0-9a-f]{64}", receipt) is None:
            return False
        copy_value = copy.deepcopy(dict(journal))
        copy_value.pop("receiptSHA256", None)
        calculated = hashlib.sha256(json.dumps(copy_value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        return calculated == receipt
    except (KeyError, TypeError, ValueError, OSError, SetupBridgeError):
        return False


@contextlib.contextmanager
def _lock_file(root: Path) -> Iterator[None]:
    _private_root(root)
    path = root / "operation.lock"
    _regular(path, allow_missing=True)
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        os.fchmod(fd, 0o600)
    except OSError:
        raise SetupBridgeError("storage-unavailable") from None
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            if error.errno in {errno.EACCES, errno.EAGAIN}:
                raise SetupBridgeError("busy") from None
            raise SetupBridgeError("storage-unavailable") from None
        yield
    finally:
        with contextlib.suppress(OSError):
            fcntl.flock(fd, fcntl.LOCK_UN)
        with contextlib.suppress(OSError):
            os.close(fd)


@dataclass(frozen=True)
class JournalHeader:
    version: int
    operation: str
    setup_id: str
    device_id: str


class JournalStore:
    """Store the one current setup transaction under a private root.

    ``journal.json`` is the sole authoritative current pointer.  Transaction
    directories contain only derived artifacts and the retained pairing
    candidate; callers must never use them as a replacement pointer.
    """

    def __init__(self, state_root: str | Path):
        self.root = Path(state_root)

    def _ensure_lock_path(self) -> None:
        path = self.lock_path
        _regular(path, allow_missing=True)
        try:
            fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
            os.fchmod(fd, 0o600)
            os.fsync(fd)
            os.close(fd)
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None

    @property
    def journal_path(self) -> Path:
        return self.root / "journal.json"

    @property
    def lock_path(self) -> Path:
        return self.root / "operation.lock"

    def lock(self):
        return _lock_file(self.root)

    def transaction_root(self, setup_id: str) -> Path:
        setup_id = _validate_setup_id(setup_id)
        _private_root(self.root)
        transactions = self.root / "transactions"
        if transactions.exists() and transactions.is_symlink():
            raise SetupBridgeError("storage-unavailable")
        try:
            if not transactions.exists():
                transactions.mkdir(mode=_PRIVATE_DIR_MODE)
            _validate_private_dir(transactions)
            path = transactions / setup_id
            if path.exists() and path.is_symlink():
                raise SetupBridgeError("storage-unavailable")
            if not path.exists():
                path.mkdir(mode=_PRIVATE_DIR_MODE)
            _validate_private_dir(path)
        except SetupBridgeError:
            raise
        except OSError:
            raise SetupBridgeError("storage-unavailable") from None
        return path

    def read(self) -> dict[str, Any] | None:
        _existing_private_root(self.root)
        if not self.root.exists():
            return None
        path = self.journal_path
        _regular(path, allow_missing=True)
        if not path.exists():
            return None
        data = _read_regular_bytes(path, max_bytes=MAX_JOURNAL_BYTES)
        try:
            value = json.loads(
                data.decode("utf-8"),
                object_pairs_hook=_pairs,
                parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            )
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError, SetupBridgeError):
            raise SetupBridgeError("storage-unavailable") from None
        self._validate(value)
        return value

    @staticmethod
    def _validate(value: Any) -> None:
        if not isinstance(value, dict):
            raise SetupBridgeError("storage-unavailable")
        if type(value.get("version")) is not int or value.get("version") != 1:
            raise SetupBridgeError("storage-unavailable")
        if value.get("operation") != "setup":
            raise SetupBridgeError("storage-unavailable")
        setup_id = _validate_setup_id(value.get("setupID"))
        if value.get("setupID") != setup_id:
            raise SetupBridgeError("storage-unavailable")
        device_id = normalized_device(value.get("deviceID"))
        if value.get("deviceID") != device_id:
            raise SetupBridgeError("storage-unavailable")
        intent = value.get("intent")
        stages = value.get("stages")
        proofs = value.get("proof")
        if not isinstance(intent, dict) or not isinstance(stages, dict) or not isinstance(proofs, dict):
            raise SetupBridgeError("storage-unavailable")
        source = intent.get("source")
        artifact_path = intent.get("artifactPath")
        team_id = intent.get("teamID")
        if source not in {"signedApp", "project"} or not isinstance(team_id, str) or _TEAM_RE.fullmatch(team_id) is None:
            raise SetupBridgeError("storage-unavailable")
        if intent.get("targetBundleID") != TARGET_BUNDLE_ID or intent.get("targetName") != TARGET_NAME:
            raise SetupBridgeError("storage-unavailable")
        if type(intent.get("allowProvisioningUpdates")) is not bool:
            raise SetupBridgeError("storage-unavailable")
        if source == "project":
            if artifact_path is not None:
                raise SetupBridgeError("storage-unavailable")
        elif not isinstance(artifact_path, str) or not artifact_path.startswith("/") or not artifact_path.endswith(".app"):
            raise SetupBridgeError("storage-unavailable")
        if source == "signedApp" and intent.get("allowProvisioningUpdates") is not False:
            raise SetupBridgeError("storage-unavailable")
        observation = intent.get("deviceObservation")
        if observation is not None:
            if not isinstance(observation, dict) or set(observation) != {
                "deviceID", "osVersion", "transport", "developerMode", "trust"
            }:
                raise SetupBridgeError("storage-unavailable")
            if (
                observation.get("deviceID") != device_id
                or not isinstance(observation.get("osVersion"), str)
                or _OS_RE.fullmatch(observation.get("osVersion", "")) is None
                or observation.get("transport") != "USB"
                or observation.get("developerMode") is not True
                or observation.get("trust") is not True
            ):
                raise SetupBridgeError("storage-unavailable")
        pairing_transaction = intent.get("pairingTransactionID")
        if not isinstance(pairing_transaction, str) or _UUID_RE.fullmatch(pairing_transaction) is None:
            raise SetupBridgeError("storage-unavailable")
        artifact = intent.get("artifact")
        if artifact is not None:
            if not isinstance(artifact, dict):
                raise SetupBridgeError("storage-unavailable")
            expected_artifact = {"path", "bundleID", "executable", "teamID", "artifactSHA256", "executableSHA256", "profileSHA256", "expiresAt", "build"}
            if set(artifact) != expected_artifact or artifact.get("bundleID") != TARGET_BUNDLE_ID or artifact.get("executable") != TARGET_NAME:
                raise SetupBridgeError("storage-unavailable")
            if artifact.get("teamID") != team_id or any(
                not isinstance(artifact.get(key), str) or not artifact.get(key)
                for key in ("path", "expiresAt", "build")
            ):
                raise SetupBridgeError("storage-unavailable")
            if any(re.fullmatch(r"[0-9a-f]{64}", artifact.get(key, "")) is None for key in ("artifactSHA256", "executableSHA256", "profileSHA256")):
                raise SetupBridgeError("storage-unavailable")
        if set(stages) != set(_STAGES):
            raise SetupBridgeError("storage-unavailable")
        for stage in _STAGES:
            state = stages[stage]
            if not isinstance(state, dict) or state.get("state") not in _STATES:
                raise SetupBridgeError("storage-unavailable")
        if set(proofs) != {"installationConfirmed", "pairingImported", "supportObserved"}:
            raise SetupBridgeError("storage-unavailable")
        if any(type(proofs[key]) is not bool for key in proofs):
            raise SetupBridgeError("storage-unavailable")
        delivery = value.get("delivery")
        if not isinstance(delivery, dict) or delivery.get("state") not in {"notStarted", "inflight", "delivered", "unknown"}:
            raise SetupBridgeError("storage-unavailable")
        handoff = value.get("handoff")
        if handoff is not None:
            if not isinstance(handoff, dict) or not {"nonce", "setupID"}.issubset(handoff):
                raise SetupBridgeError("storage-unavailable")
            if _UUID_RE.fullmatch(str(handoff.get("nonce"))) is None or handoff.get("setupID") != value.get("setupID"):
                raise SetupBridgeError("storage-unavailable")
            manifest_sha = handoff.get("manifestSHA256")
            if manifest_sha is not None and (
                not isinstance(manifest_sha, str) or re.fullmatch(r"[0-9a-f]{64}", manifest_sha) is None
            ):
                raise SetupBridgeError("storage-unavailable")
            raw_manifest = handoff.get("rawManifest")
            if raw_manifest is not None and (
                not isinstance(raw_manifest, str)
                or len(raw_manifest.encode("utf-8")) > MAX_JOURNAL_BYTES
                or manifest_sha != hashlib.sha256(raw_manifest.encode("utf-8")).hexdigest()
            ):
                raise SetupBridgeError("storage-unavailable")
            if (raw_manifest is None) != (manifest_sha is None):
                raise SetupBridgeError("storage-unavailable")
            launched_pid = handoff.get("launchedPID")
            if launched_pid is not None and (type(launched_pid) is not int or launched_pid <= 0):
                raise SetupBridgeError("storage-unavailable")
            formal = handoff.get("formalArtifacts")
            if formal is not None:
                if not isinstance(formal, list) or not formal or len(formal) > 8:
                    raise SetupBridgeError("storage-unavailable")
                seen_names: set[str] = set()
                total = 0
                for item in formal:
                    if not isinstance(item, dict) or set(item) != {"id", "filename", "byteCount", "sha256"}:
                        raise SetupBridgeError("storage-unavailable")
                    item_id = _validate_setup_id(item.get("id"))
                    filename = item.get("filename")
                    if not isinstance(filename, str) or filename in seen_names or "/" in filename or filename.startswith("."):
                        raise SetupBridgeError("storage-unavailable")
                    size = item.get("byteCount")
                    digest = item.get("sha256")
                    if type(size) is not int or size <= 0 or size > MAX_JOURNAL_BYTES or not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                        raise SetupBridgeError("storage-unavailable")
                    total += size
                    if total > MAX_JOURNAL_BYTES:
                        raise SetupBridgeError("storage-unavailable")
                    seen_names.add(filename)
        activation = value.get("activationReceipt")
        if activation is not None:
            expected_activation = {
                "setupID", "nonce", "deviceID", "rawManifestSHA256", "pairingTransactionID", "pairingSHA256",
                "bundleID", "build", "profileSHA256", "executableSHA256", "teamID", "signingExpiry",
                "deviceOS", "method", "generationID", "artifacts",
            }
            if not isinstance(activation, dict) or set(activation) != expected_activation:
                raise SetupBridgeError("storage-unavailable")
            if (
                activation.get("setupID") != value.get("setupID")
                or activation.get("deviceID") != value.get("deviceID")
                or activation.get("bundleID") != TARGET_BUNDLE_ID
                or activation.get("method") not in {"personalized", "cryptex"}
                or not isinstance(activation.get("artifacts"), list)
            ):
                raise SetupBridgeError("storage-unavailable")
            for key in ("rawManifestSHA256", "pairingSHA256", "profileSHA256", "executableSHA256"):
                if not isinstance(activation.get(key), str) or re.fullmatch(r"[0-9a-f]{64}", activation[key]) is None:
                    raise SetupBridgeError("storage-unavailable")
        ownership = value.get("installOwnership")
        if ownership is not None:
            expected_ownership = {
                "transactionID", "bundleID", "build", "artifactSHA256", "executableSHA256", "profileSHA256"
            }
            if not isinstance(ownership, dict) or set(ownership) != expected_ownership:
                raise SetupBridgeError("storage-unavailable")
            if ownership.get("transactionID") != value.get("setupID") or ownership.get("bundleID") != TARGET_BUNDLE_ID:
                raise SetupBridgeError("storage-unavailable")
            for key in ("build", "artifactSHA256", "executableSHA256", "profileSHA256"):
                if not isinstance(ownership.get(key), str) or not ownership.get(key):
                    raise SetupBridgeError("storage-unavailable")
            if any(re.fullmatch(r"[0-9a-f]{64}", ownership[key]) is None for key in ("artifactSHA256", "executableSHA256", "profileSHA256")):
                raise SetupBridgeError("storage-unavailable")

    def create(self, setup_id: str, device_id: str, intent: Mapping[str, Any]) -> dict[str, Any]:
        _private_root(self.root)
        self._ensure_lock_path()
        setup_id = _validate_setup_id(setup_id)
        device_id = normalized_device(device_id)
        if not isinstance(intent, Mapping):
            raise SetupBridgeError("storage-unavailable")
        if self.read() is not None:
            raise SetupBridgeError("transaction-conflict")
        self.transaction_root(setup_id)
        stage = {name: {"state": "pending"} for name in _STAGES}
        intent_value = copy.deepcopy(dict(intent))
        # The pairing transaction is part of immutable intent.  It is created
        # before any pair boundary and survives a reopen, so resume never has
        # to invent a second transaction identity.
        pairing_transaction = intent_value.get("pairingTransactionID")
        if pairing_transaction is None:
            pairing_transaction = str(uuid.uuid4())
            intent_value["pairingTransactionID"] = pairing_transaction
        if not isinstance(pairing_transaction, str) or _UUID_RE.fullmatch(pairing_transaction) is None:
            raise SetupBridgeError("storage-unavailable")
        intent_value["pairingTransactionID"] = pairing_transaction.lower()
        journal: dict[str, Any] = {
            "version": 1,
            "operation": "setup",
            "setupID": setup_id,
            "deviceID": device_id,
            "intent": intent_value,
            "stages": stage,
            "proof": {
                "installationConfirmed": False,
                "pairingImported": False,
                "supportObserved": False,
            },
            "delivery": {"state": "notStarted"},
            "installOwnership": None,
        }
        self._write(journal, require_absent=True)
        return journal

    def update(self, journal: Mapping[str, Any]) -> dict[str, Any]:
        if not isinstance(journal, Mapping):
            raise SetupBridgeError("storage-unavailable")
        value = copy.deepcopy(dict(journal))
        self._validate(value)
        self._write(value, require_absent=False)
        return value

    def checkpoint(
        self,
        journal: Mapping[str, Any],
        stage: str,
        state: str,
        *,
        proof: Mapping[str, bool] | None = None,
        detail: str | None = None,
    ) -> dict[str, Any]:
        if stage not in _STAGES or state not in _STATES:
            raise SetupBridgeError("storage-unavailable")
        value = copy.deepcopy(dict(journal))
        self._validate(value)
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

    def _write(self, value: Mapping[str, Any], *, require_absent: bool) -> None:
        _private_root(self.root)
        self._ensure_lock_path()
        data = _json_bytes(value)
        path = self.journal_path
        if require_absent:
            _regular(path, allow_missing=True)
            if path.exists():
                raise SetupBridgeError("transaction-conflict")
        else:
            _regular(path, allow_missing=True)
        fd: int | None = None
        temporary: Path | None = None
        try:
            fd, name = tempfile.mkstemp(prefix=".journal-", dir=self.root)
            temporary = Path(name)
            os.fchmod(fd, 0o600)
            offset = 0
            while offset < len(data):
                written = os.write(fd, data[offset:])
                if written <= 0:
                    raise OSError("short journal write")
                offset += written
            os.fsync(fd)
            os.close(fd)
            fd = None
            # A symlink appearing after the preflight check is never replaced.
            _regular(path, allow_missing=True)
            if require_absent and path.exists():
                raise SetupBridgeError("transaction-conflict")
            os.replace(temporary, path)
            temporary = None
            try:
                directory_fd = os.open(self.root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                # The replacement happened; durability of the new current
                # pointer is now uncertain and must never be reported as the
                # prior state surviving.
                raise SetupBridgeError("commit-unknown") from None
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

    def header(self) -> JournalHeader | None:
        return self.read_header()

    def read_header(self) -> JournalHeader | None:
        """Read only the frozen continuation header.

        This method deliberately does not authorize status or resume and does
        not validate stage/proof fields.  The producer always calls ``read``
        before deriving any operation state.
        """
        _existing_private_root(self.root)
        if not self.root.exists():
            return None
        path = self.journal_path
        _regular(path, allow_missing=True)
        if not path.exists():
            return None
        try:
            data = _read_regular_bytes(path, max_bytes=MAX_JOURNAL_BYTES)
            if len(data) > MAX_JOURNAL_BYTES:
                raise ValueError()
            value = json.loads(
                data.decode("utf-8"),
                object_pairs_hook=_pairs,
                parse_constant=lambda _value: (_ for _ in ()).throw(ValueError()),
            )
            if not isinstance(value, dict):
                raise ValueError()
            if type(value.get("version")) is not int or value.get("version") != 1:
                raise ValueError()
            if value.get("operation") != "setup" or not isinstance(value.get("operation"), str):
                raise ValueError()
            setup_id = _validate_setup_id(value.get("setupID"))
            device_id = normalized_device(value.get("deviceID"))
            if value.get("setupID") != setup_id or value.get("deviceID") != device_id:
                raise ValueError()
            return JournalHeader(1, "setup", setup_id, device_id)
        except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError, SetupBridgeError):
            raise SetupBridgeError("storage-unavailable") from None

    def reopen_snapshot(self) -> dict[str, Any] | None:
        """Read the authoritative record, mapping inflight to unknown in memory."""

        value = self.read()
        if value is None:
            return None
        snapshot = copy.deepcopy(value)
        for stage in snapshot["stages"].values():
            if stage["state"] == "inflight":
                stage["state"] = "unknown"
        if snapshot["delivery"]["state"] == "inflight":
            snapshot["delivery"]["state"] = "unknown"
        return snapshot

    def _completed_eligible(self, journal: Mapping[str, Any]) -> bool:
        try:
            setup_id = _validate_setup_id(str(journal["setupID"]))
            transaction = self.root / "transactions" / setup_id
            _validate_private_dir(transaction)
        except (KeyError, SetupBridgeError):
            return False
        return _completed_eligible(journal, transaction)

    def archive_completed(self, setup_id: str, device_id: str) -> Path:
        return self._archive_completed(setup_id, device_id, lock_held=False)

    def archive_completed_locked(self, setup_id: str, device_id: str) -> Path:
        """Archive while the caller already owns ``operation.lock``."""
        return self._archive_completed(setup_id, device_id, lock_held=True)

    def _archive_completed(self, setup_id: str, device_id: str, *, lock_held: bool) -> Path:
        """Archive a fully proven current transaction under the same lock.

        The current journal is the only continuation pointer.  We publish a
        durable transaction archive first, then remove that pointer, allowing a
        later explicit setup on another absent device to begin.  Any unresolved
        or receipt-less record stays current and therefore blocks replacement.
        """

        setup_id = _validate_setup_id(setup_id)
        device_id = normalized_device(device_id)
        lock = contextlib.nullcontext() if lock_held else self.lock()
        with lock:
            journal = self.read()
            if journal is None:
                raise SetupBridgeError("transaction-unknown")
            if journal.get("setupID") != setup_id or journal.get("deviceID") != device_id:
                raise SetupBridgeError("transaction-conflict")
            if not self._completed_eligible(journal):
                raise SetupBridgeError("transaction-unknown")
            receipt = journal["receiptSHA256"]
            transaction = self.transaction_root(setup_id)
            archive = transaction / "journal.completed.json"
            _regular(archive, allow_missing=True)
            data = _json_bytes(journal)
            if archive.exists():
                try:
                    if _read_regular_bytes(archive, max_bytes=MAX_JOURNAL_BYTES) != data:
                        raise SetupBridgeError("storage-unavailable")
                except OSError:
                    raise SetupBridgeError("storage-unavailable") from None
            else:
                temporary: Path | None = None
                fd: int | None = None
                try:
                    fd, name = tempfile.mkstemp(prefix=".completed-", dir=transaction)
                    temporary = Path(name)
                    os.fchmod(fd, 0o600)
                    offset = 0
                    while offset < len(data):
                        written = os.write(fd, data[offset:])
                        if written <= 0:
                            raise OSError("short archive write")
                        offset += written
                    os.fsync(fd)
                    os.close(fd)
                    fd = None
                    os.replace(temporary, archive)
                    temporary = None
                    try:
                        directory_fd = os.open(transaction, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                        try:
                            os.fsync(directory_fd)
                        finally:
                            os.close(directory_fd)
                    except OSError:
                        raise SetupBridgeError("commit-unknown") from None
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
            # Only after the archive is durable may the authoritative pointer
            # be removed.  Failure leaves it intact and blocks a new apply.
            _regular(self.journal_path)
            try:
                self.journal_path.unlink()
                directory_fd = os.open(self.root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
                try:
                    os.fsync(directory_fd)
                finally:
                    os.close(directory_fd)
            except OSError:
                # The pointer was removed before the directory flush failed;
                # current/archive state is uncertain and requires readback.
                raise SetupBridgeError("commit-unknown") from None
            return archive
