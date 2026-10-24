import XCTest

/// C7: the only map control is Recenter, 16 pt above the current panel.
final class GoFlyMapControlsUITests: GoFlyRouteModeTestCase {
    func testOnlyRecenterRemainsAndSitsSixteenPointsAboveThePanel() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            for mode in ["teleport", "route", "joystick"] {
                if mode != "teleport" { app.selectGoFlyMode(mode) }
                let recenter = element(app, "map.recenter")
                XCTAssertFalse(app.buttons["map.followHeading"].exists)
                XCTAssertFalse(app.buttons["map.north"].exists)
                XCTAssertEqual(recenter.frame.maxX, app.frame.maxX - 16, accuracy: 1, "\(mode) right inset")
                let panel = app.descendants(matching: .any)["map.sheet"]
                if panel.waitForExistence(timeout: 3) {
                    Thread.sleep(forTimeInterval: 0.5)
                    XCTAssertEqual(panel.frame.minY - recenter.frame.maxY, 16, accuracy: 1, "\(mode) gap above panel")
                }
                evidence(app, task: "C7", name: "recenter-\(mode)-\(appearance)")
            }
            app.terminate()
        }
    }

    func testRecenterFollowsTheSheetWhenCollapsed() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        let grabber = app.buttons["map.sheet.grabber"]
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        grabber.tap()
        Thread.sleep(forTimeInterval: 0.9)
        let panel = element(app, "map.sheet")
        let recenter = element(app, "map.recenter")
        XCTAssertEqual(panel.frame.minY - recenter.frame.maxY, 16, accuracy: 1)
        evidence(app, task: "C7", name: "recenter-route-collapsed-light")
    }
}
