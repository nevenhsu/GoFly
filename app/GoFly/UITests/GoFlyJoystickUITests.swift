import XCTest

@MainActor
final class GoFlyJoystickUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMissingOriginGoKeepsCandidateWithoutJoystickSuccess() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.selectGoFlyMode("teleport")
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0478, 121.5170")
        app.buttons["search.result.25.047800, 121.517000"].tap()
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        dismissKeyboard(app)
        app.buttons["map.candidate.go"].tap()
        let reason = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertTrue(reason.label.contains("A prepared physical iPhone is required."))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
        app.buttons["map.serviceError.dismiss"].tap()
        XCTAssertTrue(app.buttons["map.searchBar"].waitForExistence(timeout: 5))
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.selectGoFlyMode("teleport")
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertTrue(app.buttons["map.candidate.go"].isEnabled)
        XCTAssertTrue((app.descendants(matching: .any)["map.statusPill"].value as? String ?? "").contains("Error"))
    }

    func testManualJoystickCandidateGoKeepsJoystickModeAndCandidate() throws {
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
        XCTAssertTrue(app.buttons["map.candidate.go"].exists)
        XCTAssertEqual(app.buttons["map.candidate.go"].label, "Go")
        app.buttons["map.candidate.go"].tap()
        XCTAssertTrue(app.staticTexts["map.serviceError.message"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["joystick.pad"].exists)
        XCTAssertTrue(app.buttons["joystick.wander"].exists)
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testWanderPlanningCanStartWithoutAHealthyOrigin() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        let wander = app.buttons["joystick.wander"]
        XCTAssertEqual(wander.label, "Start")
        XCTAssertTrue(wander.isEnabled)
        wander.tap()
        XCTAssertFalse(app.buttons["joystick.randomDestination"].exists)

        app.selectGoFlyMode("teleport")
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0330, 121.5654")
        app.buttons["search.result.25.033000, 121.565400"].tap()
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        dismissKeyboard(app)
        app.selectGoFlyMode("joystick")
        let updatedWander = app.buttons["joystick.wander"]
        XCTAssertTrue(updatedWander.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.wander.target"].exists)
        XCTAssertTrue(updatedWander.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
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
        XCTAssertTrue(wander.isEnabled)
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
