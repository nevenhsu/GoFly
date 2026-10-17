import XCTest

@MainActor
final class GoFlySearchUITests: XCTestCase {
    func testCoordinateValidationViewportDetailsAndFailedGoPreserveCandidate() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator UI verifies candidate flow; physical device checks are deferred to the final batch.")
        #else
        let app = makeApp()
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        let pin = app.buttons["map.candidate.pin"]
        let go = app.buttons["map.candidate.go"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(go.isEnabled)
        assertCentered(app)
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")

        replace(query, with: "25.0, 181.0")
        XCTAssertTrue(app.staticTexts["search.inputError"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["search.inputError"].label, "Longitude must be between −180° and 180°.")
        // Real typing first produces the valid prefix 25.0, 18; the next digit
        // makes longitude invalid and must retain that last valid candidate.
        XCTAssertEqual(pin.value as? String, "25.000000, 18.000000")
        XCTAssertFalse(go.isEnabled)

        replace(query, with: "25.0330, 121.5654")
        XCTAssertTrue(go.isEnabled)
        assertCentered(app)
        dismissKeyboard(app)
        assertCentered(app)
        pin.tap()
        XCTAssertTrue(app.navigationBars["Place details"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.candidate.go"].isHittable)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        app.buttons["placeDetails.dismiss"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        go.tap()
        let error = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("prepared physical iPhone"))
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(go.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "03-coordinate-failed-go-preserves-candidate")
        #endif
    }

    func testMapTapAndLargeTextKeepCandidateInMeasuredViewport() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator UI verifies viewport geometry; physical checks are deferred to the final batch.")
        #else
        let app = makeApp()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                                "-AppleInterfaceStyle", "Dark"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        assertCentered(app)
        attach(app, name: "03-coordinate-large-dark-keyboard-centered")
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(query.frame.maxY, keyboard.frame.minY + 2,
                                     "Search input must stay above keyboard. Query: \(query.frame), keyboard: \(keyboard.frame)")
        }
        dismissKeyboard(app)
        assertCentered(app)
        let before = app.buttons["map.candidate.pin"].value as? String
        let values = metrics(app)
        let tap = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: values[0] + min(80, values[4] / 4), dy: values[1]))
        tap.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (app.buttons["map.candidate.pin"].value as? String) != before
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        assertCentered(app)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "03-map-tap-large-dark-centered")
        #endif
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }

    private func metrics(_ app: XCUIApplication) -> [Double] {
        app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
    }

    private func assertCentered(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard app.staticTexts["map.viewportMetrics"].exists else { return false }
            let values = self.metrics(app)
            return values.count == 6 && values[4] > 1 && values[5] > 1
                && abs(values[0] - values[2]) < 3 && abs(values[1] - values[3]) < 3
        }, object: nil)
        let result = XCTWaiter.wait(for: [centered], timeout: 8)
        let actual = app.staticTexts["map.viewportMetrics"].label
        XCTAssertEqual(result, .completed,
                       "Actual viewport center/candidate/size: \(actual)",
                       file: file, line: line)
        let values = metrics(app)
        if values.count == 6 {
            let visible = CGRect(x: values[0] - values[4] / 2, y: values[1] - values[5] / 2,
                                 width: values[4], height: values[5]).insetBy(dx: -3, dy: -3)
            XCTAssertTrue(visible.contains(app.buttons["map.candidate.go"].frame),
                          "Go must remain inside the measured visible map, including with the keyboard open.", file: file, line: line)
            XCTAssertTrue(app.buttons["map.candidate.pin"].isHittable, file: file, line: line)
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
