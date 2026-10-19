# GoFly — In development / 開發中

**English** · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md)

A Mac and iPhone project for researching iOS location simulation, device connections, and native app workflows. The intended setup is: get the Mac app, open GoFly, connect your iPhone by USB, and install the iPhone app from the Mac.

**Status:** no public DMG yet. The Mac app can perform a first USB installation and re-sign the installed app; final iPhone acceptance and the portable DMG are pending. Preview data never proves that a device operation happened.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Development build](#development-build)
- [Research workflow](#research-workflow)
- [AI-assisted installation](#ai-assisted-installation)
- [Troubleshooting](#troubleshooting)
- [Documentation and source layout](#documentation-and-source-layout)
- [License](#license)

## Requirements

| Item | Requirement |
| --- | --- |
| Computer | A Mac running macOS 15 or later. Use a macOS version compatible with your Xcode when building locally. Windows and Linux are outside the current setup. |
| Phone | An iPhone with iOS 26 or later as the current deployment target. This is not a compatibility guarantee for every model or OS version. |
| Cable | A USB data cable for the first installation. Later re-signing also works over Wi-Fi after the device has been verified. |
| Development tools | Xcode with the required iOS SDK and Swift toolchain; the Mac package requires Swift 6.2 or later. |
| Apple account | Your own Apple Account, signed in through Xcode for development signing. A free Personal Team is supported. |
| iPhone settings | Unlock the phone, trust the Mac, and enable [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) for development installation. |
| Connection app | The device channel requires [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044), installed separately on the iPhone. |
| Network | Needed for Apple signing, dependency downloads, maps/search, and any required device preparation downloads. |

GoFly is intended to be free to use. Apple's signing restrictions still apply: free Personal Team provisioning profiles normally expire after seven days and require re-signing. Use the actual verified expiry for your installation. See [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Install

The first installation is performed over USB from the Mac app:

1. Open GoFly and complete its environment check and signing-account setup.
2. Connect your iPhone by USB. Unlock it and complete trust and Developer Mode confirmations on the phone. Select and verify the intended device in GoFly.
3. Start the first installation. The Mac signs and installs the iPhone app, delivers pairing privately, and automatically prepares and verifies any required device support. Existing valid preparation is reused.
4. Wait for **Installation complete**. This requires verified app deployment, pairing import, and necessary device preparation; an installed icon alone is insufficient. You can then disconnect USB.
5. Install and open LocalDevVPN on the iPhone, enable the VPN channel, and open GoFly. The first-run VPN check must pass before continuing.

Selecting a verified device in device management can re-sign the same installed app; manual re-signing remains available. Both preserve app data and are not a reinstall. A public DMG is not available yet; use the development build below.

## Development build

Run from the repository root on a Mac with Xcode configured:

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

This creates a local development app, not a portable DMG. Its generated configuration contains local workspace and Python paths. It has no release signing or notarization. Read-only device checks use the existing `work/mac-setup-env/bin/python` environment; without that environment, you can still view the interface preview. The app does not install dependencies automatically.

## Research workflow

The GoFly design covers selecting locations, routes/GPX, joystick movement, device service preparation, and restoring GPS. Consult the [GoFly app notes](app/GoFly/README.md) and [iOS UI design spec](docs/IOS-UI-DESIGN.md) for requirements.

For a device experiment, record the app version, iPhone model, iOS version, connection method, and observed result. Verify location behavior in Apple Maps and another app, then stop the task, restore GPS, and verify the real location separately. Do not infer successful restoration from an installation or pairing result. Background operation, reconnects, OS updates, and device restarts need their own verification.

Research is the project's primary purpose, not a restriction to noncommercial use under 0BSD. The project does not connect to AnyGo/iToolab services or distribute their code, assets, credentials, or keys.

## AI-assisted installation

Give an AI assistant the [installation runbook](docs/AI-INSTALL.md#english), then use this prompt:

```text
Read README.md and docs/AI-INSTALL.md first. Help me set up GoFly on my Mac
and my iPhone. Check the actual release and current capabilities, identify
the target device, and perform the available setup within my authorization.
If only the preview is available, report that limit. I will handle Apple sign-in,
2FA, trust, Developer Mode, and VPN confirmations. Preserve existing app data.
Verify each result and report completed steps, pending manual steps, and blockers.
```

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| No DMG download | The DMG release is pending. Use the source build; do not substitute a third-party installer. |
| No iPhone detected | Check the USB data cable, unlock/trust state, Xcode device support, and selected device. |
| Install/re-sign button is disabled | Check the environment, selected device, and pending transaction. A preview never performs writes. |
| The iPhone app no longer opens | Check the actual signing expiry and re-sign from the Mac. Developer Mode does not extend signing. |
| LocalDevVPN shows connected but GoFly cannot continue | Verify the actual VPN channel. The design provides connection checks and a channel reset after location sending has stopped. |
| A write operation is interrupted | Inspect the same device and transaction before retrying. Report uncertain results and preserve existing data. |

## Documentation and source layout

| Path | Purpose |
| --- | --- |
| [app/GoFly/README.md](app/GoFly/README.md) | Native iOS app; English, Traditional Chinese, and Simplified Chinese resources. |
| [app/GoFlyMac/README.md](app/GoFlyMac/README.md) | Mac app capabilities and development checks. |
| [app/GoFlyMac/DEVELOPMENT.md](app/GoFlyMac/DEVELOPMENT.md) | Mac installation and device-management requirements. |
| [docs/AI-INSTALL.md](docs/AI-INSTALL.md) | Installation instructions for AI assistants, in all three languages. |
| [docs/LICENSING.md](docs/LICENSING.md) | 0BSD scope, existing upstream licenses, and release conditions. |
| `work/` | Ignored local research evidence, build outputs, and device experiments; not public release content. |

The README is available in English, Traditional Chinese, and Simplified Chinese. App localization targets the same languages, with English fallback; documentation translations do not establish complete UI localization or device verification.

## License

The selected license for newly authored, independently owned material is **0BSD**, permitting free use, modification, and redistribution without attribution. [LICENSE](LICENSE) covers the three root READMEs and the guides under `docs/`. It does not relicense existing app code or dependencies. See the [official 0BSD text](https://opensource.org/license/0bsd).

LocalGo/StikDebug, the reused Mac device boundary, and the new GoFly app's [adapted/native components](app/GoFly/Legal/SOURCES.txt) retain AGPL-3.0 notices. The Mac app uses GPL-3.0 `pymobiledevice3`. A combined app release cannot be described as wholly attribution-free. See [licensing details](docs/LICENSING.md) and [upstream provenance](app/LocalGo/UPSTREAM.md).

The structure follows the project overview, prerequisites, installation, usage, and license sections of [Best-README-Template](https://github.com/othneildrew/Best-README-Template), adapted for this research project.
