# B1/B2 Python handoff

## Contract

The new public process is `app/GoFlyMac/Bridge/Setup/setup_bridge.py`.
Protocol 2 is a strict one-request JSON object (32 KiB maximum) and a bounded
response (256 KiB maximum). Requests use the frozen fields and options from
`m1-api-freeze.md`; duplicate keys, unknown keys, trailing JSON, wrong JSON
types, unsupported actions, and protocol mismatches return fixed safe codes.
The response repeats `protocol`, `requestID`, `operation`, `action`, `setupID`,
and the normalized selected `deviceID`. Successful payloads always carry
`canResume` and the three explicit proof booleans; a confirmed complete
payload carries `canResume=false`.

`JournalStore` writes the one authoritative `stateRoot/journal.json` and uses
`stateRoot/operation.lock` for nonblocking serialization. The exact root
header is `version=1`, `operation="setup"`, `setupID`, and normalized
`deviceID`. Stages are `artifact`, `pairing`, `install`, `support`, `handoff`,
and `complete`, each with an explicit state. `intent` is created before local
build/sign work and retains the formal source/team/target plus verified artifact
digests. No separate active pointer is introduced.

## Test-first evidence

Initial bounded command (before any new module existed):

```text
python3 -m unittest discover -s app/GoFlyMac/Bridge/Setup/Tests -p 'test_setup_b1.py' -v
```

Actual setup RED:

```text
ModuleNotFoundError: No module named 'setup_bridge'
```

After the interfaces compiled, behavioral REDs were an absent lock artifact
and `{}` being classified as `protocol-mismatch`; both were fixed before the
producer slice continued.

Current focused GREEN command:

```text
work/mac-setup-env/bin/python -m unittest discover -s app/GoFlyMac/Bridge/Setup/Tests -p 'test_*.py' -q
```

Current result: 57 tests passed, including the frozen support-worker suite and
the final public resume regressions. The tests use temporary directories, injected
artifact/device seams, and controlled failures. They perform no device listing,
USB pairing, signing, Apple request, support download, mount, AFC, or install.
The regressions include retained async-loop affinity, strict activation receipt
UUID uniqueness, same-device completed-journal replacement refusal, status-mode
read-only behavior, process-group cancellation, one-shot delivery, unknown
install non-adoption, exact readback-before-stop ordering, pending-artifact
rebuild before pairing/install, frozen-device re-observation, private
owner/mode/link checks, bounded remote handle reads, journal growth detection,
formal manifest fixture conformance, exact receipt inventory binding, the
pre-effect frozen-plan journal write, missing-plan resume rejection, atomic
artifact snapshot publication, and query-only delivery-unknown status.

Fresh bounded RED/GREEN evidence is retained at:

```text
/private/tmp/setup-b19-pending-artifact-red.log
/private/tmp/setup-b19-pending-artifact-green.log
/private/tmp/setup-b30-boundary-red.log
/private/tmp/setup-b30-boundary-green.log
/private/tmp/setup-b31-b32-private-red.log
/private/tmp/setup-b31-b32-private-green.log
/private/tmp/setup-b31-candidate-red.log
/private/tmp/setup-b31-candidate-green.log
/private/tmp/setup-b33-remote-red.log
/private/tmp/setup-b33-remote-green.log
/private/tmp/setup-b32-journal-growth-red.log
/private/tmp/setup-b32-journal-growth-green.log
/private/tmp/setup-b35-b38-current.log
/private/tmp/setup-b35-b38-green-final.log
/private/tmp/setup-all-discovery-b35-b38-final.log
/private/tmp/setup-all-discovery-b35-b38-final2.log
/private/tmp/setup-b39-public-red.log
/private/tmp/setup-b39-boundary-red.log
/private/tmp/setup-b39-boundary-green.log
/private/tmp/setup-b37-public-red.log
/private/tmp/setup-b40-public-red.log
/private/tmp/setup-b39-b40-green-final.log
/private/tmp/m1-root-python-integrated53.log
/private/tmp/m1-root-python-integrated57-final.log
/private/tmp/m1-root-python-integrated58-final.log
```

