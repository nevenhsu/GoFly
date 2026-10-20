import XCTest

@MainActor
final class GoFlyOnboardingUITests: XCTestCase {
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
        let failure = app.descendants(matching: .any)["onboarding.vpn.failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.vpn.status"].label, "Not reachable")
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.vpn.failureDetail"].waitForExistence(timeout: 5))
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
