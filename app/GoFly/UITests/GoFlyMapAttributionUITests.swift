import XCTest

/// The Apple Maps logo and Legal link stay above the bottom panel, tab bar and
/// location cards in every mode (MapKit attribution must remain visible).
final class GoFlyMapAttributionUITests: GoFlyRouteModeTestCase {
    private func legalLink(_ app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] 'legal' OR label CONTAINS '法律'")
        let link = element(app, "map.canvas").descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "missing the MapKit Legal link")
        return link
    }

    private func assertAboveChrome(_ app: XCUIApplication, _ coverIDs: [String], _ message: String) {
        Thread.sleep(forTimeInterval: 0.9)
        let legal = legalLink(app)
        // MapKit's attribution never reports isHittable to XCUITest; check it is on screen instead.
        XCTAssertFalse(legal.frame.isEmpty, "\(message): Legal link has no frame")
        XCTAssertTrue(app.frame.contains(legal.frame), "\(message): Legal link off screen")
        for id in coverIDs {
            let cover = element(app, id)
            XCTAssertLessThanOrEqual(legal.frame.maxY, cover.frame.minY + 0.5, "\(message): covered by \(id)")
        }
    }

    func testLegalLinkAboveEveryModePanel() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            assertAboveChrome(app, ["map.sheet", "map.bottomBar"], "B1")
            evidence(app, task: "A1", name: "teleport-minimum-\(appearance)")
            app.selectGoFlyMode("teleport")
            assertAboveChrome(app, ["map.sheet", "map.bottomBar"], "B2")
            app.selectGoFlyMode("route")
            assertAboveChrome(app, ["map.sheet", "map.bottomBar"], "D1")
            app.buttons["map.sheet.grabber"].tap()
            assertAboveChrome(app, ["map.sheet", "map.bottomBar"], "D3")
            app.selectGoFlyMode("joystick")
            assertAboveChrome(app, ["map.sheet", "map.bottomBar"], "E1")
            evidence(app, task: "A1", name: "joystick-default-\(appearance)")
            app.terminate()
        }
    }

    func testLegalLinkAboveTeleportLocationCard() throws {
        let app = launch()
        element(app, "map.canvas").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        assertAboveChrome(app, ["map.teleport.locationCard"], "B5")
        evidence(app, task: "A1", name: "teleport-card-light")
    }
}
