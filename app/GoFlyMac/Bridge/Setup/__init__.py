"""Formal GoFlyMac setup producer package.

The package is deliberately separate from the protocol-1 read-only bridge.
Only :mod:`setup_bridge` is a process boundary; the remaining modules expose
small, injectable seams for the production adapters and local tests.
"""

from .setup_protocol import (
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    PROTOCOL,
    SetupBridgeError,
    SetupRequest,
    decode_request,
    encode_response,
)

__all__ = [
    "MAX_REQUEST_BYTES",
    "MAX_RESPONSE_BYTES",
    "PROTOCOL",
    "SetupBridgeError",
    "SetupRequest",
    "decode_request",
    "encode_response",
]
