"""Local M3 backup manager bridge."""

from .catalog import BackupCatalog, BackupManager, BackupProducer, validate_catalog
from .protocol import (
    BackupBridgeError,
    BackupRequest,
    PROTOCOL,
    decode_request,
    encode_response,
    error_response,
)

__all__ = [
    "BackupBridgeError",
    "BackupCatalog",
    "BackupManager",
    "BackupProducer",
    "validate_catalog",
    "BackupRequest",
    "PROTOCOL",
    "decode_request",
    "encode_response",
    "error_response",
]
