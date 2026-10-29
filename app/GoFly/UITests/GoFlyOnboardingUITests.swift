import XCTest

@MainActor
final class GoFlyOnboardingUITests: XCTestCase {
    func testVPNGuideBackAutomaticallyRechecksAndKeepsOnboardingFlow() throws {
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

        let check = app.buttons["onboarding.vpn.check"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        let failure = app.descendants(matching: .any)["onboarding.vpn.failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.serviceControl"].exists)
        XCTAssertFalse(app.buttons["onboarding.location.skip"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "02-vpn-unavailable-next-disabled")

        app.buttons["onboarding.vpn.help.open"].tap()
        XCTAssertTrue(app.buttons["onboarding.vpn.help.step1.action"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.vpn.help.step2.action"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.vpn.help.step3"].exists)
        XCTAssertFalse(app.buttons["onboarding.vpn.help.openSettings"].exists)
        XCTAssertFalse(app.buttons["onboarding.vpn.help.openVPN"].exists)
        let back = app.descendants(matching: .any)["onboarding.vpn.help.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(failure.waitForExistence(timeout: 5), "returning from R05 should automatically check the VPN again")
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertFalse(app.buttons["onboarding.location.skip"].exists)
        XCTAssertFalse(app.buttons["map.settings"].exists)
        #endif
    }

    func testSuccessfulVPNCheckAutomaticallyOpensCollapsedB1MapInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let screenshots = repositoryRoot.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)

        for appearance in ["light", "dark"] {
            let app = successfulOnboardingApp(appearance: appearance)
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["figma.fixture.B1"].waitForExistence(timeout: 15),
                          "A successful VPN check should open B1 without a second tap.")
            let sheet = app.descendants(matching: .any)["map.sheet"]
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["map.bottomBar"].exists)
            XCTAssertTrue(app.buttons["mode.teleport"].isSelected)
            XCTAssertLessThan(sheet.frame.height, 200,
                              "The first map after onboarding should use the collapsed sheet.")

            let screenshot = app.screenshot()
            try screenshot.pngRepresentation.write(
                to: screenshots.appendingPathComponent("R04-auto-B1-\(appearance).png"), options: .atomic)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "R04-auto-B1-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        #endif
    }

    func testR04TypographyAndPositionMatchFigmaInBothAppearances() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Figma frame fixtures run only in the iOS Simulator.")
        #else
        let screenshots = repositoryRoot.appendingPathComponent("work/gofly-ios-figma04/screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)

        for appearance in ["light", "dark"] {
            let app = staticVPNFrameApp(appearance: appearance)
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["figma.fixture.R04"].waitForExistence(timeout: 15))
            let title = app.staticTexts["onboarding.vpn.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertLessThan(title.frame.minY, 150, "R04 heading should align with Figma's y=130 pt position.")
            XCTAssertLessThan(title.frame.height, 42, "R04 heading should use the 28 pt display token.")
            XCTAssertTrue(app.buttons["onboarding.vpn.check"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["onboarding.vpn.failure"].exists)

            let screenshot = app.screenshot()
            try screenshot.pngRepresentation.write(
                to: screenshots.appendingPathComponent("R04-\(appearance).png"), options: .atomic)
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "R04-\(appearance)-typography"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        #endif
    }

    private func onboardingApp(language: String = "en", locale: String = "en_US") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "NO", "-gofly-ui-unreachable",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        return app
    }

    private func successfulOnboardingApp(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-frame", "R04",
            "-gofly-ui-vpn-reachable",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-appearance", appearance,
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        return app
    }

    private func staticVPNFrameApp(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-frame", "R04",
            "-gofly-ui-vpn-static",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-appearance", appearance,
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        return app
    }

    private var repositoryRoot: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
