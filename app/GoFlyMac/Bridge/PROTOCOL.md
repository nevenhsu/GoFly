# GoFlyMac bridge

One executable, one request, one response. `Bridge/bridge.py` reads one UTF-8
JSON object from stdin (maximum 32 KiB) and writes one compact object to stdout
(maximum 256 KiB). `action` selects the operation; there are no protocol
numbers. Libraries and child processes have their output captured.

Requests carry a UUID `requestID` and an `action`:

- `environment`, `devices`, `inspect`: read-only device checks.
- `preflight`, `apply`, `status`, `resume`: formal setup or renewal.

Setup requests add UUID `setupID`, a `deviceID`, `mode` (`install` or `renew`),
and, for `preflight`/`apply`, an exact `options` object (`teamID`,
`allowProvisioningUpdates`). `inspect` accepts an optional `transport` of `usb`
or `wifi`; no transport is guessed.

Successful responses have `status: "ok"` and a `payload`; failures have
`status: "error"` and a stable `code`. The `requestID` and `action` are echoed.

## Read-only actions

`environment` reports `ready`, safe check rows, and the Xcode Personal Team.
`devices` lists exact usbmux USB and Network observations; duplicate IDs and
transports collapse while both transports remain selectable. `inspect` requires
`deviceID`, pins the selected transport, opens lockdown with `autopair=false`,
and returns identity, OS, developer mode, installed app, LocalDevVPN presence,
and signing evidence that is actually known (otherwise `null`).

## Setup actions

`SetupConfiguration` fixes the workspace, interpreter, project, target and
private state root. `JournalStore` owns `stateRoot/journal.json` and
`operation.lock`; writes use a private temporary file, fsync, and atomic
replacement. Reads never create or repair state.

All setup mutations require the one lease. A proven completed install journal
may be replaced for a later explicit setup on another device; a completed renew
journal may be replaced by the next explicit renew. Unresolved same-device
state remains a conflict.

`mode: "install"` runs `artifact → pairing → install → support → handoff →
complete`; it refuses an already installed app. `mode: "renew"` requires an
installed app (`app-not-installed` otherwise), overwrites the same bundle, and
runs only `artifact → install → complete`. Renew never pairs, installs support,
or hands off; its confirmed payload carries the signed profile's `expiresAt`
(or `null`). An unknown install is never adopted or resubmitted.

`preflight` validates options and device state without writing. `apply` creates
the journal and performs the stages. `status` and `resume` bind the original
setup, device, and mode; an explicit resume may only continue that transaction.
