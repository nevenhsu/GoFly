import XCTest

@MainActor
final class GoFlyFavoriteUITests: XCTestCase {
    private let first = "25.047800, 121.517000"
    private let second = "25.033000, 121.565400"

    func testImmediateStarsPersistAndStayIndependentOfSelectionAndDetails() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(app.staticTexts["favorites.empty"].waitForExistence(timeout: 5))
        app.buttons["favorites.search"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText("25.0478, 121.5170")
        dismissKeyboard(app)
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.candidate.selectionID"].waitForExistence(timeout: 5))
        let selectedID = app.staticTexts["map.candidate.selectionID"].label
        let star = app.buttons["search.favorite.\(first)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(star.frame.width, 44)
        XCTAssertGreaterThanOrEqual(star.frame.height, 44)
        star.tap()
        XCTAssertEqual(star.value as? String, "Favorite")
        XCTAssertEqual(pin.value as? String, first)
        XCTAssertEqual(app.staticTexts["map.candidate.selectionID"].label, selectedID)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)

        pin.tap()
        XCTAssertTrue(app.navigationBars["Place details"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["placeDetails.title"].label, first)
        XCTAssertEqual(app.staticTexts["placeDetails.address"].label, "Address unavailable")
        XCTAssertEqual(app.staticTexts["placeDetails.coordinates"].label, first)
        let detailStar = app.buttons["placeDetails.favorite"]
        XCTAssertEqual(detailStar.value as? String, "Favorite")
        detailStar.tap()
        XCTAssertEqual(detailStar.value as? String, "Not a favorite")
        XCTAssertTrue(app.navigationBars["Place details"].exists)
        detailStar.tap()
        XCTAssertEqual(detailStar.value as? String, "Favorite")
        attach(app, "05-shared-details-immediate-star")
        app.buttons["placeDetails.dismiss"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, first)
        XCTAssertEqual(star.value as? String, "Favorite")

        XCTAssertEqual(app.staticTexts["map.candidate.selectionID"].label, selectedID)

        query.tap()
        query.typeText("x")
        XCTAssertTrue(app.staticTexts["search.inputError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled)
        XCTAssertEqual(pin.value as? String, first)
        revealInSearch(star, app: app, scrollUp: true)
        XCTAssertEqual(star.value as? String, "Favorite")
        star.tap()
        star.tap()
        XCTAssertEqual(pin.value as? String, first)
        XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled)
        revealInSearch(app.buttons["search.clear"], app: app, scrollUp: false)
        app.buttons["search.clear"].tap()
        dismissKeyboard(app)
        XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled,
                       "Clearing invalid text must not silently authorize the retained candidate.")
        app.buttons["favorites.open"].tap()
        let row = app.buttons["favorites.place.\(first)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.candidate.go"].isEnabled)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        assertCentered(app)

        app.terminate()
        app.launch()
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["favorites.star.\(first)"].value as? String, "Favorite")
        attach(app, "05-relaunched-real-store-favorite")
        row.tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, first)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
    }

    func testLongPressDraftAndImmediateStarTransactionsRemainSeparate() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        dismissKeyboard(app)
        app.buttons["search.favorite.\(first)"].tap()
        replace(query, with: "25.0330, 121.5654")
        dismissKeyboard(app)
        app.buttons["search.favorite.\(second)"].tap()
        let selectedID = app.staticTexts["map.candidate.selectionID"].label
        app.buttons["favorites.open"].tap()
        let row = app.buttons["favorites.place.\(first)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 0.8)
        let label = app.textFields["favorites.editor.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.typeText("Home")
        app.buttons["favorites.editor.save"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Home")
        XCTAssertTrue(app.buttons["favorites.place.\(second)"].isSelected,
                      "Long press must not select the edited favorite.")

        row.press(forDuration: 0.8)
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        replace(label, with: "Unsaved draft")
        let editorStar = app.buttons["favorites.editor.star"]
        editorStar.tap()
        XCTAssertTrue(app.staticTexts["favorites.editor.removed"].exists)
        XCTAssertFalse(app.buttons["favorites.editor.save"].isEnabled)
        XCTAssertTrue(label.exists)
        editorStar.tap()
        XCTAssertTrue(app.buttons["favorites.editor.save"].isEnabled)
        XCTAssertEqual(label.value as? String, "Unsaved draft")
        app.buttons["favorites.editor.cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Home", "Re-add restores the last persisted label, not the editor draft.")

        row.press(forDuration: 0.8)
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        replace(label, with: String(repeating: "a", count: 121))
        app.buttons["favorites.editor.save"].tap()
        XCTAssertTrue(app.staticTexts["favorites.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["favorites.error"].label.contains("120"))
        XCTAssertTrue(label.exists)
        app.buttons["favorites.editor.cancel"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Home")

        row.press(forDuration: 0.8)
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        app.buttons["favorites.editor.star"].tap()
        XCTAssertFalse(app.buttons["favorites.editor.save"].isEnabled)
        app.buttons["favorites.editor.cancel"].tap()
        XCTAssertFalse(row.exists, "Cancel cannot roll back an immediately persisted star removal.")
        XCTAssertTrue(app.buttons["favorites.place.\(second)"].exists)
        app.buttons["favorites.dismiss"].tap()
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, second)
        XCTAssertEqual(app.staticTexts["map.candidate.selectionID"].label, selectedID,
                       "Stars and label editing must not silently reselect any candidate.")
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        app.terminate()
        app.launch()
        app.buttons["favorites.open"].tap()
        XCTAssertFalse(row.exists)
        XCTAssertTrue(app.buttons["favorites.place.\(second)"].waitForExistence(timeout: 5))
        attach(app, "05-label-cancel-retains-immediate-star-removal")
    }

    func testUnconfirmedReturnKeepsGoLockedWhileDetailsAndFavoritesWork() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-unconfirmed-point"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        app.buttons["map.candidate.go"].tap()
        XCTAssertTrue(app.buttons["operation.return"].waitForExistence(timeout: 10))
        app.buttons["operation.return"].tap()
        let go = app.buttons["map.candidate.go"]
        XCTAssertFalse(go.isEnabled)
        app.buttons["map.candidate.pin"].tap()
        XCTAssertTrue(app.buttons["placeDetails.favorite"].waitForExistence(timeout: 5))
        app.buttons["placeDetails.favorite"].tap()
        XCTAssertEqual(app.buttons["placeDetails.favorite"].value as? String, "Favorite")
        XCTAssertTrue(app.navigationBars["Place details"].exists)
        app.buttons["placeDetails.dismiss"].tap()
        XCTAssertTrue(app.buttons["favorites.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(go.isEnabled)
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(app.buttons["favorites.place.\(first)"].waitForExistence(timeout: 5))
        app.buttons["favorites.star.\(first)"].tap()
        XCTAssertTrue(app.staticTexts["favorites.empty"].exists)
        app.buttons["favorites.dismiss"].tap()
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["map.candidate.pin"].value as? String, first)
        XCTAssertFalse(go.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, "05-unconfirmed-go-locked-favorites-usable")
    }

    func testLargeDarkDetailAndLabelKeyboardKeepIndependentControlsReachable() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        dismissKeyboard(app)
        let star = app.buttons["search.favorite.\(first)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertEqual(star.frame.width, 44, accuracy: 1)
        XCTAssertEqual(star.frame.height, 44, accuracy: 1)
        star.tap()
        app.buttons["map.candidate.pin"].tap()
        let detailStar = app.buttons["placeDetails.favorite"]
        XCTAssertTrue(detailStar.waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            detailStar.isHittable && detailStar.frame.width >= 43.5 && detailStar.frame.height >= 43.5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        XCTAssertEqual(detailStar.frame.width, 44, accuracy: 1)
        XCTAssertEqual(detailStar.frame.height, 44, accuracy: 1)
        attach(app, "05-detail-large-dark-independent-star")
        app.buttons["placeDetails.dismiss"].tap()
        app.buttons["favorites.open"].tap()
        let row = app.buttons["favorites.place.\(first)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 0.8)
        let label = app.textFields["favorites.editor.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.typeText("Unsaved label")
        let cancel = app.buttons["favorites.editor.cancel"]
        XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.buttons["favorites.editor.save"].isHittable)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            XCTAssertLessThanOrEqual(cancel.frame.maxY, keyboard.frame.minY + 2,
                                     "Label actions must stay entirely above the keyboard.")
        }
        attach(app, "05-label-large-dark-keyboard-actions")
        dismissKeyboard(app)
        XCTAssertTrue(label.exists, "Keyboard Done must only dismiss the keyboard.")
        let editorStar = app.buttons["favorites.editor.star"]
        let form = app.scrollViews["favorites.editor.form"]
        for _ in 0..<3 {
            if editorStar.isHittable && form.frame.insetBy(dx: -1, dy: -1).contains(editorStar.frame) { break }
            form.swipeDown()
        }
        XCTAssertTrue(editorStar.isHittable)
        XCTAssertTrue(form.frame.insetBy(dx: -1, dy: -1).contains(editorStar.frame),
                      "The complete editor star must be reachable after dismissing the keyboard.")
        editorStar.tap()
        XCTAssertFalse(app.buttons["favorites.editor.save"].isEnabled)
        editorStar.tap()
        XCTAssertTrue(app.buttons["favorites.editor.save"].isEnabled)
        cancel.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, first)
        app.buttons["favorites.dismiss"].tap()
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["map.candidate.pin"].value as? String, first)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests use isolated real simulator file stores and explicit error fixtures; phone checks are deferred.")
        #endif
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }

    private func replace(_ field: XCUIElement, with text: String) {
        field.tap()
        let value = field.value as? String ?? ""
        let current = value == "Label" ? "" : value
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func assertCentered(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let values = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
            return values.count == 6 && values[4] > 0 && values[5] > 0
                && abs(values[0] - values[2]) < 3 && abs(values[1] - values[3]) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 8), .completed,
                       "Selecting a favorite must center its actual projection in the visible map.", file: file, line: line)
    }

    private func revealInSearch(_ element: XCUIElement, app: XCUIApplication, scrollUp: Bool,
                                file: StaticString = #filePath, line: UInt = #line) {
        let panel = app.descendants(matching: .any)["search.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<4 {
            if element.exists, element.isHittable, panel.frame.contains(element.frame) { break }
            if scrollUp { panel.swipeUp() } else { panel.swipeDown() }
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, file: file, line: line)
        XCTAssertTrue(panel.frame.contains(element.frame), "The full control must fit inside the visible search panel.", file: file, line: line)
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
