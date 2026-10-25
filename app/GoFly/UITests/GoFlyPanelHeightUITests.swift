import XCTest

/// Each mode panel has a default and a minimum height (Figma, points above the tab bar):
/// teleport 300 / 120 (B2 / B1), route 340 / 76 (D1 / D3), joystick 352 / 76 (E1 / E1.a); Figma values snapped to the 4 pt grid.
final class GoFlyPanelHeightUITests: GoFlyRouteModeTestCase {
    private func visibleHeight(_ app: XCUIApplication) -> CGFloat {
        Thread.sleep(forTimeInterval: 0.9)
        return element(app, "map.bottomBar").frame.minY - element(app, "map.sheet").frame.minY
    }

    func testTeleportDefaultAndMinimum() throws {
        let app = launch()
        XCTAssertEqual(visibleHeight(app), 120, accuracy: 1, "B1 minimum")
        app.selectGoFlyMode("teleport")
        XCTAssertEqual(visibleHeight(app), 300, accuracy: 1, "B2 default")
        evidence(app, task: "H", name: "teleport-default-light")
        app.buttons["map.sheet.grabber"].tap()
        XCTAssertEqual(visibleHeight(app), 120, accuracy: 1)
    }

    func testRouteDefaultAndMinimum() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        XCTAssertEqual(visibleHeight(app), 340, accuracy: 1, "D1 default")
        app.buttons["map.sheet.grabber"].tap()
        XCTAssertEqual(visibleHeight(app), 76, accuracy: 1, "D3 minimum")
    }

    func testJoystickDefaultMinimumAndInteriorSpacing() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            app.selectGoFlyMode("joystick")
            XCTAssertEqual(visibleHeight(app), 352, accuracy: 1, "E1 default")
            let sheet = element(app, "map.sheet")
            let bar = element(app, "map.bottomBar")
            let pad = element(app, "joystick.pad")
            let start = element(app, "joystick.wander")
            let chip = element(app, "joystick.speed")
            XCTAssertEqual(chip.frame.minY - sheet.frame.minY, 24, accuracy: 2, "chip 36 pt in the 44 pt row at y 20 → y 24")
            XCTAssertEqual(chip.frame.height, 36, accuracy: 1)
            XCTAssertEqual(pad.frame.minY - sheet.frame.minY, 88, accuracy: 2, "pad at y 88")
            XCTAssertEqual(pad.frame.height, 152, accuracy: 1)
            XCTAssertEqual(start.frame.minY - sheet.frame.minY, 264, accuracy: 2, "button at y 264")
            XCTAssertEqual(start.frame.height, 52, accuracy: 1)
            XCTAssertEqual(bar.frame.minY - start.frame.maxY, 36, accuracy: 2, "36 pt below the button")
            evidence(app, task: "H", name: "joystick-default-\(appearance)")

            app.buttons["map.sheet.grabber"].tap()
            XCTAssertEqual(visibleHeight(app), 76, accuracy: 1, "E1.a minimum")
            XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
            evidence(app, task: "H", name: "joystick-minimum-\(appearance)")
            app.terminate()
        }
    }
}
