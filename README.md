# GoFly — In development / 開發中

**English** · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

A Mac and iPhone project for researching iOS location simulation, device connections, and native app workflows. The intended setup is: download the Mac DMG, open GoFly, connect your iPhone by USB, and install the iPhone app from the Mac.

**Development status — 2026-10-17:** a downloadable DMG and the complete GoFly installation flow are not available yet. The current Mac app provides read-only checks and workflow previews. The new iOS app is under development; LocalGo is an earlier research prototype. Its device experiments do not establish GoFly release readiness.

## Contents

- [Requirements](#requirements)
- [Download and install](#download-and-install)
- [Try the current development version](#try-the-current-development-version)
- [Research workflow](#research-workflow)
- [AI-assisted installation](#ai-assisted-installation)
- [Troubleshooting](#troubleshooting)
- [Documentation and source layout](#documentation-and-source-layout)
- [License](#license)

## Requirements

| Item | Requirement |
| --- | --- |
| Computer | A Mac. The current Mac app targets macOS 15 or later; use a macOS version compatible with your Xcode when building locally. Windows and Linux are outside the current setup. |
| Phone | An iPhone with iOS 26 or later as the current deployment target. Earlier prototype research used an iPhone 15 with iOS 27; this is not a compatibility guarantee for every model or OS version. |
| Cable | A USB data cable for the first installation. Wi-Fi device management is a later GoFly requirement. |
| Development tools | Xcode with the required iOS SDK and Swift toolchain; the Mac package requires Swift 6.2 or later. Current prototype build records use Xcode 27. |
| Apple account | Your own Apple Account, signed in through Xcode for development signing. A free Personal Team is supported by the earlier LocalGo setup tool. |
| iPhone settings | Unlock the phone, trust the Mac, and enable [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) for development installation. |
| Connection app | The current device-channel approach requires [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), installed separately on the iPhone. |
| Network | Needed for Apple signing, dependency downloads, maps/search, and any required device preparation downloads. |

GoFly is intended to be free to use. Apple's signing restrictions still apply: free Personal Team provisioning profiles normally expire after seven days and require rebuilding/reinstallation. Use the actual verified expiry for your installation. See [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account). Free use does not mean permanent signing.

## Download and install

**Planned release workflow — not executable with the current Mac preview.** There is no verified public download URL in this repository yet. Use the current development path below until a release is published.

1. Download the GoFly `.dmg` from the project's published release page. Check the version, supported Mac architecture, macOS requirements, and published checksum.
2. Open the DMG, copy `GoFly.app` to Applications, and launch it. Follow the app's environment check and signing-account setup.
3. Connect your iPhone by USB. Unlock it and complete trust and Developer Mode confirmations on the phone. Select and verify the intended device in GoFly.
4. Start the first installation. The Mac signs and installs the iPhone app, delivers pairing privately, and automatically prepares and verifies any required device support. Existing valid preparation is reused. Progress uses **Prepare device**; there is no separate iPhone support-data download or setup page.
5. Wait for **Installation complete**. This requires verified app deployment, pairing import, and necessary device preparation; a completed download or an installed icon alone is insufficient. You can then disconnect USB.
6. Install/open LocalDevVPN on the iPhone, enable the VPN channel, and open GoFly. The first-run VPN check must pass before continuing. Starting the service prepares it without moving the location; a separate location action starts simulation.

Planned device management automatically re-signs GoFly after you select and successfully connect to a verified device over USB or Wi-Fi. Manual re-signing remains available and must preserve app data. These capabilities still require implementation and device verification; see the [Mac development specification](app/GoFlyMac/DEVELOPMENT.md).

## Try the current development version

Run from the repository root on a Mac with Xcode configured:

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

This creates a local development app, not a portable DMG. Its generated configuration contains local workspace and Python paths. It has no release signing or notarization. Read-only device checks use the existing `work/mac-setup-env/bin/python` environment; without that environment, you can still view the interface preview. The app does not install dependencies automatically.

The development Mac GUI implements formal GoFly USB first installation, selected-data same-device reinstallation, and local backup management. These flows have local/controlled-boundary checks; final iPhone acceptance is deferred. Re-signing, pairing repair, Wi-Fi writes, and the portable DMG remain in development. Preview success uses sample data and does not prove a device operation happened.

For a separate **LocalGo prototype** experiment, follow the [Mac setup CLI guide](app/LocalGo/MacSetup/README.md). That tool can perform real USB signing/installation when explicitly executed. It targets `com.neven.localgo`, not the new GoFly app (`com.neven.gofly`). The prototype still prepares/downloads device support on the phone and therefore does not meet the planned GoFly installation-completion requirement.

## Research workflow

The GoFly design covers selecting locations, routes/GPX, joystick movement, device service preparation, and restoring GPS. Consult the [product specification](app/LocalGo/PRODUCT-SPEC.md) for requirements and implementation status.

For a device experiment, record the app version, iPhone model, iOS version, connection method, and observed result. Verify location behavior in Apple Maps and another app, then stop the task, restore GPS, and verify the real location separately. Do not infer successful restoration from an installation or pairing result. Background operation, reconnects, OS updates, and device restarts need their own verification.

Research is the project's primary purpose, not a restriction to noncommercial use under 0BSD. The project does not connect to AnyGo/iToolab services or distribute their code, assets, credentials, or keys.

## AI-assisted installation

Give an AI assistant the [installation runbook](docs/AI-INSTALL.md#english), then use this prompt:

```text
Read README.md and docs/AI-INSTALL.md first. Help me set up GoFly on my Mac
and my iPhone. Check the actual release and current capabilities, identify
the target device, and perform the available setup within my authorization.
If only the preview is available, report that limit. Use the LocalGo prototype
only if I explicitly choose that experiment. I will handle Apple sign-in,
2FA, trust, Developer Mode, and VPN confirmations. Preserve existing app data.
Verify each result and report completed steps, pending manual steps, and blockers.
```

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| No DMG download | The DMG release is pending. Use the source preview; do not substitute a third-party installer. |
| No iPhone detected | Check the USB data cable, unlock/trust state, Xcode device support, and selected device. |
| Install/re-sign button is disabled | Check the environment, selected device, and pending transaction. Re-signing is still in development; previews do not perform writes. |
| The iPhone app no longer opens | Check the actual signing expiry and return to the applicable Mac signing workflow. Developer Mode does not extend signing. |
| LocalDevVPN shows connected but GoFly cannot continue | Verify the actual VPN channel. The design provides connection checks and a channel reset after location sending has stopped; the connected label alone is not proof. |
| A write operation is interrupted | Inspect the same device and transaction before retrying. Report uncertain results and preserve existing data. |

## Documentation and source layout

| Path | Purpose |
| --- | --- |
| [app/GoFly/README.md](app/GoFly/README.md) | New native iOS app under development; English, Traditional Chinese, and Simplified Chinese resources. |
| [app/GoFlyMac/README.md](app/GoFlyMac/README.md) | Current Mac app capabilities and development checks. |
| [app/GoFlyMac/DEVELOPMENT.md](app/GoFlyMac/DEVELOPMENT.md) | Confirmed Mac installation and device-management requirements. |
| [app/LocalGo/README.md](app/LocalGo/README.md) | Earlier iOS prototype, design history, and research context. |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | Installation instructions for AI assistants, in all three languages. |
| [docs/LICENSING.md](docs/LICENSING.md) | 0BSD scope, existing upstream licenses, and release conditions. |
| `work/` | Ignored local research evidence, build outputs, and device experiments; not public release content. |

The README is available in English, Traditional Chinese, and Simplified Chinese. App localization targets the same languages, with English fallback; documentation translations do not establish complete UI localization or device verification.

## License

The selected license for newly authored, independently owned material is **0BSD**, permitting free use, modification, and redistribution without attribution. In this documentation change, [LICENSE](LICENSE) covers the three root READMEs and the two new guides under `docs/`. It does not relicense existing app code or dependencies. See the [official 0BSD text](https://opensource.org/license/0bsd).

LocalGo/StikDebug, the reused Mac device boundary, and the new GoFly app's [adapted/native components](app/GoFly/Legal/SOURCES.txt) retain AGPL-3.0 notices. The Mac prototype uses GPL-3.0 `pymobiledevice3`, and the bundled Noto Sans TC font retains OFL-1.1. A combined app release cannot be described as wholly attribution-free. See [licensing details](docs/LICENSING.md) and [upstream provenance](app/LocalGo/UPSTREAM.md).

The structure follows the project overview, prerequisites, installation, usage, and license sections of [Best-README-Template](https://github.com/othneildrew/Best-README-Template), adapted for this research project.
