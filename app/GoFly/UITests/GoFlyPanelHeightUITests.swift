import XCTest

/// Each mode panel has a default and a minimum height (points above the tab bar), as implemented
/// (2026-10-26; Figma 04 not yet synced): teleport 305 / 120 (B2 / B1), route content-sized 345 / 96
/// (D1 / D3), joystick 349 / 96 (E1 / E1.a). Content sits on the 4 pt grid below the 33 pt grabber row
/// (8 pt inset + 5 pt capsule + 20 pt gap) and ends 20 pt above the tab bar.
final class GoFlyPanelHeightUITests: GoFlyRouteModeTestCase {
    private let grabberRow: CGFloat = 33

    private func visibleHeight(_ app: XCUIApplication) -> CGFloat {
        Thread.sleep(forTimeInterval: 0.9)
        return element(app, "map.bottomBar").frame.minY - element(app, "map.sheet").frame.minY
    }

    func testTeleportDefaultAndMinimum() throws {
        let app = launch()
        XCTAssertEqual(visibleHeight(app), 305, accuracy: 1, "B2 default")
        evidence(app, task: "H", name: "teleport-default-light")
        app.buttons["map.sheet.grabber"].tap()
        XCTAssertEqual(visibleHeight(app), 120, accuracy: 1)
    }

    func testRouteDefaultAndMinimum() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        XCTAssertEqual(visibleHeight(app), 345, accuracy: 1, "D1 default")
        app.buttons["map.sheet.grabber"].tap()
        XCTAssertEqual(visibleHeight(app), 96, accuracy: 1, "D3 minimum")
    }

    func testJoystickDefaultMinimumAndInteriorSpacing() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            app.selectGoFlyMode("joystick")
            XCTAssertEqual(visibleHeight(app), 349, accuracy: 1, "E1 default")
            let sheet = element(app, "map.sheet")
            let bar = element(app, "map.bottomBar")
            let pad = element(app, "joystick.pad")
            let start = element(app, "joystick.wander")
            let chip = element(app, "joystick.speed")
            XCTAssertEqual(chip.frame.minY - sheet.frame.minY, grabberRow + 4, accuracy: 2, "chip 36 pt centered in the 44 pt row below the grabber")
            XCTAssertEqual(chip.frame.height, 36, accuracy: 1)
            XCTAssertEqual(pad.frame.minY - sheet.frame.minY, grabberRow + 68, accuracy: 2, "pad 68 pt below the grabber row")
            XCTAssertEqual(pad.frame.height, 152, accuracy: 1)
            XCTAssertEqual(start.frame.minY - sheet.frame.minY, grabberRow + 244, accuracy: 2, "button 244 pt below the grabber row")
            XCTAssertEqual(start.frame.height, 52, accuracy: 1)
            XCTAssertEqual(bar.frame.minY - start.frame.maxY, 20, accuracy: 2, "20 pt below the button")
            evidence(app, task: "H", name: "joystick-default-\(appearance)")

            app.buttons["map.sheet.grabber"].tap()
            XCTAssertEqual(visibleHeight(app), 96, accuracy: 1, "E1.a minimum")
            XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
            evidence(app, task: "H", name: "joystick-minimum-\(appearance)")
            app.terminate()
        }
    }
}
