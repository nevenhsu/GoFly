import XCTest

/// F1 / F2: the favorite routes page is a full page with a bottom search section; in multi-select the
/// delete button sits above that section, and the undo snackbar is 12 pt above it (D19, D21, D22).
final class GoFlyFavoriteRoutesPageUITests: GoFlyRouteModeTestCase {
    private func fill(_ app: XCUIApplication, row: String, coordinate: String) {
        element(app, row).tap()
        app.buttons["map.searchBar"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText(coordinate)
        let result = app.buttons["search.result.\(coordinate)"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertEqual(element(app, row).value as? String, coordinate)
    }

    private func saveRoute(_ app: XCUIApplication) {
        app.selectGoFlyMode("route")
        fill(app, row: "route.node.start", coordinate: "25.047800, 121.517000")
        fill(app, row: "route.node.destination", coordinate: "25.033000, 121.565400")
        element(app, "route.favorite.toggle").tap()
        let label = app.textFields["favoriteRoutes.save.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertEqual(label.placeholderValue, "路線名稱")
        let save = element(app, "favoriteRoutes.save.confirm")
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled, "Save is enabled without a typed label")
        save.tap()
        XCTAssertTrue(app.buttons["route.favoriteRoutes"].waitForExistence(timeout: 8))
    }

    func testPageLayoutDeleteButtonAndUndoSnackbar() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            saveRoute(app)
            element(app, "route.favoriteRoutes").tap()
            let firstRecord = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "favoriteRoutes.record.")).firstMatch
            XCTAssertTrue(firstRecord.waitForExistence(timeout: 5), "the empty-label favorite is saved")
            XCTAssertNotNil(firstRecord.label.range(
                of: #"\d{1,2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}"#,
                options: .regularExpression), "empty labels persist the generated date/time fallback")

            let search = element(app, "favoriteRoutes.search")
            let back = element(app, "favoriteRoutes.dismiss")
            XCTAssertTrue(back.label.contains("路線"), "back label names the previous screen (D19), got \(back.label)")
            let card = app.descendants(matching: .any)["favoriteRoutes.card"]
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertEqual(card.frame.minX, 16, accuracy: 2)
            XCTAssertEqual(card.frame.width, app.windows.firstMatch.frame.width - 32, accuracy: 2)
            XCTAssertGreaterThanOrEqual(card.frame.height, 64)
            XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.searchPaste"].exists)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            // The text field is centered in the 48 pt field container.
            let fieldTop = search.frame.midY - 24, fieldBottom = search.frame.midY + 24
            XCTAssertEqual(app.frame.maxY - fieldBottom, 28 + 34, accuracy: 4, "28 pt below the field plus the home indicator area")
            evidence(app, task: "F1", name: "d19-list-\(appearance)")

            let select = element(app, "favoriteRoutes.select")
            XCTAssertEqual(select.label, "選取")
            select.tap()
            let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'favoriteRoutes.record.'")).element(boundBy: 0)
            XCTAssertTrue(record.waitForExistence(timeout: 5))
            record.tap()
            XCTAssertTrue(app.staticTexts["已選取 1 項"].waitForExistence(timeout: 3))
            let delete = element(app, "favoriteRoutes.deleteSelected")
            XCTAssertEqual(delete.frame.height, 48, accuracy: 2, "delete is 48 pt high")
            XCTAssertEqual(fieldTop - 12 - delete.frame.maxY, 12, accuracy: 3, "delete sits 12 pt above the search section")
            XCTAssertLessThan(delete.frame.maxY, fieldTop - 12, "delete is outside the search section")
            evidence(app, task: "F2", name: "d21-delete-above-search-\(appearance)")

            delete.tap()
            let undo = element(app, "snackbar.action")
            XCTAssertEqual(undo.label, "復原")
            XCTAssertEqual(fieldTop - 12 - (undo.frame.midY + 28), 12, accuracy: 3, "snackbar 12 pt above the search section")
            evidence(app, task: "F2", name: "d22-undo-\(appearance)")
            undo.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'favoriteRoutes.record.'")).element(boundBy: 0)
                .waitForExistence(timeout: 5), "undo brings the route back")
            app.terminate()
        }
    }
}
