import XCTest

@MainActor
final class GoFlySearchUITests: XCTestCase {
    private let coordinate = "25.047800, 121.517000"

    func testCoordinateSelectionAndFailedGoPreserveCandidate() throws {
        try simulatorOnly()
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
        XCTAssertEqual(pin.value as? String, coordinate)

        replace(query, with: "25.0, 181.0")
        XCTAssertTrue(app.staticTexts["search.inputError"].waitForExistence(timeout: 5))
        XCTAssertFalse(go.isEnabled)
        XCTAssertEqual(pin.value as? String, "25.000000, 18.000000")

        replace(query, with: "25.0330, 121.5654")
        XCTAssertTrue(go.isEnabled)
        dismissKeyboard(app)
        go.tap()
        let error = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("prepared physical iPhone"))
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(go.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testFavoritePersistsAcrossRelaunch() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        dismissKeyboard(app)
        let star = app.buttons["search.favorite.\(coordinate)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        XCTAssertEqual(star.value as? String, "Favorite")

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
