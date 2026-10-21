import XCTest

@MainActor
final class GoFlySearchUITests: XCTestCase {
    private let coordinate = "25.047800, 121.517000"

    func testCoordinateSelectionAndFailedGoPreserveCandidate() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0, 181.0")
        XCTAssertTrue(app.staticTexts["search.inputError.title"].waitForExistence(timeout: 5))
        // Documented rule: invalid input keeps the previous valid candidate but
        // offers no new coordinate result and never sends a point.
        XCTAssertFalse(app.buttons["search.result.25.000000, 18.000000"].exists)
        XCTAssertEqual(query.value as? String, "25.0, 181.0")
        replace(query, with: "25.0478, 121.5170")
        let result = app.buttons["search.result.\(coordinate)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let pin = app.buttons["map.candidate.pin"]
        let go = app.buttons["map.candidate.go"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(go.isEnabled)
        XCTAssertTrue(app.buttons["placeDetails.go"].isEnabled)
        go.tap()
        let error = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("prepared physical iPhone"))
        XCTAssertTrue(pin.exists)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFavoritePersistsAcrossRelaunch() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        dismissKeyboard(app)
        let result = app.buttons["search.result.\(coordinate)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let star = app.buttons["placeDetails.favorite"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()

        app.terminate()
        app.launch()
        app.buttons["favorites.open"].tap()
        let row = app.buttons["favorites.place.\(coordinate)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, coordinate)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Simulator UI covers the candidate flow; physical checks are deferred.")
        #endif
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
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
}