The formal inventory, completed-archive predicate, and final local snapshot/read
hardening were added after the earlier focused run; no pre-fix RED log for
those changes was reconstructed. The B35–B38 focused run was then rerun from
the saved current tree and passed 41 producer/bridge tests; the final discovery
run (latest) passed 57 tests including the frozen support-worker suite.

The handoff plan is now built by the shared pure `FormalSetupInput` builder,
including deterministic UUID5 artifact IDs, exact raw UTF-8 bytes, digest, and
closed inventory. The producer journals that complete plan in the same atomic
handoff-inflight write before any readback or upload effect. Resume requires the
frozen plan byte-for-byte and digest-for-digest; a missing or changed plan is a
transaction-unknown result. The production adapter independently rebuilds and
compares the local validated generation before opening the remote client.
Artifact snapshots copy into a private staged tree, fsync and validate it, then
publish by rename; missing or changed sources and unknown existing destinations
fail closed. Delivery unknown/inflight is query-only and reports
`canResume=false`, while install unknown remains a resumable diagnostic state.

## Unknown and delivery rules

The controlled install failure enters `install=unknown`. Resume performs one
same-device observation, records no ownership, and does not call install,
launch, stop, readback, handoff, or v1 delivery. A matching external app is
diagnostic only. Pairing resume verifies the retained candidate without pair
setup. `deliver_v1_once` records `delivery=inflight` before its external
boundary and leaves `delivery=unknown` after an ambiguous failure; the same
transaction cannot upload a second time. Completion archival requires all
stages, all proofs, delivered v1, durable install ownership, the retained
candidate and immutable artifact, frozen support input hashes, formal manifest
inventory, and a matching activation binding/receipt digest under the global
lock.
The remote-pairing service binds both pair-record reads and writes to the
transaction candidate, including the host identifier needed for pair-verify;
the dependency's global cache is never used as a continuation source. If a
launched ProcessControl PID remains journaled after a crash, resume verifies
and stops that exact live PID before another launch.
The first App bootstrap readback may report an absent or invalid stored pairing;
that identity-only observation does not block a clean install. Pairing proof is
set only by the committed activation receipt after the one v1 delivery and
formal envelope. An invalid nonce, setup ID, device ID, Bundle digest, or build
leaves the PID journaled and never triggers a blind stop.

## Adapter inventory

Production code uses only these fixed dependency surfaces:

- `pymobiledevice3` version `11.31.0`.
- USB `usbmux.list_devices()` and `lockdown.create_using_usbmux` with
  `connection_type="USB"` and `autopair=False`.
- `RemotePairingLockdownService` for explicit pair/verify, with the private
  retained candidate path and same-device reopen.
- `InstallationProxyService.install_from_local(..., developer=True)` and
  `get_apps(bundle_identifiers=["com.neven.gofly"])`.
- HouseArrest vend-container readback uses fixed
  `Library/Application Support/GoFlySetup/readback-request.json` and
  `readback-response.json` paths, with staged write, remote size/hash
  readback, and a single rename.
  The AFC transport itself exposes its pinned mode/size/rename boundaries;
  App ingress sealing owns the final normal-file and nlink checks before any
  response or formal data is accepted, so the producer does not claim AFC
  permission bits that the dependency cannot set.
- Handoff first launches only for nonce-bound Bundle readback, journals the
  returned ProcessControl PID, and re-observes that PID before stopping it.
  Support files are then uploaded and the manifest is published last. A
  second transaction-owned launch must expose the strict `activation.json`
  record and matching committed receipt; the receipt's raw manifest digest,
  App identity, pairing binding, support generation, and closed artifact
  inventory are checked before fresh same-device support observation.
- Formal setup input uses the same VendContainer and publishes the validated
  `generations/<setupID>/DDI` inventory before the fixed `incoming.json`
  manifest. The one-shot v1 envelope is uploaded to the fixed
  `Library/Application Support/LocalGoSetup/incoming.plist` path.
- `ProcessControl` launches `com.neven.gofly` only when no instance is already
  running, retains the returned PID, and rechecks that exact PID by bundle
  identifier before kill/stop.
