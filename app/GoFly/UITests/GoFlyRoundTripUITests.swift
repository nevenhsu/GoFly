import XCTest

@MainActor
final class GoFlyRoundTripUITests: XCTestCase {
    func testRoundTripOptionSurvivesNodeEditingPlanningCancellationAndFailure() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-route-draft-count", "2", "-gofly-ui-route-planning-delay"]
        app.launch()
        openRoute(app)
        XCTAssertFalse(app.descendants(matching: .any)["route.roundTrip"].exists,
                       "The initial route panel keeps options inside details.")
        openDetails(app)
        let option = app.descendants(matching: .any)["route.roundTrip"]
        XCTAssertEqual(option.value as? String, "0")
        assertTarget(option, in: app)
        option.tap()
        XCTAssertEqual(option.value as? String, "1")
        app.buttons["route.details.back"].tap()
        app.buttons["route.node.start"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        query.typeText("25.0478, 121.5170")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        app.buttons["route.picker.confirm"].tap()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
        openDetails(app)
        XCTAssertEqual(option.value as? String, "1")
        app.buttons["route.details.back"].tap()
        app.buttons["route.start"].tap()
        let cancel = app.buttons["route.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.details"].exists)
        XCTAssertFalse(option.exists, "Planning must not expose execution or editing options.")
        cancel.tap()
        XCTAssertTrue(app.buttons["route.details"].waitForExistence(timeout: 5))
        openDetails(app)
        XCTAssertEqual(option.value as? String, "1")
        app.buttons["route.details.back"].tap()
        app.buttons["route.start"].tap()
        let error = app.descendants(matching: .any)["route.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("walking route could not be planned"))
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        XCTAssertFalse(app.buttons["route.direction"].exists)
        XCTAssertFalse(app.staticTexts["route.position.value"].exists)
        openDetails(app)
        XCTAssertEqual(option.value as? String, "1")
        attach(app, "08-round-trip-retained-after-real-planning-failure")
        option.tap()
        XCTAssertEqual(option.value as? String, "0")
        app.buttons["route.details.back"].tap()
        openDetails(app)
        XCTAssertEqual(option.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testAllLocalizedLargeDarkDetailsKeepRoundTripSpeedAndReturnReachable() throws {
        try simulatorOnly()
        for language in ["en", "zh-Hant", "zh-Hans"] {
            let app = makeApp(language: language)
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            openRoute(app)
            openDetails(app)
            let option = app.descendants(matching: .any)["route.roundTrip"]
            let expected = language == "en" ? "Round trip" : (language == "zh-Hant" ? "來回走動" : "来回走动")
            XCTAssertEqual(option.label, expected)
            assertTarget(option, in: app)
            let scroll = app.scrollViews["route.details.content"]
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.detailsViewport(app).contains(option.frame)
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                           "Full checkbox \(option.frame) must fit actual details viewport \(detailsViewport(app)).")
            option.tap()
            XCTAssertEqual(option.value as? String, "1")
            let speed = app.sliders["route.speed"]
            for _ in 0..<3 where !speed.isHittable { scroll.swipeUp() }
            XCTAssertTrue(speed.isHittable)
            let back = app.buttons["route.details.back"]
            assertTarget(back, in: app)
            attach(app, "08-round-trip-\(language)-max-dark-details")
            back.tap()
            openDetails(app)
            XCTAssertEqual(option.value as? String, "1")
            app.terminate()
        }
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Round-trip UI tests verify real editing and failed planning in the simulator. Physical movement checks are deferred.")
        #endif
    }

    private func makeApp(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_TW"]
        return app
    }

    private func openRoute(_ app: XCUIApplication) {
        app.selectGoFlyMode("route")
        XCTAssertTrue(app.buttons["route.details"].waitForExistence(timeout: 5))
    }

    private func openDetails(_ app: XCUIApplication) {
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["route.roundTrip"].waitForExistence(timeout: 5))
    }

    private func detailsViewport(_ app: XCUIApplication) -> CGRect {
        let values = app.staticTexts["route.details.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private func assertTarget(_ target: XCUIElement, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(target.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(target.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(target.frame.height, 44, file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame), file: file, line: line)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
