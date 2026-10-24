import XCTest

@MainActor
final class GoFlyRouteUITests: XCTestCase {
    private let first = "25.047800, 121.517000"
    private let second = "25.033000, 121.565400"
    private let waypoint = "25.040000, 121.530000"

    func testTwoPointRouteConfirmsDestinationAndEnablesStart() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
        XCTAssertFalse(app.buttons["route.start"].isEnabled)
        setNode(app, id: "route.node.start", coordinate: first)
        setNode(app, id: "route.node.destination", coordinate: second)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, second)
        waitEnabled(app.buttons["route.start"])
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testDestinationPickerShowsRoleChipAndFavoritesButton() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        app.buttons["route.node.destination"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["search.role"].waitForExistence(timeout: 5))
        let favButton = app.buttons["search.favorites"]
        XCTAssertTrue(favButton.waitForExistence(timeout: 5))
        favButton.tap()
        XCTAssertTrue(app.buttons["favorites.dismiss"].waitForExistence(timeout: 5))
        app.buttons["favorites.dismiss"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["search.role"].waitForExistence(timeout: 5))
    }

    func testWaypointIsInsertedBeforeTheDestination() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        setNode(app, id: "route.node.start", coordinate: first)
        setNode(app, id: "route.node.destination", coordinate: second)
        addNode(app, coordinate: waypoint)
        XCTAssertEqual(app.buttons["route.node.waypoint.1"].value as? String, waypoint)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, second)
        waitEnabled(app.buttons["route.start"])
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testRoundTripToggleSurvivesNodeEditing() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        let roundTrip = app.descendants(matching: .any)["route.roundTrip"]
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        XCTAssertEqual(roundTrip.value as? String, "0")
        roundTrip.tap()
        XCTAssertEqual(roundTrip.value as? String, "1")
        addNode(app, coordinate: second)
        XCTAssertEqual(roundTrip.value as? String, "1")
    }

    func testGPXImportLoadsAFullRoutePreview() throws {
        try simulatorOnly()
        let app = makeApp(gpx: "valid")
        app.launch()
        openRoute(app)
        let imported = app.buttons["route.importedRoutes"]
        XCTAssertTrue(imported.waitForExistence(timeout: 5))
        imported.tap()
        let importButton = app.buttons["imports.import"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(importButton.isEnabled)
        importButton.tap()
        let record = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "imports.record.")
        ).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 8))
        record.tap()
        let load = app.buttons.matching(identifier: "imports.load").firstMatch
        XCTAssertTrue(load.waitForExistence(timeout: 5))
        XCTAssertTrue(load.isEnabled)
        load.tap()
        let summary = app.descendants(matching: .any)["route.importedSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("valid.gpx"))
        waitEnabled(app.buttons["route.start"])
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Route UI smoke tests use isolated simulator stores; physical checks are deferred.")
        #endif
    }

    private func makeApp(gpx: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        if let gpx { arguments += ["-gofly-ui-gpx-file", gpx] }
        app.launchArguments = arguments
        return app
    }

    private func openRoute(_ app: XCUIApplication) {
        app.selectGoFlyMode("route")
        XCTAssertTrue(app.descendants(matching: .any)["route.panel"].waitForExistence(timeout: 5))
    }

    private func openDetails(_ app: XCUIApplication) {
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["route.speed"].waitForExistence(timeout: 5))
    }

    private func waitEnabled(_ element: XCUIElement, timeout: TimeInterval = 8) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"),
                                              object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed)
    }

    private func setNode(_ app: XCUIApplication, id: String, coordinate: String) {
        if app.buttons[id].exists { app.buttons[id].tap() }
        else { app.buttons["route.addNode"].tap() }
        typeCoordinate(app, coordinate)
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
    }

    private func addNode(_ app: XCUIApplication, coordinate: String) {
        app.buttons["route.addNode"].tap()
        typeCoordinate(app, coordinate)
    }

    private func typeCoordinate(_ app: XCUIApplication, _ coordinate: String) {
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        query.tap()
        let old = query.value as? String ?? ""
        let count = old == "Search places, addresses or coordinates" ? 0 : old.count
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + coordinate)
        let result = app.buttons["search.result.\(coordinate)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
    }

}
