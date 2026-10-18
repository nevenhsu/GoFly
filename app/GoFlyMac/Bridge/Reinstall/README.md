# GoFlyMac reinstall protocol boundary

This package contains the protocol-3 request/response codec, fixed-path
configuration reader, durable M2 journal, producer, and explicit device,
process, support, and validator seams. No operation is performed merely by
importing the package; the bridge opens the shared lease only for an explicit
mutating action.

`reinstall_protocol.py` rejects duplicate or unknown keys, nonfinite/floating
numbers, exponent numbers, malformed UUID/device identities, unsafe options,
stale category/count/proof combinations, and unbounded responses. Errors use
only the frozen safe code set and a sanitized envelope.

`reinstall_config.py` composes the existing M1 path and state-root validation.
Read-only validation never creates or repairs anything; `ensure_state_root`
is retained for the later explicit apply boundary and does not perform any
device operation.

The B2 producer uses `reinstall-journal.json` as its one current transaction
record and the existing `operation.lock` shared with `Setup.JournalStore`.
`journal.json` remains the protocol-2 setup record.  Each M2 checkpoint is a
private 0600 atomic file replacement followed by a parent-directory fsync;
status and preflight only read existing state.  A source export is not usable
for removal until the local backup has been copied, reopened and accepted by
the bundled `GoFlyTransferValidator` subprocess.  Lost install results remain
unknown and are never adopted or resubmitted.  The controlled tests exercise
the journal/header, backup-before-uninstall, and receipt-gated completion
seams without enumerating or mutating a device.
