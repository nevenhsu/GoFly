"""One-time incoming pairing-v1 delivery ledger."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable, Mapping

try:
    from .setup_journal import JournalStore
    from .setup_protocol import SetupBridgeError
except ImportError:  # script execution from the packaged Setup directory
    from setup_journal import JournalStore
    from setup_protocol import SetupBridgeError


def deliver_v1_once(
    store: JournalStore,
    journal: Mapping[str, Any],
    *,
    device_id: str,
    setup_id: str,
    deliver: Callable[[str, str], None],
) -> tuple[dict[str, Any], bool]:
    """Deliver the exact pending v1 input at most once.

    The delivery intent is durable before the external write.  A process death
    or adapter error leaves ``unknown`` and therefore forbids a second upload,
    even when the caller presents an identical setup UUID and digest.
    """

    value = dict(journal)
    state = value.get("delivery", {}).get("state", "notStarted")
    if state == "delivered":
        return value, True
    if state in {"inflight", "unknown"}:
        return value, False
    if state != "notStarted":
        raise SetupBridgeError("transaction-unknown")
    value["delivery"] = {"state": "inflight"}
    value = store.update(value)
    try:
        deliver(device_id, setup_id)
    except Exception:
        value["delivery"] = {"state": "unknown"}
        try:
            value = store.update(value)
        except SetupBridgeError:
            pass
        raise SetupBridgeError("transaction-unknown") from None
    value["delivery"] = {"state": "delivered"}
    return store.update(value), True
