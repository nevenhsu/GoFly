import XCTest

/// R4 / D9: clearing a route endpoint shows the undoable snackbar above the sheet.
final class GoFlyRouteUndoUITests: GoFlyRouteModeTestCase {
    private func removes(_ app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route.delete.'"))
    }

    func testUndoRestoresTheClearedStartAboveTheSheet() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            app.selectGoFlyMode("route")
            let sheet = element(app, "map.sheet")
            Thread.sleep(forTimeInterval: 0.6)
            removes(app).element(boundBy: 0).tap()
            XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點")

            let undo = element(app, "snackbar.action")
            XCTAssertEqual(undo.label, "復原")
            XCTAssertTrue(app.staticTexts["已清空路線地點"].waitForExistence(timeout: 2))
            // The snackbar is 52 pt high with a 32 pt action centered in it.
            XCTAssertEqual(sheet.frame.minY - (undo.frame.midY + 26), 12, accuracy: 2.5, "12 pt above the sheet")
            evidence(app, task: "R4", name: "d9-undo-\(appearance)")

            undo.tap()
            XCTAssertEqual(element(app, "route.node.start").value as? String, "目前位置", "undo restores the original value")
            app.terminate()
        }
    }

    func testSnackbarDisappearsAfterAboutFiveSeconds() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        Thread.sleep(forTimeInterval: 0.6)
        removes(app).element(boundBy: 0).tap()
        let undo = element(app, "snackbar.action")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(undo.exists, "still there after 3 s")
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: undo)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點", "timeout keeps the cleared state")
    }

    func testConsecutiveClearsOnlyUndoTheLatest() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        Thread.sleep(forTimeInterval: 0.6)
        removes(app).element(boundBy: 0).tap()
        XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點")
        XCTAssertFalse(removes(app).element(boundBy: 1).isEnabled, "the empty destination has nothing to clear")
    }
}
