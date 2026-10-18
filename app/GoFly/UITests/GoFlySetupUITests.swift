import XCTest

@MainActor
final class GoFlySetupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMalformedFormalSetupLocksBeforeNormalRuntime() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Formal setup UI fixtures are scoped to the Debug simulator app.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-setup-store", UUID().uuidString,
            "-gofly-ui-setup-fixture", "malformed-input",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly.onboarding.complete", "NO"
        ]
        app.launch()

        let blocked = app.descendants(matching: .any)["setup.blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["map.settings"].exists)
        XCTAssertFalse(app.buttons["onboarding.welcome.next"].exists)
        XCTAssertFalse(app.buttons["map.serviceControl"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "setup-malformed-input-locked-before-runtime")
        #endif
    }

    func testReadbackRequestWithoutProfileLocksBeforeNormalRuntime() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Formal setup UI fixtures are scoped to the Debug simulator app.")
        #else
        let app = launch(
            fixture: "request-without-profile",
            language: nil
        )
        let blocked = app.descendants(matching: .any)["setup.blocked"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["map.settings"].exists)
        XCTAssertFalse(app.buttons["onboarding.welcome.next"].exists)
        XCTAssertFalse(app.buttons["map.serviceControl"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "setup-request-without-profile-locked-before-runtime")
        #endif
    }

    func testOrdinaryStartupWithoutFormalSetupKeepsNormalRuntime() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator startup coverage is scoped to the Debug simulator app.")
        #else
        let app = launch(fixture: nil, language: nil)
        XCTAssertTrue(app.buttons["onboarding.welcome.next"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["setup.blocked"].exists)
        #endif
    }

    func testFormalLockSmokeAcrossSupportedLocales() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Formal setup UI fixtures are scoped to the Debug simulator app.")
        #else
        let locales: [(String, String, String)] = [
            ("en", "en_US", "Setup is required"),
            ("zh-Hans", "zh_CN", "需要完成设置"),
            ("zh-Hant", "zh_TW", "需要完成設定")
        ]
        for (language, locale, title) in locales {
            let app = launch(
                fixture: "malformed-input",
                language: (language, locale),
                maximumText: true
            )
            XCTAssertTrue(app.descendants(matching: .any)["setup.blocked"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            let retry = app.buttons["setup.retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 5))
            XCTAssertTrue(retry.isHittable)
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
            XCTAssertFalse(app.buttons["map.settings"].exists)
            XCTAssertFalse(app.buttons["map.serviceControl"].exists)
            attach(app, name: "setup-locked-\(language)")
            app.terminate()
        }
        #endif
    }

    private func launch(
        fixture: String?,
        language: (String, String)?,
        maximumText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-gofly-ui-setup-store", UUID().uuidString,
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly.onboarding.complete", "NO"
        ]
        if let fixture {
            arguments += ["-gofly-ui-setup-fixture", fixture]
        }
        if let (language, locale) = language {
            arguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        }
        if maximumText {
            arguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
