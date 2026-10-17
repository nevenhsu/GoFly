import XCTest

@MainActor
final class GoFlyImportedRoutesUITests: XCTestCase {
    func testIndependentImportsSelectionLoadDeleteUndoAndRelaunchKeepSnapshots() throws {
        try simulatorOnly()
        let app = makeApp(variant: "valid")
        app.launch()
        openRoute(app)
        app.buttons["route.details"].tap()
        let roundTrip = app.descendants(matching: .any)["route.roundTrip"]
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        roundTrip.tap()
        app.sliders["route.speed"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["route.importedRoutes"].tap()
        waitForList(app)
        XCTAssertTrue(app.staticTexts["imports.empty"].exists)
        XCTAssertFalse(app.buttons["imports.load"].isEnabled)
        XCTAssertFalse(app.buttons["imports.export"].isEnabled)
        importFile(app, expectedCount: 1)
        let firstID = recordIDs(app)[0]
        let first = app.buttons[firstID]
        XCTAssertTrue(first.isSelected)
        importFile(app, expectedCount: 2)
        let ids = recordIDs(app)
        XCTAssertEqual(Set(ids).count, 2)
        let secondID = try XCTUnwrap(ids.first(where: { $0 != firstID }))
        XCTAssertTrue(app.buttons[secondID].isSelected)
        reveal(first, in: app)
        first.tap()
        waitUntil { first.isSelected && app.buttons["imports.load"].isEnabled }
        let delete = app.buttons[firstID.replacingOccurrences(of: "imports.record.", with: "imports.delete.")]
        assertTarget(first, in: app)
        assertTarget(delete, in: app)
        XCTAssertLessThanOrEqual(first.frame.maxX, delete.frame.minX)
        app.buttons["imports.back"].tap()
        app.buttons["route.details.back"].tap()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location",
                       "Selecting an import must not change the route draft.")
        openImports(app)
        XCTAssertTrue(first.isSelected)
        app.buttons["imports.load"].tap()
        let summary = app.descendants(matching: .any)["route.importedSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("valid.gpx"))
        assertMainPreview(app, points: 2)
        XCTAssertFalse(app.buttons["route.node.start"].exists)
        XCTAssertFalse(app.buttons["route.addNode"].exists)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        app.buttons["route.details"].tap()
        XCTAssertTrue(roundTrip.waitForExistence(timeout: 5))
        XCTAssertEqual(roundTrip.value as? String, "1")
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "100 km/h")
        app.buttons["route.importedRoutes"].tap()
        waitForList(app)
        reveal(delete, in: app)
        delete.tap()
        waitForRecords(app, count: 1)
        XCTAssertEqual(recordIDs(app), [secondID])
        XCTAssertFalse(app.buttons["imports.load"].isEnabled)
        XCTAssertFalse(app.buttons["imports.export"].isEnabled)
        let undo = app.buttons["imports.undo"]
        reveal(undo, in: app)
        assertTarget(undo, in: app)
        undo.tap()
        waitForRecords(app, count: 2)
        XCTAssertEqual(Set(recordIDs(app)), Set(ids))
        XCTAssertFalse(first.isSelected, "Undo restores identity, not selection.")
        XCTAssertFalse(app.buttons["imports.load"].isEnabled)
        app.buttons["imports.back"].tap()
        app.buttons["route.details.back"].tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("valid.gpx"), "Deleting the source record must not invalidate a loaded snapshot.")
        attach(app, "09-loaded-gpx-snapshot-survives-source-delete-undo")
        app.buttons["route.clearImported"].tap()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
        waitUntil { app.staticTexts["map.routePreview.points"].label == "0" }
        XCTAssertFalse(summary.exists)
        app.buttons["route.details"].tap()
        XCTAssertEqual(roundTrip.value as? String, "1")
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "100 km/h")
        app.terminate()
        app.launch()
        openRoute(app)
        openImports(app)
        waitForRecords(app, count: 2)
        XCTAssertEqual(Set(recordIDs(app)), Set(ids), "The real file store must retain two independent UUIDs on relaunch.")
        XCTAssertFalse(app.buttons["imports.load"].isEnabled)
        XCTAssertFalse(app.buttons["imports.export"].isEnabled)
        app.buttons[firstID].tap()
        waitUntil { app.buttons["imports.load"].isEnabled }
        XCTAssertEqual(previewCount(app, "points"), 2)
        attach(app, "09-relaunched-actual-import-store-distinct-records")
    }

    func testDisconnectedAndZeroPathsPreviewAndExportWhileInvalidFilesAddNothing() throws {
        try simulatorOnly()
        for variant in ["gapped", "zero", "invalid", "large"] {
            let app = makeApp(variant: variant)
            app.launch()
            openRoute(app)
            openImports(app)
            app.buttons["imports.import"].tap()
            if variant == "gapped" || variant == "zero" {
                waitForRecords(app, count: 1)
                let reason = app.descendants(matching: .any)["imports.executionError"]
                XCTAssertTrue(reason.waitForExistence(timeout: 5))
                XCTAssertTrue(reason.label.contains(variant == "gapped" ? "segments do not share" : "no travel distance"))
                XCTAssertFalse(app.buttons["imports.load"].isEnabled)
                XCTAssertTrue(app.buttons["imports.export"].isEnabled)
                XCTAssertEqual(previewCount(app, "points"), variant == "gapped" ? 4 : 2)
                XCTAssertEqual(previewCount(app, "segments"), variant == "gapped" ? 2 : 1)
            } else {
                let error = app.descendants(matching: .any)["imports.error"]
                XCTAssertTrue(error.waitForExistence(timeout: 5))
                XCTAssertTrue(error.label.contains(variant == "large" ? "2 MiB" : "GPX"))
                XCTAssertEqual(recordIDs(app), [])
                XCTAssertTrue(app.staticTexts["imports.empty"].exists)
                XCTAssertFalse(app.buttons["imports.load"].isEnabled)
                XCTAssertFalse(app.buttons["imports.export"].isEnabled)
            }
            attach(app, "09-\(variant)-truthful-import-state")
            app.buttons["imports.back"].tap()
            app.buttons["route.details.back"].tap()
            XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
            XCTAssertFalse(app.descendants(matching: .any)["route.importedSummary"].exists)
            app.terminate()
        }
    }

    func testTenThousandPointPreviewAndActualExportDocumentKeepFullPath() throws {
        try simulatorOnly()
        let app = makeApp(variant: "tenThousand")
        app.launch()
        openRoute(app)
        openImports(app)
        importFile(app, expectedCount: 1)
        XCTAssertEqual(previewCount(app, "points"), 10_000)
        XCTAssertEqual(previewCount(app, "segments"), 1)
        XCTAssertTrue(app.buttons["imports.load"].isEnabled)
        let export = app.buttons["imports.export"]
        reveal(export, in: app)
        export.tap()
        let save = app.buttons["DOCPicker.actionButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 8), "The actual system exporter must present its Save action.")
        XCTAssertEqual(save.label, "Save")
        let cancel = app.buttons["Cancel"].firstMatch
        if !cancel.exists {
            let browse = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(browse.exists, "An exporter opened inside a folder exposes the native Browse return action.")
            XCTAssertEqual(browse.label, "Browse")
            browse.tap()
        }
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "The system exporter must allow cancellation without saving.")
        cancel.tap()
        let metrics = app.staticTexts["imports.export.metrics"]
        XCTAssertTrue(metrics.waitForExistence(timeout: 5))
        let values = metrics.label.split(separator: ",")
        XCTAssertEqual(values.count, 3)
        XCTAssertEqual(values.first, "10000")
        XCTAssertGreaterThan(Int(values.dropFirst().first ?? "0") ?? 0, 10_000)
        XCTAssertEqual(values.last?.count, 64)
        XCTAssertEqual(recordIDs(app).count, 1, "Cancelling system export must not modify imports.")
        app.buttons["imports.load"].tap()
        let summary = app.descendants(matching: .any)["route.importedSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("tenThousand.gpx"))
        assertMainPreview(app, points: 10_000)
        XCTAssertTrue(summary.label.replacingOccurrences(of: ",", with: "").contains("10000"))
        XCTAssertFalse(app.buttons["route.addNode"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "route.node.")).count, 0)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        attach(app, "09-ten-thousand-points-loaded-as-one-gpx-summary")
    }

    func testLocalizedLargeDarkListKeepsSeparateTargetsAndPinnedLoadVisible() throws {
        try simulatorOnly()
        for language in ["en", "zh-Hant", "zh-Hans"] {
            let app = makeApp(variant: "valid", language: language)
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            openRoute(app)
            openImports(app)
            let importButton = app.buttons["imports.import"]
            reveal(importButton, in: app)
            assertTarget(importButton, in: app)
            XCTAssertFalse(app.buttons["imports.load"].isEnabled)
            assertTarget(app.buttons["imports.load"], in: app)
            importButton.tap()
            waitForRecords(app, count: 1)
            let recordID = recordIDs(app)[0]
            let card = app.buttons[recordID]
            let delete = app.buttons[recordID.replacingOccurrences(of: "imports.record.", with: "imports.delete.")]
            reveal(card, in: app)
            assertTarget(card, in: app)
            assertTarget(delete, in: app)
            XCTAssertLessThanOrEqual(card.frame.maxX, delete.frame.minX)
            XCTAssertTrue(importViewport(app).contains(card.frame))
            XCTAssertTrue(importViewport(app).contains(delete.frame))
            let load = app.buttons["imports.load"]
            assertTarget(load, in: app)
            XCTAssertTrue(load.isEnabled)
            XCTAssertLessThanOrEqual(importViewport(app).maxY, load.frame.minY)
            assertTarget(app.buttons["imports.back"], in: app)
            attach(app, "09-import-list-\(language)-max-dark-independent-targets")
            app.terminate()
        }
    }

    func testCancellingRealSystemFilePickerKeepsEmptyListAndOriginalDraft() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        openImports(app)
        app.buttons["imports.import"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "Import must open the actual system file picker.")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["imports.empty"].waitForExistence(timeout: 5))
        XCTAssertEqual(recordIDs(app), [])
        XCTAssertFalse(app.buttons["imports.load"].isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["imports.error"].exists)
        app.buttons["imports.back"].tap()
        app.buttons["route.details.back"].tap()
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
        attach(app, "09-import-cancel-original-manual-panel")
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("GPX UI tests use isolated real simulator file stores. Physical movement checks are deferred.")
        #endif
    }
    private func makeApp(variant: String? = nil, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-imports-store", UUID().uuidString, "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_TW"]
        if let variant { app.launchArguments += ["-gofly-ui-gpx-file", variant] }
        return app
    }
    private func openRoute(_ app: XCUIApplication) {
        app.selectGoFlyMode("route")
        XCTAssertTrue(app.buttons["route.details"].waitForExistence(timeout: 5))
        assertTarget(app.buttons["route.details"], in: app)
    }
    private func openImports(_ app: XCUIApplication) {
        app.buttons["route.details"].tap()
        let entry = app.buttons["route.importedRoutes"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        waitForList(app)
    }
    private func waitForList(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["imports.import"].waitForExistence(timeout: 5))
        waitUntil { app.buttons["imports.import"].isEnabled }
    }
    private func importFile(_ app: XCUIApplication, expectedCount: Int) {
        reveal(app.buttons["imports.import"], in: app)
        app.buttons["imports.import"].tap()
        waitForRecords(app, count: expectedCount)
        waitUntil { app.buttons["imports.export"].isEnabled }
    }
    private func recordIDs(_ app: XCUIApplication) -> [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "imports.record."))
            .allElementsBoundByIndex.map(\.identifier)
    }
    private func waitForRecords(_ app: XCUIApplication, count: Int) {
        waitUntil { self.recordIDs(app).count == count }
    }
    private func previewCount(_ app: XCUIApplication, _ metric: String) -> Int {
        let value = app.staticTexts["imports.preview.\(metric)"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        return Int(value.label.filter(\.isNumber)) ?? -1
    }
    private func importViewport(_ app: XCUIApplication) -> CGRect {
        let values = app.staticTexts["imports.viewport.metrics"].label.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    private func assertMainPreview(_ app: XCUIApplication, points: Int) {
        waitUntil {
            Int(app.staticTexts["map.routePreview.points"].label.filter(\.isNumber)) == points
                && app.staticTexts["map.routePreview.visible"].label == "true"
        }
        XCTAssertTrue(app.buttons["route.start"].isEnabled, "Loading previews the full path without starting movement.")
        XCTAssertTrue(app.staticTexts["map.positionStatus"].label.contains("Stopped"))
    }
    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let viewport = importViewport(app)
            if target.isHittable, viewport.contains(target.frame) { return }
            if target.frame.minY < viewport.minY { app.scrollViews["imports.content"].swipeDown() }
            else { app.scrollViews["imports.content"].swipeUp() }
        }
    }
    private func waitUntil(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed, file: file, line: line)
    }
    private func assertTarget(_ target: XCUIElement, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        // AX subtracts fractional screen coordinates; 44pt can arrive as 43.99999999999994.
        let minimumTarget: CGFloat = 44 - 0.000001
        XCTAssertGreaterThanOrEqual(target.frame.width, minimumTarget, file: file, line: line)
        XCTAssertGreaterThanOrEqual(target.frame.height, minimumTarget, file: file, line: line)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(target.frame), file: file, line: line)
        if target.isEnabled { XCTAssertTrue(target.isHittable, file: file, line: line) }
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
