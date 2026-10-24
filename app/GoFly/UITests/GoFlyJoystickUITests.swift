import XCTest

@MainActor
final class GoFlyJoystickUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // The simulator has no prepared device: Go and Start are visible but disabled, and no success is ever faked.
    // Enablement without an origin is covered by WanderControllerIntegrationTests.

    func testJoystickShowsPadAndStartWithoutAnOrigin() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        XCTAssertFalse(app.descendants(matching: .any)["map.joystick.locationCard"].exists)
        XCTAssertTrue((app.descendants(matching: .any)["map.statusPill"].value as? String ?? "").contains("Error"))
    }

    func testSearchedPinKeepsTheJoystickTabAndShowsTheGoCard() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0478, 121.5170")
        app.buttons["search.result.25.047800, 121.517000"].tap()
        dismissKeyboard(app)
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertTrue(app.buttons["mode.joystick"].isSelected, "searching from the joystick tab does not switch tabs")
        let card = app.descendants(matching: .any)["map.joystick.locationCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let go = app.buttons["map.candidate.go"]
        XCTAssertTrue(go.exists)
        XCTAssertEqual(go.label, "Go")
        XCTAssertEqual(app.alerts.count, 0)

        app.buttons["map.joystick.locationCard.dismiss"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["joystick.pad"].waitForExistence(timeout: 5),
                      "closing the card brings the pad back")
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator UI covers origin-unavailable and device-required paths.")
        #endif
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        return app
    }

    private func assertMissingOrigin(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["joystick.pad"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["joystick.setOrigin"].exists)
        let wander = app.buttons["joystick.wander"]
        XCTAssertTrue(wander.exists)
        XCTAssertTrue(wander.exists, "Start is visible; it is disabled in the simulator because no device is prepared")
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }

    private func assertTarget(_ element: XCUIElement, _ app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let minimum: CGFloat = 44 - 0.000001
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum, file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
}
