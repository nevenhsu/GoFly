import XCTest

/// Visual acceptance only: the three requested rendering samples, without
/// multiplying operation states, languages, permissions, or device conditions.
@MainActor
final class GoFlyRedesignScreenshots: XCTestCase {
    func testCaptureRedesignedScreens() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual samples run on the simulator.")
        #else
        continueAfterFailure = false
        captureScreens(style: "light", largeText: false)
        captureScreens(style: "dark", largeText: false)
        captureScreens(style: "light", largeText: true)
        #endif
    }

    func testCaptureOnboardingScreens() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual samples run on the simulator.")
        #else
        continueAfterFailure = false
        for sample in ["light", "dark", "axxxl"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-session-store", UUID().uuidString,
                "-gofly.onboarding.complete", "NO", "-gofly-ui-unreachable",
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-gofly-ui-preferences-appearance", sample == "dark" ? "dark" : "light",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if sample == "axxxl" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            wait(app.buttons["onboarding.welcome.next"])
            snapshot(app, "precision-onboarding-welcome-\(sample)")
            app.buttons["onboarding.welcome.next"].tap()
            wait(app.buttons["onboarding.location.skip"])
            snapshot(app, "precision-onboarding-location-\(sample)")
            app.buttons["onboarding.location.skip"].tap()
            wait(app.buttons["onboarding.vpn.next"])
            snapshot(app, "precision-onboarding-vpn-\(sample)")
            wait(app.descendants(matching: .any)["onboarding.vpn.failure"])
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.3)
            let help = app.buttons["onboarding.vpn.help.open"]
            wait(help)
            help.tap()
            wait(app.staticTexts["onboarding.vpn.help.step1"])
            Thread.sleep(forTimeInterval: 0.45)
            snapshot(app, "precision-vpn-help-\(sample)")
            app.terminate()
        }
        #endif
    }

    func testExecutionControlsAtAccessibilitySize() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Visual samples run on the simulator.")
        #else
        for sample in ["light", "dark", "axxxl"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "-gofly-ui-gallery",
                "-gofly-ui-preferences-store", UUID().uuidString,
                "-gofly-ui-preferences-language", "zh-Hant",
                "-gofly-ui-preferences-appearance", sample == "dark" ? "dark" : "light",
                "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
            ]
            if sample == "axxxl" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            if sample == "axxxl" {
                let shuffle = app.buttons["joystick.randomDestination"]
                for _ in 0..<10 where !shuffle.isHittable { app.swipeUp() }
                wait(shuffle)
                XCTAssertTrue(shuffle.isHittable)
                XCTAssertGreaterThanOrEqual(shuffle.frame.height, 44)
                snapshot(app, "precision-execution-destination-axxxl")
                let pause = app.buttons["execution.pause"]
                for _ in 0..<8 where !pause.isHittable { app.swipeUp() }
                wait(pause)
                XCTAssertTrue(pause.isHittable)
                XCTAssertGreaterThanOrEqual(pause.frame.height, 44)
                snapshot(app, "precision-execution-controls-axxxl")
            }
            let pad = app.descendants(matching: .any)["joystick.pad"]
            for _ in 0..<10 where !pad.isHittable { app.swipeUp() }
            wait(pad)
            Thread.sleep(forTimeInterval: 0.3)
            snapshot(app, "step-5-joystick-pad-\(sample)")
            app.terminate()
        }
        #endif
    }

    private func captureScreens(style: String, largeText: Bool) {
        let sample = largeText ? "axxxl" : style
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-preferences-appearance", style,
            "-gofly-ui-gpx-file", "valid",
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        wait(app.buttons["map.searchBar"])
        snapshot(app, "step-3-map-\(sample)")
        app.buttons["map.sheet.grabber"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        snapshot(app, "step-3-collapsed-\(sample)")
        app.buttons["map.sheet.grabber"].tap()
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        wait(query)
        query.tap()
        query.typeText("25.0478, 121.5170")
        let result = app.buttons["search.result.25.047800, 121.517000"]
        wait(result)
        snapshot(app, "step-3-search-\(sample)")
        result.tap()
        wait(app.buttons["placeDetails.go"])
        snapshot(app, "step-3-place-\(sample)")
        app.buttons["placeDetails.favorite"].tap()
        app.buttons["placeDetails.dismiss"].tap()
        app.buttons["favorites.open"].tap()
        wait(app.textFields["favorites.search"])
        snapshot(app, "step-6-favorites-\(sample)")
        app.buttons["favorites.edit.25.047800, 121.517000"].tap()
        wait(app.textFields["favorites.editor.label"])
        snapshot(app, "precision-favorite-editor-\(sample)")
        app.buttons["favorites.editor.cancel"].tap()
        wait(app.buttons["favorites.select"])
        app.buttons["favorites.select"].tap()
        app.buttons["favorites.star.25.047800, 121.517000"].tap()
        snapshot(app, "precision-favorite-selection-\(sample)")
        app.buttons["favorites.dismiss"].tap()
        wait(app.buttons["favorites.select"])
        app.buttons["favorites.dismiss"].tap()
        app.selectGoFlyMode("route")
        wait(app.buttons["route.importedRoutes"])
        snapshot(app, "step-4-route-\(sample)")
        app.buttons["route.importedRoutes"].tap()
        wait(app.buttons["imports.import"])
        app.buttons["imports.import"].tap()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'imports.record.'")).firstMatch
        wait(record)
        snapshot(app, "step-4-folder-\(sample)")
        record.tap()
        let load = app.buttons.matching(identifier: "imports.load").firstMatch
        wait(load)
        load.tap()
        wait(app.buttons["route.start"])
        snapshot(app, "step-4-imported-\(sample)")
        app.selectGoFlyMode("joystick")
        wait(app.buttons["joystick.wander"])
        snapshot(app, "step-5-joystick-origin-\(sample)")
        app.buttons["map.settings"].tap()
        wait(app.buttons["settings.language"])
        snapshot(app, "step-8-settings-\(sample)")
        let pageRootIdentifiers: [String: String] = [
            "location": "settings.location.page",
            "vpn": "settings.vpn.page",
            "background": "settings.background.page",
            "language": "settings.language.page",
            "appearance": "settings.appearance.page",
            "device": "settings.device.page"
        ]
        for page in ["location", "vpn", "background", "language", "appearance", "device"] {
            let link = app.buttons["settings.\(page)"]
            for _ in 0..<6 where !link.isHittable { app.swipeUp() }
            wait(link)
            link.tap()
            if let rootID = pageRootIdentifiers[page] {
                wait(app.descendants(matching: .any)[rootID])
            }
            Thread.sleep(forTimeInterval: 0.45)
            snapshot(app, "precision-settings-\(page)-\(sample)")
            app.navigationBars.buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.35)
        }
        app.terminate()
    }

    private func wait(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
    }

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
