# Figma 04 screenshot harness

## Run the simulator screenshots

Build and launch a supported frame directly with these Debug Simulator arguments:

```text
-gofly-ui-frame B1 -gofly-ui-appearance dark
```

`-gofly-ui-frame` accepts the exact frame ID. Each frame launch uses isolated UI-test stores; pass `-gofly-ui-session-store`, `-gofly-ui-favorites-store`, `-gofly-ui-imports-store`, `-gofly-ui-favorite-routes-store`, and `-gofly-ui-preferences-store` UUIDs when a repeatable namespace is useful. Without an explicit namespace, frame mode creates a fresh one. The frame path bypasses setup activation, real location authorization, the native device service, VPN probing, and live network-path monitoring. B1/B2/B10 use locally generated MapKit tiles; production route, annotation, Pin, and position-arrow rendering remains active.

Run the screenshot test on an available iOS Simulator:

```sh
xcodebuild -project app/GoFly/GoFly.xcodeproj \
  -scheme GoFly \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -parallel-testing-enabled NO \
  -only-testing:GoFlyUITests/GoFlyFigmaFrameScreenshots \
  test
```

The test writes one PNG per supported frame and appearance to `work/gofly-ios-figma04/screenshots/` and writes `manifest.json` with the exact Figma node, launch flags, unavailable frames, and conflicts. It also attaches screenshots to the `.xcresult`.

## Refresh Figma references

`work/gofly-ios-figma04/figma/manifest.json` maps each rendered frame and appearance to its Figma node ID. In the Figma Desktop Bridge, call `figma_capture_screenshot` for the node ID with PNG format and scale 1, then save the returned image as `work/gofly-ios-figma04/figma/<FrameID>-<light|dark>.png`. Keep Figma read-only. Refresh the matching manifest entry when node IDs or rendered variants change.

The initial reference set contains 128 PNGs captured from the rendered A–F sections on 2026-10-29. The B11 Dark node currently renders a screen, which conflicts with the task instructions and ticket 00 record saying that Dark is missing. The screenshot is retained as conflict evidence and is not treated as an approved design.

## Current fixture coverage

The current test captures R01, R02, R03, R04, R04.a, R05, B1, B2, and B10 in Light and Dark. All other frames are listed in the generated manifest with a reason; the fixture does not substitute placeholder screenshots for those frames.
