import Foundation
import XCTest

/// Captures only frames with a deterministic local fixture. Every omitted Figma
/// frame is listed in the manifest with its reason, so a missing screenshot is
/// never confused with a verified comparison.
@MainActor
final class GoFlyFigmaFrameScreenshots: XCTestCase {
    private let supportedFrames: Set<String> = [
        "R01", "R02", "R03", "R04", "R04.a", "R05", "R07", "R08",
        "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B10",
        "D1", "D5", "D6", "D8", "D19",
        "E1", "E1.a", "E2", "E2.a", "E4",
        "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9"
    ]

    func testF1aStopFailureFixtureShowsResetAction() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-frame", "F1.a",
            "-gofly-ui-appearance", "light",
            "-gofly-ui-device-state", "stop-failure",
            "-gofly-ui-preferences-language", "zh-Hant",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        app.launch()
        waitForFixture(app, frame: "F1.a")
        XCTAssertTrue(app.buttons["service.reset"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "F1.a-light-stop-failure"
        attachment.lifetime = .keepAlways
        add(attachment)
        #endif
    }

    func testAdditionalConfiguredFrameFixturesOpenExpectedSurface() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        for frame in ["B3", "B4", "B6", "D5", "D19", "E1.a", "E2", "E2.a", "E4"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-frame", frame,
                "-gofly-ui-appearance", "light",
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly-ui-favorites-store", UUID().uuidString,
                "-gofly-ui-imports-store", UUID().uuidString,
                "-gofly-ui-favorite-routes-store", UUID().uuidString,
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if frame == "B10" { app.launchArguments.append("-gofly-ui-wifi-disconnected") }
            if frame == "E2" || frame == "E2.a" { app.launchArguments += ["-gofly-ui-device-state", "normal"] }
            app.launch()
            waitForFixture(app, frame: frame)
            app.terminate()
        }
        #endif
    }

    func testCaptureSupportedFigmaFramesInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let root = repositoryRoot
        let catalogURL = root.appendingPathComponent("app/GoFly/Resources/Figma04FrameCatalog.json")
        let catalog = try JSONDecoder().decode(FigmaCatalog.self, from: Data(contentsOf: catalogURL))
        let output = root.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try preservePreviousRun(at: output)

        var captures: [CaptureRecord] = []
        for frame in catalog.frames.filter({ supportedFrames.contains($0.id) }) {
            for appearance in ["light", "dark"] {
                let nodeID = try XCTUnwrap(frame.nodeIds[appearance], "missing Figma \(appearance) variant for \(frame.id)")
                let sessionID = UUID().uuidString
                let app = XCUIApplication()
                app.launchArguments = [
                    "-gofly-ui-frame", frame.id,
                    "-gofly-ui-appearance", appearance,
                    "-gofly-ui-session-store", sessionID,
                    "-gofly-ui-favorites-store", UUID().uuidString,
                    "-gofly-ui-imports-store", UUID().uuidString,
                    "-gofly-ui-favorite-routes-store", UUID().uuidString,
                    "-gofly-ui-preferences-store", UUID().uuidString,
                    "-gofly-ui-preferences-language", "zh-Hant",
                    "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
                ]
                if frame.id == "R04" { app.launchArguments.append("-gofly-ui-vpn-static") }
                if frame.id == "B10" { app.launchArguments.append("-gofly-ui-wifi-disconnected") }
                if frame.id == "B7" {
                    app.launchArguments += ["-gofly-ui-device-state", "unconfirmed-point"]
                }
                if frame.id == "D8" {
                    app.launchArguments += ["-gofly-ui-route-outcome", "planningFailed"]
                }
                if frame.id == "F1.a" {
                    app.launchArguments += ["-gofly-ui-device-state", "stop-failure"]
                }
                app.launch()
                waitForFixture(app, frame: frame.id)

                if ["F4", "F5", "F6", "F6.a", "F7", "F8", "F9"].contains(frame.id) {
                    openSettingsFrame(app, frame: frame.id)
                }
                if frame.id == "F1.a" {
                    XCTAssertTrue(app.buttons["service.reset"].waitForExistence(timeout: 10))
                }

                if frame.id == "R05" {
                    let help = app.buttons["onboarding.vpn.help.open"]
                    XCTAssertTrue(help.waitForExistence(timeout: 10))
                    help.tap()
                    XCTAssertTrue(app.buttons["onboarding.vpn.help.step1.action"].waitForExistence(timeout: 10))
                    XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.help.back"].waitForExistence(timeout: 5))
                    XCTAssertFalse(app.buttons["onboarding.vpn.help.openSettings"].exists)
                    XCTAssertFalse(app.buttons["onboarding.vpn.help.openVPN"].exists)
                }
                if frame.id == "R04.a" {
                    XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.failure"].waitForExistence(timeout: 10))
                }
                if frame.id == "B10" {
                    XCTAssertTrue(app.descendants(matching: .any)["map.wifiError"].waitForExistence(timeout: 10))
                }

                // Allow the offline tile renderer and SwiftUI transitions to settle.
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                let screenshot = app.screenshot()
                let filename = "\(frame.id)-\(appearance).png"
                let relativePath = "work/gofly-ios-figma04/screenshots/\(filename)"
                try screenshot.pngRepresentation.write(to: output.appendingPathComponent(filename), options: .atomic)
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(frame.id)-\(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
                captures.append(CaptureRecord(
                    frame: frame.id,
                    name: frame.name,
                    appearance: appearance,
                    figmaNodeID: nodeID,
                    screenshotPath: relativePath,
                    expectedFigmaPath: "work/gofly-ios-figma04/figma/\(filename)",
                    fixtureFlags: app.launchArguments
                ))
                app.terminate()
            }
        }

        let unavailable = catalog.frames.filter { !supportedFrames.contains($0.id) }.map {
            UnavailableRecord(frame: $0.id, name: $0.name, reason: unavailableReason(for: $0.id))
        }
        let conflicts = [
            "B11: the task and ticket 00 record say Dark is missing, but a read-only capture of Figma node 322:40470 currently renders a Dark · B11 screen; no B11 screenshot is emitted until this design status is reconciled."
        ]
        let manifest = ScreenshotManifest(
            fileKey: catalog.fileKey,
            pageNodeID: catalog.pageNodeId,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            captures: captures,
            unavailable: unavailable,
            figmaConflicts: conflicts
        )
        let data = try JSONEncoder.prettyPrinted.encode(manifest)
        try data.write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        try writeIndex(catalog: catalog, captures: captures, unavailable: unavailable,
                       conflicts: conflicts, output: output)
        #endif
    }

