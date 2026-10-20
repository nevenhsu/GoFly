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
        wait(app.buttons["route.clearImported"])
        snapshot(app, "step-4-imported-\(sample)")
        app.selectGoFlyMode("joystick")
        wait(app.buttons["joystick.setOrigin"])
        snapshot(app, "step-5-joystick-origin-\(sample)")
        app.buttons["map.settings"].tap()
        wait(app.buttons["settings.languageAndAppearance"])
        snapshot(app, "step-8-settings-\(sample)")
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
