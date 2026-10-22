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

`environment` reports `ready`, safe check rows, `xcodeVersion`, and every team
from Xcode's `IDEProvisioningTeamByIdentifier` as `teams` entries with
`teamID`, `teamName`, and `isFreeProvisioningTeam`.
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
runs the same full pairing, support and handoff stages as installation, while
overwriting the same bundle without uninstalling or resetting app data. Both
modes require exact App activation proof. New journals freeze `intent.fullSetup`
as true. Historical renew journals without it retain their original three-stage
shape; incomplete historical renews cannot resume writes, and signed-only
completion is not device-ready. An unknown install is never adopted or resubmitted.

Before a subsequent full handoff, only the three fixed control files from the
exact active committed activation may be archived under `GoFlySetup/retired`.
Activation, support generations, pairing receipts and user files are retained.
Pending/foreign controls, staging, an existing archive or an interrupted rename
remain unknown; rollover is never blindly replayed.

`preflight` validates options and device state without writing. `apply` creates
the journal and performs the stages. `status` and `resume` bind the original
setup, device, and mode; an explicit resume may only continue that transaction.