    private func preservePreviousRun(at output: URL) throws {
        let manager = FileManager.default
        let previousFiles = try manager.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            .filter { [".png", ".json", ".html"].contains($0.pathExtension.lowercased()) }
        guard !previousFiles.isEmpty else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archive = output.appendingPathComponent("previous", isDirectory: true)
            .appendingPathComponent(timestamp, isDirectory: true)
        try manager.createDirectory(at: archive, withIntermediateDirectories: true)
        for file in previousFiles {
            try manager.copyItem(at: file, to: archive.appendingPathComponent(file.lastPathComponent))
        }
    }

    private func writeIndex(catalog: FigmaCatalog, captures: [CaptureRecord],
                            unavailable: [UnavailableRecord], conflicts: [String], output: URL) throws {
        let captureKeys = Set(captures.map { "\($0.frame)-\($0.appearance)" })
        let unavailableByFrame = Dictionary(uniqueKeysWithValues: unavailable.map { ($0.frame, $0.reason) })
        let frameRows = catalog.frames.map { frame -> String in
            let section = frame.id.first == "R" ? "A" : String(frame.id.prefix(1))
            let light = comparisonCells(frame: frame, appearance: "light", available: captureKeys,
                                        unavailableReason: unavailableByFrame[frame.id])
            let dark = comparisonCells(frame: frame, appearance: "dark", available: captureKeys,
                                       unavailableReason: unavailableByFrame[frame.id])
            return """
            <tr data-section="\(escapeHTML(section))" data-frame="\(escapeHTML(frame.id))">
              <th scope="row"><strong>\(escapeHTML(frame.id))</strong><br><span>\(escapeHTML(frame.name))</span></th>
              \(light)
              \(dark)
            </tr>
            """
        }.joined(separator: "\n")
        let conflictNotice = conflicts.map { "<li>\(escapeHTML($0))</li>" }.joined()
        let html = """
        <!doctype html>
        <html lang="zh-Hant">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>GoFly Figma 04 · App 對照</title>
          <style>
            :root { color-scheme: light; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
            body { margin: 20px; color: #202124; background: #f6f7f9; }
            header { position: sticky; top: 0; z-index: 2; padding: 12px 0; background: #f6f7f9; }
            h1 { margin: 0 0 10px; font-size: 21px; }
            .meta, .notes { color: #555; }
            .notes { max-width: 1000px; }
            table { width: 100%; border-collapse: separate; border-spacing: 0; background: white; }
            th, td { padding: 10px; border-right: 1px solid #ddd; border-bottom: 1px solid #ddd; vertical-align: top; }
            thead th { position: sticky; top: 77px; z-index: 1; background: #e9ebef; text-align: left; }
            tbody th { min-width: 130px; text-align: left; }
            tbody th span { display: inline-block; margin-top: 5px; color: #555; font-weight: 400; }
            img { display: block; width: min(19vw, 220px); min-width: 135px; height: auto; border: 1px solid #d4d6da; background: #eee; }
            .missing { width: min(19vw, 220px); min-width: 135px; min-height: 180px; padding: 8px; box-sizing: border-box; color: #855b00; background: #fff6d9; }
            .conflict { color: #a11; font-weight: 600; }
            tr[hidden] { display: none; }
          </style>
        </head>
        <body>
          <header>
            <h1>GoFly · Figma 04 對照</h1>
            <div class="meta">Frame × Light／Dark · Figma 截圖與 App fixture 輸出</div>
            <label>Section <select id="section-filter"><option value="all">全部</option><option>A</option><option>B</option><option>C</option><option>D</option><option>E</option><option>F</option></select></label>
          </header>
          <ul class="notes">\(conflictNotice)</ul>
          <table>
            <thead><tr><th>Frame</th><th>Light · Figma</th><th>Light · App</th><th>Dark · Figma</th><th>Dark · App</th></tr></thead>
            <tbody>\(frameRows)</tbody>
          </table>
          <script>
            document.getElementById('section-filter').addEventListener('change', function () {
              document.querySelectorAll('tbody tr').forEach(function (row) {
                row.hidden = this.value !== 'all' && row.dataset.section !== this.value;
              }, this);
            });
          </script>
        </body>
        </html>
        """
        try html.write(to: output.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    private func comparisonCells(frame: FigmaFrame, appearance: String,
                                 available: Set<String>, unavailableReason: String?) -> String {
        let key = "\(frame.id)-\(appearance)"
        let nodeID = frame.nodeIds[appearance]
        let figmaCell: String
        if nodeID != nil {
            let conflict = frame.id == "B11" && appearance == "dark"
            let note = conflict ? "<span class=\"conflict\">Conflict: not approved</span>" : ""
            figmaCell = "<td>\(note)<img loading=\"lazy\" src=\"../figma/\(escapeHTML(key)).png\" alt=\"Figma \(escapeHTML(key))\"></td>"
        } else {
            figmaCell = "<td><div class=\"missing\">No rendered Figma \(escapeHTML(appearance)) variant recorded.</div></td>"
        }
        let appCell: String
        if available.contains(key) {
            appCell = "<td><img loading=\"lazy\" src=\"./\(escapeHTML(key)).png\" alt=\"App \(escapeHTML(key))\"></td>"
        } else {
            let reason = unavailableReason ?? "No deterministic fixture recorded."
            appCell = "<td><div class=\"missing\">\(escapeHTML(reason))</div></td>"
        }
        return figmaCell + appCell
    }

    private func escapeHTML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func waitForFixture(_ app: XCUIApplication, frame: String) {
        let fixture = app.descendants(matching: .any)["figma.fixture.\(frame)"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 15), "frame fixture did not open: \(frame)")
        switch frame {
        case "R02", "R03":
            XCTAssertTrue(app.buttons["onboarding.location.allow"].waitForExistence(timeout: 10))
        case "R04", "R04.a", "R05":
            XCTAssertTrue(app.buttons["onboarding.vpn.check"].waitForExistence(timeout: 10))
        case "B7":
            XCTAssertTrue(app.descendants(matching: .any)["map.unconfirmedFailure"].waitForExistence(timeout: 15))
        case "D8":
            XCTAssertTrue(app.descendants(matching: .any)["route.error"].waitForExistence(timeout: 15))
        case "F1.b":
            XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["service.resetSucceeded"].waitForExistence(timeout: 10))
        case "F1":
            XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 10))
        case "R07":
            XCTAssertTrue(app.descendants(matching: .any)["setup.mac.status"].waitForExistence(timeout: 10))
        case "R08":
            XCTAssertTrue(app.buttons["setup.retry"].waitForExistence(timeout: 10))
        case "B1", "B2", "B5", "B10", "D1", "D6", "E1":
            XCTAssertTrue(app.otherElements["map.canvas"].waitForExistence(timeout: 10))
        case "B3":
            XCTAssertTrue(app.otherElements["search.panel"].waitForExistence(timeout: 10))
        case "B4":
            XCTAssertTrue(app.otherElements["search.panel"].waitForExistence(timeout: 10))
            let result = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "search.result.")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10))
        case "B6":
            XCTAssertTrue(app.descendants(matching: .any)["snackbar"].waitForExistence(timeout: 10))
        case "D5":
            XCTAssertTrue(app.descendants(matching: .any)["search.panel"].waitForExistence(timeout: 10))
        case "D19":
            XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.content"].waitForExistence(timeout: 10))
        case "E1.a":
            XCTAssertTrue(app.descendants(matching: .any)["joystick.panel"].waitForExistence(timeout: 10))
        case "E2":
            XCTAssertTrue(app.buttons["joystick.stopWander"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["漫步中"].exists)
        case "E2.a":
            XCTAssertTrue(app.descendants(matching: .any)["joystick.panel"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["漫步中"].waitForExistence(timeout: 10))
        case "E4":
            XCTAssertTrue(app.descendants(matching: .any)["map.wander.locationCard"].waitForExistence(timeout: 10))
        default:
            break
        }
    }

    private func openSettingsFrame(_ app: XCUIApplication, frame: String) {
        let settingsID: String
        let pageID: String
        switch frame {
        case "F4": settingsID = "settings.location"; pageID = "settings.location.page"
        case "F5": settingsID = "settings.vpn"; pageID = "settings.vpn.page"
        case "F6", "F6.a": settingsID = "settings.background"; pageID = "settings.background.page"
        case "F7": settingsID = "settings.language"; pageID = "settings.language.page"
        case "F8": settingsID = "settings.appearance"; pageID = "settings.appearance.page"
        default: settingsID = "settings.device"; pageID = "settings.device.page"
        }
        let row = app.descendants(matching: .any)[settingsID]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "settings entry missing: \(settingsID)")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)[pageID].waitForExistence(timeout: 10),
                      "settings page missing: \(pageID)")

        if frame == "F6.a" {
            let duration = app.descendants(matching: .any)["settings.background.duration"]
            XCTAssertTrue(duration.waitForExistence(timeout: 10))
            duration.tap()
            XCTAssertTrue(app.buttons["settings.background.duration.confirm"].waitForExistence(timeout: 10))
        }
    }

    private func unavailableReason(for frame: String) -> String {
        switch frame {
        case "R07", "R08": "Requires Mac setup identity or pairing transaction data; the fixture intentionally bypasses setup storage and real device APIs."
        case "B3", "B4", "B5": "Requires deterministic MapKit search, coordinate resolution, and place-sheet state injection."
        case "B6", "B7", "B8", "B9", "B11": "Requires a deterministic position command, connection interruption, or recovery state."
        case "C1", "C2", "C3", "C4": "Requires seeded favorite-place persistence and edit/delete undo state."
        case "D1", "D2", "D2.a", "D3", "D4", "D5", "D6", "D7", "D8", "D10", "D10.a", "D11", "D12", "D13", "D14", "D15", "D16", "D17", "D18", "D19", "D20", "D21", "D22", "D23": "Requires route planning, GPX/share importers, interruption state, or seeded route/favorite data."
        case "E1", "E1.a", "E2", "E2.a", "E3", "E4", "E5": "Requires deterministic joystick, wander-planning, destination, or recovery state."
        case "F1", "F1.a", "F1.b", "F4", "F5", "F6", "F6.a", "F7", "F8", "F9": "Settings pages depend on OS permission/service status and have no injected status fixture yet."
        default: "No deterministic fixture exists yet."
        }
    }

    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
    }
}

private struct FigmaCatalog: Decodable {
    let fileKey: String
    let pageNodeId: String
    let frames: [FigmaFrame]
}

private struct FigmaFrame: Decodable {
    let id: String
    let name: String
    let nodeIds: [String: String]
}

private struct ScreenshotManifest: Encodable {
    let fileKey: String
    let pageNodeID: String
    let generatedAt: String
    let captures: [CaptureRecord]
    let unavailable: [UnavailableRecord]
    let figmaConflicts: [String]
}

private struct CaptureRecord: Encodable {
    let frame: String
    let name: String
    let appearance: String
    let figmaNodeID: String
    let screenshotPath: String
    let expectedFigmaPath: String
    let fixtureFlags: [String]
}

private struct UnavailableRecord: Encodable {
    let frame: String
    let name: String
    let reason: String
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