- `PinnedXcodeProcessAdapter` invokes the fixed `/usr/bin/xcodebuild` project,
  scheme `GoFly`, `Debug`/`iphoneos`, and a transaction-private build output;
  `-allowProvisioningUpdates` is appended only for the explicit true option;
  its build timeout is 900 seconds and maps to the fixed `timeout` safe code.
- `PersonalizedImageMounter.is_image_mounted("Personalized")` and `mount` for
  iOS 26.0–26.3.
- `UserspaceRsdTunnel(serial=..., autopair=False,
  remotepairing_fallback=False)` plus `CryptexdService.copy_installed` and
  `auto_install_ddi` for iOS 26.4+ / 27.
- Apply-only missing asset preparation uses the pinned dependency's
  `fetch_personalized_ddi()` or `fetch_cryptex_ddi()` source, then streams the
  exact closed inventory into the transaction directory with no-follow reads,
  private files, and parent-directory fsync. Query and all tests remain
  download-free.

Cryptex preparation retains the complete fetched BuildManifest layout in a
private restore sibling for `auto_install_ddi`, while the formal handoff uses a
separately validated closed inventory. Cryptex query evidence compares the
actual installed identifier/version exposed by the pinned API with the selected
manifest identity; personalized mounted state remains a boolean same-device
proof and is not presented as an image-byte identity.

Before a support installer boundary, the producer prepares and validates the
transaction-private generation, then journals the method, frozen OS, manifest
digest, and every closed input file size/hash while the support stage is
`inflight`. A later query/resume revalidates those files before accepting the
selected generation. During handoff and resume, support query/install is held
until the current Bundle readback has been validated and its transaction-owned
PID has been stopped; the resumed path preserves the frozen input map and
manifest digest instead of regenerating or adopting a new one. Every support
postcondition is required to be observed and to match the frozen method, OS,
generation, identifier, and version.

The handoff also carries a durable `formalPublished` phase marker initialized
false with the nonce and manifest. Activation receipts are never polled while
that marker is false. A first-launch PID is reconciled by exact Bundle
readback and stopped first; a durable `delivery=notStarted` transaction may
then perform its one frozen-candidate v1 delivery. The marker becomes true
only after the exact formal upload and inventory validation, before the second
launch. Missing markers and ambiguous delivery remain query-only.

The public resume regressions cover first-PID recovery before v1, activation
polling only after `formalPublished`, fresh same-device binding checks before
the first activation-receipt read and before its one recovery launch, rejection
of local support mutation even when the support stage was previously confirmed,
and rejection of observed support missing generation/identifier/version without
a requery or reinstall. The newest boundary regression is included in the
existing public first-PID test, so the full discovery count remains 57 rather
than adding a duplicate fixture.

The formal signed-artifact validator has its own GoFly identity checks. It does
not call or mutate `LocalGo/MacSetup/localgo_setup.validate_profile`, whose
globals are intentionally legacy `com.neven.localgo` / `StikDebug`.

## Known runtime unknowns

No production dependency invocation was run in this handoff. The default
adapter is intentionally lazy until an explicit `apply`/device action. A real
device run still needs Root's bundled helper inventory, a selected USB device,
an actual signed GoFly artifact or fixed project build, support assets fetched
or supplied during apply, and the final App activation receipt before completion
can be reported. The
InstallationProxy success result is the durable install ownership boundary;
exact current Bundle build/profile/executable hashes and the same-device
support observation remain required before stop, staging, activation, or
completion. A missing activation receipt remains `handoff-unknown`; matching
readback metadata cannot stand in for App-owned activation evidence.
If the complete stage is durable but its receipt digest write is interrupted,
status remains unknown/resumable and explicit resume completes that digest
before reporting confirmed completion.

The CLI entry was also exercised through the exact isolated launcher:
`work/mac-setup-env/bin/python -I .../setup_bridge.py --config
.../SetupConfiguration.json`, yielding a bounded `transaction-unknown` status
response with zero stderr and no state-root or lock creation. The configured
project, developer directory, interpreter link, and current-user state root
are fixed by `SetupConfiguration`; status/read paths do not create or chmod
the state root, while apply creates it under the operation lease.
