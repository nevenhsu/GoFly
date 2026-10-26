import XCTest

/// Clearing an endpoint or deleting a stop is silent: the emptied row is the feedback, no snackbar.
final class GoFlyRouteUndoUITests: GoFlyRouteModeTestCase {
    private func removes(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route.delete.'"))
    }

    func testClearingTheStartShowsNoSnackbar() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        Thread.sleep(forTimeInterval: 0.6)
        removes(app).element(boundBy: 0).tap()
        XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點")
        XCTAssertFalse(app.descendants(matching: .any)["snackbar.action"].waitForExistence(timeout: 1.5))
        XCTAssertFalse(app.staticTexts["已清空路線地點"].exists)
    }

    func testEmptyDestinationHasNothingToClear() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        Thread.sleep(forTimeInterval: 0.6)
        removes(app).element(boundBy: 0).tap()
        XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點")
        XCTAssertFalse(removes(app).element(boundBy: 1).isEnabled, "the empty destination has nothing to clear")
    }
}
