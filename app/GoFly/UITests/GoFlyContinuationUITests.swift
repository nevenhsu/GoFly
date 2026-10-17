import XCTest

@MainActor
final class GoFlyContinuationUITests: XCTestCase {
    func testSettingsShowsReachableIdleContinuationStateAndDescription() {
        let app = launch(language: "en", locale: "en_US")
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))

        app.buttons["map.settings"].tap()

        let card = app.otherElements["background.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        attachSettingsScreenshot(app, name: "continuation-settings-en")
        XCTAssertEqual(app.staticTexts["background.status"].label, "Idle")
        XCTAssertTrue(app.staticTexts["background.description"].exists)
        XCTAssertTrue(app.staticTexts["background.systemDecides"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testLocalizedLargeTextKeepsContinuationCopyAccessible() {
        let languages = [
            ("en", "en_US", "Idle"),
            ("zh-Hant", "zh_TW", "待命"),
            ("zh-Hans", "zh_CN", "待机")
        ]

        for (language, locale, expectedStatus) in languages {
            let app = launch(
                language: language, locale: locale,
                extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            )
            XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
            app.buttons["map.settings"].tap()

            let card = app.otherElements["background.card"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["background.status"].label, expectedStatus)

            for identifier in [
                "background.title", "background.status", "background.description", "background.systemDecides"
            ] {
                let element = app.staticTexts[identifier]
                XCTAssertTrue(element.waitForExistence(timeout: 5), identifier)
                scrollIntoView(element, in: app)
                XCTAssertTrue(element.isHittable, identifier)
                XCTAssertGreaterThan(element.frame.width, 0, identifier)
                XCTAssertGreaterThan(element.frame.height, 0, identifier)
            }

            attachSettingsScreenshot(app, name: "continuation-settings-\(language)")
            XCTAssertEqual(app.alerts.count, 0)
            app.terminate()
        }
    }

    private func launch(language: String, locale: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale
        ] + extraArguments
        app.launch()
        return app
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func attachSettingsScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
