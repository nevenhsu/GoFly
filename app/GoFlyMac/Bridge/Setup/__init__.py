"""Formal GoFlyMac setup producer package.

The package is imported by the single :mod:`bridge` process boundary. The
remaining modules expose small, injectable seams for the production adapters
and local tests.
"""

from .setup_protocol import (
    MAX_REQUEST_BYTES,
    MAX_RESPONSE_BYTES,
    SetupBridgeError,
    SetupRequest,
    decode_request,
    encode_response,
)

__all__ = [
    "MAX_REQUEST_BYTES",
    "MAX_RESPONSE_BYTES",
    "SetupBridgeError",
    "SetupRequest",
    "decode_request",
    "encode_response",
]
