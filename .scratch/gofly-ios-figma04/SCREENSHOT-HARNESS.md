# Figma 04 screenshot harness

## Capture App frames

The fixture entry point is available only in Debug iOS Simulator builds. Launch a frame with the exact Figma frame ID and appearance:

```text
-gofly-ui-frame B1 -gofly-ui-appearance dark
```

Each frame launch uses isolated UI-test stores. Pass UUIDs to `-gofly-ui-session-store`, `-gofly-ui-favorites-store`, `-gofly-ui-imports-store`, `-gofly-ui-favorite-routes-store`, and `-gofly-ui-preferences-store` when a repeatable namespace is needed; frame mode otherwise creates a fresh namespace. Fixtures bypass setup activation, real location authorization, the native device service, VPN probing, and live network-path monitoring. Map screens use local deterministic fixtures; production route, annotation, Pin, and position-arrow rendering stays active.

Run the full screenshot matrix on an available iOS Simulator:

```sh
xcodebuild -project app/GoFly/GoFly.xcodeproj \
  -scheme GoFly \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -parallel-testing-enabled NO \
  -only-testing:GoFlyUITests/GoFlyFigmaFrameScreenshots/testCaptureSupportedFigmaFramesInBothAppearances \
  test
```

The current catalog has 64 frame IDs. The test writes 128 App screenshots (Light and Dark) to `work/gofly-ios-figma04/screenshots/<FrameID>-<light|dark>.png`, a `manifest.json` with the Figma node and launch flags, and an `index.html` comparison page with Light/Dark columns and section filtering. The HTML pairs each App screenshot with the matching read-only Figma render. On rerun, prior root-level PNG, JSON, and HTML outputs are copied under `screenshots/previous/<timestamp>/` and removed from the current output before new captures are written.

## Refresh Figma references

`work/gofly-ios-figma04/figma/manifest.json` maps rendered frames and appearances to Figma node IDs. In Figma Console, call `figma_capture_screenshot` for each node with PNG format and scale 1, then save the returned image as `work/gofly-ios-figma04/figma/<FrameID>-<light|dark>.png`. Keep Figma read-only and update the matching manifest entry if node IDs or rendered variants change.

The current reference set contains 128 PNGs captured from the rendered A–F sections on 2026-10-29. The current matrix emits all 64 catalog frames in both appearances; no catalog frame is unavailable to the fixture. R06 has no frame or rendered variant in the current Figma 04 catalog and is not synthesized. The current catalog and read-only render include Dark · B11 at node `322:40470`; this conflicts with the earlier ticket 00 note that Dark is missing, so that note remains recorded in the capture manifest for reconciliation.

## Build isolation and current coverage

`GoFlyUITestOverrides` has an inert variant outside `DEBUG && targetEnvironment(simulator)`. Release and iPhoneOS builds contain no `-gofly-ui-*` launch-argument strings, so those arguments cannot select fixture state. Validate with `bash app/GoFly/scripts/check.sh`; use `bash app/GoFly/scripts/check.sh --device` for NativeBridge verification and an unsigned iPhoneOS build. Neither command installs the App on a device.

The supported frame IDs are listed in `app/GoFly/Resources/Figma04FrameCatalog.json`; `work/gofly-ios-figma04/screenshots/manifest.json` is the source of truth for the last capture run and its Figma gaps.
