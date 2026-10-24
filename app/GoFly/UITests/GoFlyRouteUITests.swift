import XCTest

@MainActor
final class GoFlyRouteUITests: XCTestCase {
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
}
