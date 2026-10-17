import XCTest

@MainActor
final class GoFlyServiceUITests: XCTestCase {
    func testMapStartShowsDismissibleFailureAndKeepsRepairAccessible() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This failure-path test requires the simulator deviceRequired adapter; device clear is verified separately.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["map.serviceControl"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        start.tap()

        let error = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "A prepared physical iPhone is required. The simulator cannot start the device service or confirm GPS recovery.")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["map.positionStatus"].label.contains("Stopped"))
        attach(app, name: "01-map-start-device-required")

        app.buttons["map.serviceError.dismiss"].tap()
        XCTAssertFalse(error.exists)
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["map.positionStatus"].label.contains("Stopped"))
        app.buttons["map.settings"].tap()
        let restore = app.buttons["service.restoreGPS"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(restore.isEnabled)
        XCTAssertTrue(app.buttons["service.resetTunnel"].isEnabled)
        restore.tap()
        let repairFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: app.buttons["service.primary"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [repairFinished], timeout: 5), .completed)
        XCTAssertTrue(restore.isEnabled)
        XCTAssertEqual(app.staticTexts["service.gpsStatus"].label, "GPS recovery has not been confirmed.")
        XCTAssertEqual(app.alerts.count, 0)
        #endif
    }

    func testServiceFailureKeepsRepairAvailableWithoutGPSPrompt() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This failure-path test requires the simulator deviceRequired adapter; device clear is verified separately.")
        #else
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "YES", "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
        app.launch()
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "01-map-stopped")
        app.buttons["map.settings"].tap()
        let start = app.buttons["service.primary"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertTrue(app.otherElements["service.error"].waitForExistence(timeout: 5)
            || app.staticTexts["service.error"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["service.restoreGPS"].isEnabled)
        XCTAssertTrue(app.buttons["service.resetTunnel"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "01-settings-device-required")
        app.buttons["service.restoreGPS"].tap()
        XCTAssertTrue(app.buttons["service.primary"].isEnabled)
        XCTAssertTrue(app.buttons["service.resetTunnel"].isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        #endif
    }

    func testLargeEnglishDarkSettingsKeepActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
        app.buttons["map.settings"].tap()
        XCTAssertTrue(app.buttons["service.primary"].waitForExistence(timeout: 5))
        if !app.buttons["service.resetTunnel"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["service.restoreGPS"].isHittable)
        XCTAssertTrue(app.buttons["service.resetTunnel"].isHittable)
        attach(app, name: "01-settings-english-large-dark")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
