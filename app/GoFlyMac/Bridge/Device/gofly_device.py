#!/usr/bin/env python3
"""Read-only device boundary for the GoFly macOS bridge.

The protocol-1 checker keeps one narrow seam to the device dependency: this
module.  It pins pymobiledevice3 11.31.0 and exposes only what a read-only
inspection needs: enumerate attached devices and open one lockdown session.
Pairing records, installation and device support stay in the setup bridge setup
bridge, which owns its own candidate records.
"""

from __future__ import annotations

import contextlib
import importlib
import importlib.metadata
import inspect
import os
from pathlib import Path
from typing import Any

PMD3_VERSION = "11.31.0"
USB = "USB"
NETWORK = "Network"
PAIR_TIMEOUT_SECONDS = 60
LABEL = "GoFlyMac Read Only"


class DeviceError(Exception):
    """An error code safe to expose over the bridge boundary."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


_modules: tuple[Any, Any] | None = None


def _load() -> tuple[Any, Any]:
    """Load the pinned usbmux and lockdown modules, never exposing import details."""

    global _modules
    if _modules is not None:
        return _modules
    try:
        version = importlib.metadata.version("pymobiledevice3")
        usbmux = importlib.import_module("pymobiledevice3.usbmux")
        lockdown = importlib.import_module("pymobiledevice3.lockdown")
    except Exception:
        raise DeviceError("runtime-import-unavailable") from None
    if version != PMD3_VERSION:
        raise DeviceError("runtime-version-mismatch")
    _modules = usbmux, lockdown
    return _modules


def _require_parameters(function: Any, names: set[str]) -> None:
    try:
        signature = inspect.signature(function)
    except (TypeError, ValueError):
        raise DeviceError("runtime-api-mismatch") from None
    parameters = signature.parameters
    if any(item.kind is inspect.Parameter.VAR_KEYWORD for item in parameters.values()):
        return
    if not names.issubset(parameters):
        raise DeviceError("runtime-api-mismatch")


def check_compatibility() -> None:
    """Fail closed if the pinned dependency or required API has changed."""

    usbmux, lockdown = _load()
    list_devices = getattr(usbmux, "list_devices", None)
    create = getattr(lockdown, "create_using_usbmux", None)
    if not callable(list_devices) or not callable(create):
        raise DeviceError("runtime-api-mismatch")
    _require_parameters(
        create,
        {
            "serial",
            "label",
            "autopair",
            "connection_type",
            "pair_timeout",
            "pairing_records_cache_folder",
        },
    )


async def list_usb_devices() -> list[Any]:
    """Return the raw usbmux rows for a read-only device listing."""

    usbmux, _ = _load()
    try:
        rows = usbmux.list_devices()
        if inspect.isawaitable(rows):
            rows = await rows
    except DeviceError:
        raise
    except Exception:
        raise DeviceError("usb-device-list-failed") from None
    if not isinstance(rows, list):
        raise DeviceError("runtime-api-mismatch")
    return rows


@contextlib.contextmanager
def _restricted_umask():
    """Keep any transient dependency file private to the current user."""

    previous = os.umask(0o077)
    try:
        yield
    finally:
        os.umask(previous)


async def open_lockdown(serial: str, connection: str, cache: Path, *, autopair: bool = False) -> Any:
    """Open one lockdown session without pairing and without a home cache."""

    _, lockdown = _load()
    create = getattr(lockdown, "create_using_usbmux", None)
    if not callable(create):
        raise DeviceError("runtime-api-mismatch")
    try:
        with _restricted_umask():
            client = create(
                serial=serial,
                connection_type=USB if connection.upper() == USB else NETWORK,
                pairing_records_cache_folder=Path(cache),
                autopair=autopair,
                pair_timeout=PAIR_TIMEOUT_SECONDS,
                label=LABEL,
            )
            if inspect.isawaitable(client):
                client = await client
    except DeviceError:
        raise
    except Exception:
        raise DeviceError("usb-lockdown-failed") from None
    return client
