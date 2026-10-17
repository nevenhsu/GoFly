import XCTest

@MainActor
final class GoFlyJoystickUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMissingOriginSetupUsesRealFailedGoAndKeepsCandidateWithoutJoystickSuccess() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.buttons["joystick.setOrigin"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0478, 121.5170")
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        dismissKeyboard(app)
        app.buttons["map.candidate.go"].tap()
        let reason = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertEqual(reason.label,
            "A prepared physical iPhone is required. The simulator cannot start the device service or confirm GPS recovery.")
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
        attach(app, "11-origin-go-real-device-required-keeps-candidate")
        app.buttons["map.serviceError.dismiss"].tap()
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.selectGoFlyMode("teleport")
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertTrue(app.buttons["map.candidate.go"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["map.positionStatus"].label.contains("Stopped"))
    }

    func testSetupModeBrowsingAndForegroundDoNotMoveOrRequestLocation() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        app.buttons["joystick.setOrigin"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0330, 121.5654")
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        dismissKeyboard(app)
        app.selectGoFlyMode("route")
        XCTAssertTrue(app.buttons["route.details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        app.selectGoFlyMode("joystick")
        assertMissingOrigin(app)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertMissingOrigin(app)
        XCTAssertFalse(app.staticTexts["operation.attempt"].exists)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map.positionStatus"].label.contains("Stopped"))
        app.selectGoFlyMode("teleport")
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["map.candidate.pin"].value as? String, "25.033000, 121.565400")
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, "11-browse-foreground-keeps-unsubmitted-start")
    }

    func testLocalizedLargeDarkModeMenuAndOriginSetupKeepKeyboardTargetsVisible() throws {
        try simulatorOnly()
        for language in ["en", "zh-Hant", "zh-Hans"] {
            let app = makeApp(language: language)
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["map.mode"].waitForExistence(timeout: 10))
            let menu = app.buttons["map.mode.menu"]
            if language == "en" {
                XCTAssertTrue(menu.exists, "Full English mode names require the readable native menu at maximum text size.")
            }
            if menu.exists {
                assertTarget(menu, app)
            } else {
                let expected = language == "zh-Hant" ? ["瞬移", "路線", "搖桿"] : ["瞬移", "路线", "摇杆"]
                for (name, label) in zip(["teleport", "route", "joystick"], expected) {
                    let choice = app.buttons["mode." + name]
                    XCTAssertEqual(choice.label, label)
                    assertTarget(choice, app)
                }
            }
            app.selectGoFlyMode("joystick")
            assertMissingOrigin(app)
            assertTarget(app.buttons["joystick.setOrigin"], app)
            attach(app, "11-no-origin-\(language)-max-dark")
            app.buttons["joystick.setOrigin"].tap()
            let query = app.textFields["search.query"]
            XCTAssertTrue(query.waitForExistence(timeout: 5))
            query.tap()
            query.typeText("25.0478, 121.5170")
            XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            XCTAssertLessThanOrEqual(query.frame.maxY, keyboard.frame.minY + 1)
            XCTAssertLessThanOrEqual(query.frame.maxY, app.maps.firstMatch.frame.maxY + 1)
            assertTarget(app.buttons["map.candidate.pin"], app)
            assertTarget(app.buttons["map.candidate.go"], app)
            assertCentered(app)
            XCTAssertEqual(app.alerts.count, 0)
            attach(app, "11-start-selection-\(language)-max-dark-keyboard")
            dismissKeyboard(app)
            app.selectGoFlyMode("joystick")
            assertMissingOrigin(app)
            app.buttons["map.settings"].tap()
            XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 5))
            assertTarget(app.buttons["service.primary"], app)
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests verify simulator origin-unavailable and real deviceRequired paths. Physical joystick movement is deferred.")
        #endif
    }
    private func makeApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-map-metrics",
                               "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-imports-store", UUID().uuidString,
                               "-gofly-ui-favorite-routes-store", UUID().uuidString,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_TW"]
        return app
    }
    private func assertMissingOrigin(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["joystick.setOrigin"].waitForExistence(timeout: 5))
        assertTarget(app.buttons["joystick.setOrigin"], app)
        XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
        XCTAssertFalse(app.sliders["joystick.speed"].exists)
        XCTAssertFalse(app.buttons["joystick.randomDestination"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["joystick.wander"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }
    private func assertCentered(_ app: XCUIApplication) {
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let values = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
            return values.count == 6 && values[4] > 0 && values[5] > 0
                && abs(values[0] - values[2]) < 3 && abs(values[1] - values[3]) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 5), .completed)
    }
    private func assertTarget(_ element: XCUIElement, _ app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let minimum: CGFloat = 44 - 0.000001
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum, file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
