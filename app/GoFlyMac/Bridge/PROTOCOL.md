# GoFlyMac bridge protocol

The bridge is a one-shot executable. It reads one UTF-8 JSON object from
stdin (maximum 32 KiB), performs one read-only operation, and writes one
compact UTF-8 JSON object to stdout (maximum 256 KiB). Libraries and child
processes have their output captured; stdout is reserved for the response.

Every request has `protocol: 1`, a UUID `requestID`, and an `action` of
`environment`, `devices`, `inspect`, or `install`. The install action is kept
for forward protocol compatibility and always returns `read-only-mode` before
loading a mutating helper. No signing, pairing, installation, repair, or
renewal is performed by this version.

Successful responses have `status: "ok"` and a `payload`; failures have
`status: "error"` and a stable `code`. The request ID is echoed when it was
syntactically available.

The error code set accepted by the Swift client is: `invalid-request`,
`protocol-mismatch`, `read-only-mode`, `environment-not-ready`,
`device-disconnected`, `trust-required`, `developer-mode-required`,
`unsupported-os`, `identity-mismatch`, `signing-required`,
`operation-failed`, `busy`, `usb-lockdown-failed`, `usb-device-not-found`,
`device-identity-mismatch`, `unsupported-os-version`, `runtime-unavailable`,
`dependency-mismatch`, `device-values-unavailable`, `runtime-api-mismatch`,
`timeout`, and `configuration-invalid`.

`environment` reports `ready`, safe check rows (`id`, `title`, `detail`, and
`passed`), and the independently detected Xcode Personal Team (`teamID`, or
`null`). A missing Personal Team does not make read-only management
unavailable.

`devices` lists exact usbmux USB and Network observations. Device IDs are
normalized to lowercase; duplicate observations of the same ID and transport
collapse, while USB and Network choices remain available independently. The
GUI shows one row per phone, defaults to USB and offers an explicit connection
picker when both are observed. Unknown names are an
empty string and unknown OS versions are `null`; no online devices are
invented.

`inspect` requires `deviceID` and accepts an optional `transport` of `usb` or
`wifi`. The GUI always pins its selected transport; an unavailable requested
transport fails instead of falling back. Older requests without `transport`
retain USB preference. It selects the exact observed transport and
opens lockdown with `autopair=false` and a private temporary cache. Identity,
OS version, and developer mode are checked. Installed LocalGo metadata is
looked up through InstallationProxy when available. Signing evidence,
LocalDevVPN's bundle ID, and expiry are not guessed, so the corresponding
fields remain `null` when unavailable; an unsupported developer-mode key also
remains `null`. Capability fields are always `false` in this read-only build.
The GUI creates a fresh selection identity only from an explicit user selection;
discovery, refresh and repeated inspection do not create another selection.
Protocol 5 independently authenticates the selected connection before renewal.
