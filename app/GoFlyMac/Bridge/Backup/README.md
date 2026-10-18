# GoFly local backup bridge

This package implements the approved M3 local backup manager.  It reads only
the validated M2 `reinstall-journal.json` and bounded files in
`reinstall-history/`; a backup package is always derived from
`reinstall-transactions/<transferID>/backup`.

The bridge accepts one protocol-4 JSON request on stdin and emits one bounded
JSON response.  `list` is read-only.  `maintain` records a first observed
completion, retains the copy for seven days, and performs due cleanup.  A
`delete` request requires `confirmed: true` and reopens the complete source
binding before persisting a deletion intent.

Deletion uses retained no-follow directory descriptors and `unlinkat`/`rmdir`
style operations.  The original `manifest.json` remains until every payload
file and directory has been removed and fsynced.  A durable catalog intent
allows a later maintenance run to resume the same deletion; it never adopts a
different journal or manifest generation.

The manifest grammar is reused through the existing pure M2 adapter helper via
`object.__new__`; no device adapter is instantiated and no device operation is
performed by this package.
