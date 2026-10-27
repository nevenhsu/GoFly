# GoFly for Mac V1

GoFly for Mac prepares a user's Xcode Team-scoped GoFly iOS build and manages that selected iPhone's install or signing renewal. Mac interface requirements follow Figma `05 · Mac Redesign（新版）`, V1 light and dark sections. The operational contract is [`docs/MAC-INSTALLER-SPEC.md`](../../docs/MAC-INSTALLER-SPEC.md); ticket evidence is in [TRACKER](../../.scratch/gofly-mac-v1/TRACKER.md).

## Obtain and install

No public DMG release is published yet. A local Apple Silicon build can be made from the repository root on a Mac with full Xcode:

```sh
bash app/GoFlyMac/make-dmg.sh <YOUR_XCODE_TEAM_ID>
```

This creates `work/dist/GoFly-<version>-arm64.dmg` and a matching `.sha256` file. Verify the checksum before opening the disk image, then run `bash /Volumes/GoFly/install.sh` in Terminal. The installer asks before replacing an existing `/Applications/GoFly.app`, removes quarantine from the installed app, and opens it. This ad-hoc signed local build is not Developer ID signed or notarized and is not an official release.

The Mac needs a macOS version supported by the installed full Xcode and the iOS platform. Sign in to the user's own Apple Account in Xcode; GoFly does not receive Apple passwords. The first iPhone install requires USB, trust, and Developer Mode.

## V1 behavior

- The app bundles its pinned arm64 CPython runtime, Bridge, iOS project inputs, and native FFI archive. Runtime paths come from `Bundle.main`; persistent GoFly state is stored under `~/Library/Application Support/GoFly/state`.
- First installation is USB-only. Renew supports USB and Wi-Fi; Wi-Fi renewal checks the selected phone's existing pairing and does not create a new pairing.
- Automatic renewal checks at app launch and every 24 hours while the Mac app is open. It runs only when enabled for that device, the observed signing lifetime is below four days, a supported transport and network are available, and no other operation is active. A failed attempt waits until the next 24-hour check.
- An interrupted operation is restarted from a new setup transaction; there is no resume action. Renewal overwrites the same Team-scoped app and preserves its app data.
- Completion requires observed deployment, pairing, device support, and the iPhone activation receipt. Missing evidence remains pending.

## Development and verification

Build a local app bundle without creating a DMG:

```sh
bash app/GoFlyMac/build-app.sh <YOUR_XCODE_TEAM_ID>
open work/gofly-mac/GoFly.app
```

Run the offline suites from the repository root:

```sh
swift test --package-path app/GoFlyMac
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s app/GoFlyMac/Bridge/Setup/Tests -p 'test_*.py'
```

Mac colors live only in [`MacColorSystem.swift`](Sources/GoFlyMac/MacColorSystem.swift). Keep Mac semantic tokens independent from iOS colors. Local UI capture screenshots are under `work/gofly-mac/v1/screens/`; offline tests and capture fixtures do not prove physical-device or clean-Mac behavior.

See [development notes](DEVELOPMENT.md), [Bridge protocol](Bridge/PROTOCOL.md), [release component inventory](../../docs/LICENSING.md), and the [Mac device acceptance list](../../.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md).
