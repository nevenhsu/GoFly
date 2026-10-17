import XCTest

@MainActor
final class GoFlyServiceUITests: XCTestCase {
    func testServiceFailureKeepsRepairAvailableWithoutGPSPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"]
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
    }

    func testLargeEnglishDarkSettingsKeepActionsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
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
