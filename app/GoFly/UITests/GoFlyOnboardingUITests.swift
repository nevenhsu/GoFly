import XCTest

@MainActor
final class GoFlyOnboardingUITests: XCTestCase {
    func testRealLocationPermissionDenialContinuesToVPN() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This permission reset is scoped to the simulator app; physical permission flow is verified separately.")
        #else
        let app = onboardingApp()
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.welcome.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.welcome.next"].tap()
        let allow = app.buttons["onboarding.location.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        guard prompt.waitForExistence(timeout: 5) else {
            attach(springboard, name: "02-location-permission-prompt-missing")
            XCTFail("Expected an actual system location authorization prompt after resetting this simulator app's location permission.")
            return
        }
        attach(springboard, name: "02-location-system-permission")
        let deny = prompt.buttons.matching(NSPredicate(
            format: "label IN %@", ["Don’t Allow", "Don't Allow", "不允許", "不允许"]
        )).firstMatch
        guard deny.exists else {
            XCTFail("The system prompt has no recognized denial action. Actual buttons: \(prompt.buttons.allElementsBoundByIndex.map(\.label))")
            return
        }
        deny.tap()

        let next = app.buttons["onboarding.vpn.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(app.staticTexts["onboarding.vpn.failure"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.settings"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "02-location-denied-vpn-still-available")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        XCTAssertEqual(allow.label, "Next")
        XCTAssertEqual(app.alerts.count, 0)
        #endif
    }

    func testSkipLocationRequiresReachableVPNAndBackKeepsFlow() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The bounded unavailable-endpoint fixture is only available in the Debug simulator app.")
        #else
        let app = onboardingApp()
        app.launch()
        let welcome = app.buttons["onboarding.welcome.next"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["map.settings"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        welcome.tap()

        let skip = app.buttons["onboarding.location.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.location.allow"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        skip.tap()

        let next = app.buttons["onboarding.vpn.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        let failure = app.staticTexts["onboarding.vpn.failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.vpn.status"].label, "Not connected")
        XCTAssertFalse(app.buttons["map.serviceControl"].exists)
        XCTAssertFalse(app.buttons["onboarding.location.skip"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "02-vpn-unavailable-next-disabled")

        app.buttons["onboarding.vpn.check"].tap()
        XCTAssertFalse(next.isEnabled)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(welcome.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.settings"].exists)
        #endif
    }

    func testLargeTraditionalChineseDarkVPNKeepsRequiredActionsReachable() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("The bounded unavailable-endpoint fixture is only available in the Debug simulator app.")
        #else
        let app = onboardingApp(language: "zh-Hant", locale: "zh_TW")
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.welcome.next"].waitForExistence(timeout: 10))
        app.buttons["onboarding.welcome.next"].tap()
        app.buttons["onboarding.location.skip"].tap()
        let next = app.buttons["onboarding.vpn.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(app.buttons["onboarding.vpn.check"].isHittable)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "02-vpn-traditional-chinese-large-dark")
        #endif
    }

    private func onboardingApp(language: String = "en", locale: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "NO", "-gofly-ui-unreachable",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
