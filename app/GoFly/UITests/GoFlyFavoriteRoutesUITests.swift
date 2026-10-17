import XCTest

@MainActor
final class GoFlyFavoriteRoutesUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testUnavailableCurrentEligibilityCancelAndOmittedReceiptKeepLiveDraft() throws {
        try simulatorOnly()
        let app = makeApp(count: 2)
        app.launch()
        openRoute(app)
        let originalIDs = nodeIDs(app)
        openSave(app)
        typeLabel(app, id: "favoriteRoutes.save.label", text: "Cancelled route")
        XCTAssertFalse(app.buttons["favoriteRoutes.save.confirm"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.error"].label.contains("At least two available places"))
        app.buttons["favoriteRoutes.save.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), originalIDs)
        openFavorites(app)
        XCTAssertTrue(app.staticTexts["favoriteRoutes.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(recordIDs(app), [])
        app.buttons["favoriteRoutes.return"].tap()
        app.terminate()
        let index = try XCTUnwrap(app.launchArguments.firstIndex(of: "-gofly-ui-route-draft-count"))
        app.launchArguments[index + 1] = "3"
        app.launch()
        openRoute(app)
        let draftIDs = nodeIDs(app)
        openSave(app)
        typeLabel(app, id: "favoriteRoutes.save.label", text: "Two places")
        XCTAssertTrue(app.buttons["favoriteRoutes.save.confirm"].isEnabled)
        app.buttons["favoriteRoutes.save.confirm"].tap()
        let result = app.descendants(matching: .any)["favoriteRoutes.save.omittedResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(result.label.contains("not included"))
        XCTAssertFalse(app.buttons["favoriteRoutes.save.confirm"].exists)
        XCTAssertFalse(app.buttons["favoriteRoutes.save.cancel"].exists)
        XCTAssertFalse(app.textFields["favoriteRoutes.save.label"].exists)
        attach(app, "10-saved-omitted-current-done-only")
        app.buttons["favoriteRoutes.save.done"].tap()
        waitUntil { app.buttons["route.favorite.add"].isHittable }
        XCTAssertEqual(nodeIDs(app), draftIDs)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
        XCTAssertFalse(app.buttons["route.start"].isEnabled, "Saving must not weaken Start's strict Current-location rule.")
        XCTAssertFalse(app.buttons["route.favorite.add"].isSelected)
        openFavorites(app)
        waitForRecords(app, count: 1)
        let record = app.buttons[recordIDs(app)[0]]
        XCTAssertEqual(record.value as? String, "2 places")
        record.tap()
        waitUntil { !app.buttons["favoriteRoutes.return"].exists }
        XCTAssertEqual(nodeIDs(app).count, 2)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.002000, 121.502000")
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "25.004000, 121.504000")
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        XCTAssertTrue(app.staticTexts["map.positionStatus"].label.contains("Stopped"))
        attach(app, "10-short-load-keeps-exact-two-saved-places-without-start")
    }

    func testDuplicateRecordsLongPressLabelDeleteUndoRelaunchAndSettingsStayIndependent() throws {
        try simulatorOnly()
        let app = makeApp(count: 2)
        app.launch()
        openRoute(app)
        setOrigin(app)
        setOptions(app)
        save(app, label: "Daily route")
        save(app, label: "Daily route")
        XCTAssertFalse(app.buttons["route.favorite.add"].isSelected)
        let draftIDs = nodeIDs(app)
        openFavorites(app)
        waitForRecords(app, count: 2)
        let ids = recordIDs(app)
        XCTAssertEqual(Set(ids).count, 2)
        let first = app.buttons[ids[0]]
        let second = app.buttons[ids[1]]
        XCTAssertFalse(first.isSelected)
        XCTAssertFalse(second.isSelected)
        first.press(forDuration: 0.8)
        XCTAssertTrue(app.textFields["favoriteRoutes.editor.label"].waitForExistence(timeout: 5))
        typeLabel(app, id: "favoriteRoutes.editor.label", text: "Discarded label")
        app.buttons["favoriteRoutes.editor.cancel"].tap()
        waitUntil { first.isHittable }
        assertRecordLabel(first, label: "Daily route")
        first.press(forDuration: 0.8)
        typeLabel(app, id: "favoriteRoutes.editor.label", text: String(repeating: "x", count: 121))
        app.buttons["favoriteRoutes.editor.save"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["favoriteRoutes.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["favoriteRoutes.editor.label"].exists)
        typeLabel(app, id: "favoriteRoutes.editor.label", text: "Morning route")
        app.buttons["favoriteRoutes.editor.save"].tap()
        waitUntil { first.isHittable }
        assertRecordLabel(first, label: "Morning route")
        XCTAssertEqual(Set(recordIDs(app)), Set(ids))
        assertRecordLabel(second, label: "Daily route")
        app.buttons["favoriteRoutes.return"].tap()
        XCTAssertEqual(nodeIDs(app), draftIDs, "Long press and label edits must not select or replace the route draft.")
        openFavorites(app)
        first.tap()
        waitUntil { !app.buttons["favoriteRoutes.return"].exists }
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.047800, 121.517000")
        verifyOptions(app, speed: "100 km/h", roundTrip: "1")
        let loadedIDs = nodeIDs(app)
        openFavorites(app)
        XCTAssertTrue(first.isSelected)
        app.buttons[ids[0].replacingOccurrences(of: "favoriteRoutes.record.", with: "favoriteRoutes.delete.")].tap()
        waitForRecords(app, count: 1)
        XCTAssertEqual(recordIDs(app), [ids[1]])
        app.buttons["favoriteRoutes.undo"].tap()
        waitForRecords(app, count: 2)
        XCTAssertEqual(Set(recordIDs(app)), Set(ids))
        XCTAssertFalse(first.isSelected)
        attach(app, "10-duplicate-label-edit-and-undo-preserve-record-ids")
        app.buttons["favoriteRoutes.return"].tap()
        XCTAssertEqual(nodeIDs(app), loadedIDs)
        app.terminate()
        app.launch()
        openRoute(app)
        openFavorites(app)
        waitForRecords(app, count: 2)
        XCTAssertEqual(Set(recordIDs(app)), Set(ids))
        assertRecordLabel(first, label: "Morning route")
        assertRecordLabel(second, label: "Daily route")
        first.tap()
        waitUntil { !app.buttons["favoriteRoutes.return"].exists }
        verifyOptions(app, speed: "20 km/h", roundTrip: "0")
        XCTAssertTrue(app.staticTexts["map.positionStatus"].label.contains("Stopped"))
    }

    func testGPXFavoriteRetainsTenThousandPointsAfterImportDeletionAndRelaunch() throws {
        try simulatorOnly()
        let app = makeApp(count: 1)
        app.launchArguments += ["-gofly-ui-gpx-file", "tenThousand"]
        app.launch()
        openRoute(app)
        openImports(app)
        app.buttons["imports.import"].tap()
        waitUntil { app.buttons["imports.load"].isEnabled }
        let imported = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imports.record.")).firstMatch
        let importedID = imported.identifier
        app.buttons["imports.load"].tap()
        assertGPXPreview(app)
        save(app, label: "Long walk")
        openImports(app)
        let delete = app.buttons[importedID.replacingOccurrences(of: "imports.record.", with: "imports.delete.")]
        if !delete.isHittable { app.scrollViews["imports.content"].swipeDown() }
        delete.tap()
        XCTAssertTrue(app.staticTexts["imports.empty"].waitForExistence(timeout: 5))
        app.buttons["imports.back"].tap()
        app.buttons["route.details.back"].tap()
        app.buttons["route.clearImported"].tap()
        waitUntil { app.staticTexts["map.routePreview.points"].label == "0" }
        openFavorites(app)
        waitForRecords(app, count: 1)
        let id = recordIDs(app)[0]
        XCTAssertEqual(app.buttons[id].value as? String, "10,000 points")
        app.buttons[id].tap()
        assertGPXPreview(app)
        openImports(app)
        XCTAssertTrue(app.staticTexts["imports.empty"].exists, "Loading a favorite GPX must not fabricate an imported record.")
        app.buttons["imports.back"].tap()
        app.buttons["route.details.back"].tap()
        attach(app, "10-favorite-gpx-full-preview-after-original-import-deletion")
        app.terminate()
        app.launch()
        openRoute(app)
        openFavorites(app)
        waitForRecords(app, count: 1)
        XCTAssertEqual(recordIDs(app), [id])
        app.buttons[id].tap()
        assertGPXPreview(app)
        XCTAssertTrue(app.staticTexts["map.positionStatus"].label.contains("Stopped"))
    }

    func testLocalizedLargeDarkSaveAndLongPressEditorKeepKeyboardAndTargetsReachable() throws {
        try simulatorOnly()
        for language in ["en", "zh-Hant", "zh-Hans"] {
            let app = makeApp(count: 3, language: language)
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            openRoute(app)
            openSave(app)
            assertForm(app, prefix: "favoriteRoutes.save", saveID: "favoriteRoutes.save.confirm")
            typeLabel(app, id: "favoriteRoutes.save.label", text: "Saved AX")
            attach(app, "10-save-\(language)-max-dark-keyboard")
            app.buttons["favoriteRoutes.save.confirm"].tap()
            XCTAssertTrue(app.buttons["favoriteRoutes.save.done"].waitForExistence(timeout: 8))
            XCTAssertFalse(app.buttons["favoriteRoutes.save.confirm"].exists)
            assertTarget(app.buttons["favoriteRoutes.save.done"], in: app)
            app.buttons["favoriteRoutes.save.done"].tap()
            openFavorites(app)
            waitForRecords(app, count: 1)
            let id = recordIDs(app)[0]
            let record = app.buttons[id]
            let delete = app.buttons[id.replacingOccurrences(of: "favoriteRoutes.record.", with: "favoriteRoutes.delete.")]
            assertTarget(record, in: app)
            assertTarget(delete, in: app)
            XCTAssertLessThanOrEqual(record.frame.maxX, delete.frame.minX)
            record.press(forDuration: 0.8)
            assertForm(app, prefix: "favoriteRoutes.editor", saveID: "favoriteRoutes.editor.save")
            typeLabel(app, id: "favoriteRoutes.editor.label", text: "Cancelled AX")
            attach(app, "10-editor-\(language)-max-dark-keyboard")
            app.buttons["favoriteRoutes.editor.cancel"].tap()
            waitUntil { record.isHittable }
            assertRecordLabel(record, label: "Saved AX",
                              endpoints: "25.002000, 121.502000 → 25.004000, 121.504000")
            app.buttons["favoriteRoutes.return"].tap()
            XCTAssertEqual(app.buttons["route.node.start"].value as? String,
                           language == "en" ? "Current location" : (language == "zh-Hant" ? "目前位置" : "当前位置"))
            app.terminate()
        }
    }

    func testTwentySevenExplicitPlacesRelaunchAndLoadKeepOrderWithoutTruncation() throws {
        try simulatorOnly()
        let app = makeApp(count: 27)
        app.launch()
        openRoute(app)
        setOrigin(app, coordinate: "25.0000, 121.5000")
        let original = nodeIDs(app)
        XCTAssertEqual(original.count, 27)
        save(app, label: "")
        openFavorites(app)
        waitForRecords(app, count: 1)
        let id = recordIDs(app)[0]
        let record = app.buttons[id]
        XCTAssertEqual(record.value as? String, "27 places")
        XCTAssertEqual(record.label.components(separatedBy: "→").count, 2, "Unlabeled route cards must not repeat the endpoint summary.")
        record.tap()
        waitUntil { !app.buttons["favoriteRoutes.return"].exists }
        let loaded = nodeIDs(app)
        XCTAssertEqual(loaded.count, 27)
        XCTAssertTrue(Set(original).isDisjoint(with: Set(loaded)), "Manual favorite loads create fresh node IDs while retaining the places.")
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.000000, 121.500000")
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "25.052000, 121.552000")
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        app.terminate()
        app.launch()
        openRoute(app)
        openFavorites(app)
        XCTAssertEqual(recordIDs(app), [id])
        app.buttons[id].tap()
        waitUntil { !app.buttons["favoriteRoutes.return"].exists }
        XCTAssertEqual(nodeIDs(app).count, 27)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "25.052000, 121.552000")
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Favorite-route UI tests use isolated real simulator stores. Physical movement is deferred.")
        #endif
    }
    private func makeApp(count: Int, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-imports-store", UUID().uuidString, "-gofly-ui-favorite-routes-store", UUID().uuidString,
                               "-gofly-ui-route-draft-count", String(count), "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_TW"]
        return app
    }
    private func openRoute(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["mode.route"].waitForExistence(timeout: 10))
        app.buttons["mode.route"].tap()
        XCTAssertTrue(app.buttons["route.favorite.add"].waitForExistence(timeout: 5))
        assertTarget(app.buttons["route.favorite.add"], in: app)
    }
    private func openSave(_ app: XCUIApplication) {
        revealRoute(app.buttons["route.favorite.add"], in: app)
        app.buttons["route.favorite.add"].tap()
        XCTAssertTrue(app.textFields["favoriteRoutes.save.label"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertTarget(app.textFields["favoriteRoutes.save.label"], in: app)
    }
    private func save(_ app: XCUIApplication, label: String) {
        openSave(app)
        if !label.isEmpty { typeLabel(app, id: "favoriteRoutes.save.label", text: label) }
        let confirm = app.buttons["favoriteRoutes.save.confirm"]
        waitUntil { confirm.isEnabled }
        confirm.tap()
        waitUntil { !app.buttons["favoriteRoutes.save.confirm"].exists }
        if app.buttons["favoriteRoutes.save.done"].exists { app.buttons["favoriteRoutes.save.done"].tap() }
        waitUntil { !app.textFields["favoriteRoutes.save.label"].exists && !app.buttons["favoriteRoutes.save.done"].exists }
    }
    private func openFavorites(_ app: XCUIApplication) {
        let entry = app.buttons["route.favorite.list"]
        revealRoute(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.buttons["favoriteRoutes.return"].waitForExistence(timeout: 5))
    }
    private func openImports(_ app: XCUIApplication) {
        revealRoute(app.buttons["route.details"], in: app)
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.buttons["route.importedRoutes"].waitForExistence(timeout: 5))
        app.buttons["route.importedRoutes"].tap()
        XCTAssertTrue(app.buttons["imports.import"].waitForExistence(timeout: 5))
        waitUntil { app.buttons["imports.import"].isEnabled }
    }
    private func setOrigin(_ app: XCUIApplication, coordinate: String = "25.0478, 121.5170") {
        revealRoute(app.buttons["route.node.start"], in: app)
        app.buttons["route.node.start"].tap()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        query.typeText(coordinate)
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        app.buttons["route.picker.confirm"].tap()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
    }
    private func setOptions(_ app: XCUIApplication) {
        revealRoute(app.buttons["route.details"], in: app)
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.sliders["route.speed"].waitForExistence(timeout: 5))
        app.sliders["route.speed"].adjust(toNormalizedSliderPosition: 1)
        app.descendants(matching: .any)["route.roundTrip"].tap()
        app.buttons["route.details.back"].tap()
    }
    private func verifyOptions(_ app: XCUIApplication, speed: String, roundTrip: String) {
        revealRoute(app.buttons["route.details"], in: app)
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.staticTexts["route.speed.value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, speed)
        XCTAssertEqual(app.descendants(matching: .any)["route.roundTrip"].value as? String, roundTrip)
        app.buttons["route.details.back"].tap()
    }
    private func typeLabel(_ app: XCUIApplication, id: String, text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertTarget(field, in: app)
        let previous = field.value as? String ?? ""
        let placeholders = ["Label (optional)", "標籤（選填）", "标签（选填）"]
        let count = placeholders.contains(previous) ? 0 : previous.count
        if count > 0 {
            for _ in 0..<count {
                field.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
            }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
            let cleared = field.value as? String ?? ""
            guard cleared.isEmpty || placeholders.contains(cleared) else {
                XCTFail("Native right-arrow/backspace did not clear the entire field; stop before typing or Save.")
                return
            }
        }
        field.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
        XCTAssertEqual(field.value as? String, text, "The entire native field must equal the intended replacement before Save.")
        let action = app.buttons[id.hasPrefix("favoriteRoutes.save")
            ? "favoriteRoutes.save.confirm" : "favoriteRoutes.editor.save"]
        var previousFrame: CGRect?
        waitUntil {
            guard app.keyboards.firstMatch.exists, action.isHittable,
                  action.frame.maxY <= app.keyboards.firstMatch.frame.minY + 1 else {
                previousFrame = nil
                return false
            }
            let frame = action.frame
            defer { previousFrame = frame }
            guard let previousFrame else { return false }
            return abs(frame.minX - previousFrame.minX) < 0.5
                && abs(frame.minY - previousFrame.minY) < 0.5
                && abs(frame.width - previousFrame.width) < 0.5
                && abs(frame.height - previousFrame.height) < 0.5
        }
    }
    private func assertRecordLabel(_ record: XCUIElement, label: String,
                                   endpoints: String = "25.047800, 121.517000 → 25.002000, 121.502000",
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(record.label, label + ", " + endpoints, file: file, line: line)
    }
    private func assertForm(_ app: XCUIApplication, prefix: String, saveID: String) {
        let field = app.textFields[prefix + ".label"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitUntil { self.viewport(app, id: prefix + ".viewport.metrics").contains(field.frame) }
        assertTarget(field, in: app)
        for id in [prefix + ".cancel", saveID] {
            let action = app.buttons[id]
            assertTarget(action, in: app)
            XCTAssertLessThanOrEqual(action.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
            XCTAssertFalse(action.frame.intersects(field.frame))
        }
    }
    private func nodeIDs(_ app: XCUIApplication) -> [String] {
        app.staticTexts["route.nodes.order"].label.split(separator: ",").map(String.init)
    }
    private func recordIDs(_ app: XCUIApplication) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favoriteRoutes.record."))
            .allElementsBoundByIndex.map(\.identifier)
    }
    private func waitForRecords(_ app: XCUIApplication, count: Int) {
        waitUntil { self.recordIDs(app).count == count }
    }
    private func assertGPXPreview(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["route.importedSummary"].waitForExistence(timeout: 5))
        waitUntil { app.staticTexts["map.routePreview.points"].label == "10000"
            && app.staticTexts["map.routePreview.visible"].label == "true" }
        XCTAssertFalse(app.buttons["route.addNode"].exists)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
    }
    private func viewport(_ app: XCUIApplication, id: String) -> CGRect {
        let values = app.staticTexts[id].label.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    private func revealRoute(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            let viewport = self.viewport(app, id: "route.nodes.viewport")
            if element.isHittable, viewport.contains(element.frame) { return }
            if element.frame.minY < viewport.minY { app.scrollViews["route.panel.content"].swipeDown() }
            else { app.scrollViews["route.panel.content"].swipeUp() }
        }
    }
    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, file: file, line: line)
    }
    private func assertTarget(_ element: XCUIElement, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let minimum: CGFloat = 44 - 0.000001
        XCTAssertGreaterThanOrEqual(element.frame.width, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height, minimum, file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(element.frame), file: file, line: line)
        if element.isEnabled { XCTAssertTrue(element.isHittable, file: file, line: line) }
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
