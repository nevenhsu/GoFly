# GoFlyMac protocol 2 setup producer

This directory is the formal first install producer boundary. It is separate
from `Bridge/bridge.py` and the protocol 1 LocalGo helpers.

`setup_bridge.py` accepts one strict JSON request from stdin and emits one
bounded response. The frozen request fields are `protocol`, `requestID`,
`operation`, `action`, `setupID`, `deviceID`, and, for `preflight`/`apply`, an
exact `options` object. `SetupConfiguration` accepts only the seven frozen
configuration keys and enforces `com.neven.gofly` / `GoFly`.

`JournalStore` owns the single `stateRoot/journal.json` state record and
`operation.lock`. The root header is always:

```json
{"version":1,"operation":"setup","setupID":"...","deviceID":"..."}
```

Writes use a private temporary file, file fsync, atomic replacement, and
parent-directory fsync. An inflight install is unknown after reopen. A
successful InstallationProxy result is recorded as transaction ownership in
the same journal checkpoint; later App readback proves the exact current
Bundle identity separately. A lost install result remains unknown forever: the
producer may observe a matching installed App for diagnostics but never adopts,
launches, stops, hands off, or resubmits it.

Status and header reads are read-only: they reject an unsafe or missing root
without creating directories or changing permissions. Apply is the only path
that prepares the fixed current-user private state root; transaction mutations
then require its one operation lease. A proven completed journal can be archived only under
that same lease before a later explicit setup on a different selected device;
unresolved or same-device state remains a conflict.

The production seams are `DeviceAdapter`, `ProcessAdapter`, `SupportAdapter`,
`FormalArtifactValidator`, `PinnedPymobiledeviceAdapter`, and
`PinnedSupportAdapter`. Tests inject controlled implementations; importing this
package does not enumerate a device, open Lockdown, create an RSD tunnel, call
Xcode, invoke Apple services, mount support, or install an App.

The pinned device adapter keeps USB enumeration and Lockdown inspection
read-only until an explicit producer action. Pairing uses the retained private
candidate and same-device no-autopair verification; resume only verifies that
candidate. App handoff uses fixed HouseArrest VendContainer paths under
`Library/Application Support/GoFlySetup`; support files are streamed and
verified before the manifest is published last, and the readback request is
staged, remotely read back, and renamed once. The response is strictly decoded
against the setup UUID, nonce, device, App identity, and stored pairing digest.
The AFC dependency does not provide chmod controls for these operations; the
App ingress sealing boundary owns its final normal-file and nlink checks before
accepting response or formal data.

Handoff uses two transaction-owned launches. The first launch must return an
exact nonce-bound Bundle readback, then its returned ProcessControl PID is
journaled and re-observed before termination. Only after that process stops are
support files uploaded and the formal manifest published last. A second launch
must return the exact committed App `activation.json` receipt, including the
raw manifest digest, App identity, pairing binding, support method/generation,
and closed artifact inventory. Readback metadata without this committed
receipt never confirms handoff or completion. Resume consumes an already
committed matching receipt without re-delivering pairing-v1.
The first readback accepts only the closed absent/invalid/verified pairing
observation forms and does not require a pairing hash before the first install;
the activation receipt is the sole final pairing proof. All receipt setup IDs
and nonces are unique, and the active setup occurs exactly once. An exact
current Bundle nonce/device/build/hash mismatch leaves the PID journaled for
safe re-observation instead of allowing a blind stop.

The pinned support adapter uses USB Lockdown with `autopair=False` and the
11.31.0 dependency. Cryptex support constructs one
`UserspaceRsdTunnel(serial=<selected>, autopair=False,
remotepairing_fallback=False)` handle, verifies the returned RSD identity, and
keeps that handle through query/install/query before closing it. Personalized
support is query-first through `PersonalizedImageMounter`.
Support generations accept only the closed frozen filename inventory and verify
`MountMethod` content, bounded files, and streaming hashes before use.
Cryptex install keeps the complete manifest `Info.Path` layout in a private
restore copy for the pinned `auto_install_ddi` API and separately validates the
formal normalized inventory. The selected cryptex identifier/version is
required to match the actual installed service observation exactly. A missing
selected version or a different installed DDI fails closed; this flow does not
automatically unmount or replace an unknown installed generation.

`setup_delivery.deliver_v1_once` journals the one-time incoming pairing-v1
delivery intent before calling the adapter. `inflight` or `unknown` delivery
states never call the adapter again.

The CLI calls `establish_process_group()` before request work and fails closed
if it cannot own its process group; the fixed `python -I` entry restores only
the trusted Setup sibling directory for imports. The unittest runner is
unchanged. A completed journal can be explicitly archived under the same
global lock; unresolved state always remains the authoritative blocker.
Production async calls share one operation-owned event loop for the lifetime of
the device services, which is closed after the request returns.

Before the first launch, the journal atomically freezes the original formal
manifest bytes, digest and closed artifact inventory. `formalPublished` starts
false and becomes true only after the same remote bytes have been verified;
activation polling and the second launch require that durable phase. Every
reconnect, receipt read and launch still checks the selected device, dotted OS
version, Developer Mode and trust at its actual boundary. An ambiguous one-time
v1 delivery is query-only and cannot be resumed by sending another input.
