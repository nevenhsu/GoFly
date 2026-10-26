import XCTest

/// F3: tapping a tab restores a panel that is at its minimum height.
final class GoFlyTabRestoreUITests: GoFlyRouteModeTestCase {
    private func sheetHeight(_ app: XCUIApplication) -> CGFloat {
        Thread.sleep(forTimeInterval: 0.9)
        return element(app, "map.sheet").frame.height
    }

    func testTeleportTabRestoresACollapsedPanel() throws {
        let app = launch()
        app.buttons["map.sheet.grabber"].tap()
        let collapsed = sheetHeight(app)
        app.selectGoFlyMode("teleport")
        let restored = sheetHeight(app)
        XCTAssertGreaterThan(restored, collapsed, "teleport panel grows from \(collapsed) to \(restored)")
        evidence(app, task: "F3", name: "teleport-restored-light")
    }

    func testRouteTabRestoresACollapsedPanel() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        let full = sheetHeight(app)
        app.buttons["map.sheet.grabber"].tap()
        let collapsed = sheetHeight(app)
        XCTAssertEqual(collapsed, 96, accuracy: 1)
        app.selectGoFlyMode("route")
        XCTAssertEqual(sheetHeight(app), full, accuracy: 1, "route panel returns to its content height")
    }

    func testJoystickTabRestoresACollapsedPanel() throws {
        let app = launch()
        app.selectGoFlyMode("joystick")
        let full = sheetHeight(app)
        app.buttons["map.sheet.grabber"].tap()
        let collapsed = sheetHeight(app)
        XCTAssertLessThan(collapsed, full)
        app.selectGoFlyMode("joystick")
        XCTAssertEqual(sheetHeight(app), full, accuracy: 1, "joystick panel returns to its previous height")
    }
}
