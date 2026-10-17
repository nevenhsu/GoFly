import XCTest

@MainActor
final class GoFlyRecoveryUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false }

    func testUserEditedDraftSpeedRoundTripAndStableNodeIDsSurviveColdRelaunchWithoutMovement() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        app.selectGoFlyMode("route")
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
        app.buttons["route.node.start"].tap()
        confirmCoordinate("25.0478, 121.5170", in: app)
        app.buttons["route.addNode"].tap()
        confirmCoordinate("25.0330, 121.5654", in: app)
        let order = app.staticTexts["route.nodes.order"].label
        XCTAssertEqual(order.split(separator: ",").count, 2)
        app.buttons["route.details"].tap()
        let option = app.descendants(matching: .any)["route.roundTrip"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
        app.sliders["route.speed"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "100 km/h")
        app.buttons["route.details.back"].tap()
        waitForSaved(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 10), "The saved mode must restore without selecting it again.")
        XCTAssertEqual(app.staticTexts["route.nodes.order"].label, order)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "25.033000, 121.565400")
        XCTAssertFalse(app.descendants(matching: .any)["recovery.panel"].exists,
                       "A saved editing draft is data only and must not invent an active-task warning.")
        assertNoMovement(app)
        app.buttons["route.details"].tap()
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertEqual(option.value as? String, "1")
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "100 km/h")
        attach(app, "13-user-edited-draft-cold-restored-ids-speed-roundtrip")
    }

    func testImportedTenThousandPointDraftAndActualMapOverlaySurviveColdRelaunch() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-gpx-file", "tenThousand"]
        app.launch()
        app.selectGoFlyMode("route")
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.buttons["route.importedRoutes"].waitForExistence(timeout: 5))
        app.buttons["route.importedRoutes"].tap()
        XCTAssertTrue(app.buttons["imports.import"].waitForExistence(timeout: 5))
        app.buttons["imports.import"].tap()
        waitUntil { app.buttons["imports.load"].isEnabled && Int(app.staticTexts["imports.preview.points"].label.filter(\.isNumber)) == 10_000 }
        app.buttons["imports.load"].tap()
        assertImportedPreview(app)
        waitForSaved(app)
        app.terminate()
        app.launch()
        assertImportedPreview(app)
        assertNoMovement(app)
        XCTAssertFalse(app.descendants(matching: .any)["recovery.panel"].exists)
        attach(app, "13-ten-thousand-point-gpx-cold-draft-actual-overlay")
    }

    func testColdDataSummaryDiscardResetAndFailedClearNeverUnlockNewMovementAcrossRelaunch() throws {
        try simulatorOnly()
        for fixture in ["route", "wander", "manual", "uncertainty"] {
            let app = makeApp(fixture: fixture)
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["recovery.notice"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.descendants(matching: .any)["recovery.notice"].label, "Restore GPS before starting a new task.")
            XCTAssertTrue(app.staticTexts["recovery.summary.title"].exists)
            if fixture == "wander" {
                XCTAssertEqual(app.staticTexts["recovery.wanderTarget"].label, "Current destination: Saved destination")
            } else if fixture == "manual" {
                XCTAssertEqual(app.staticTexts["recovery.manualSummary"].label, "Previous joystick movement · unverified")
                XCTAssertFalse(app.staticTexts["recovery.routeHeading"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["recovery.uncertainty"].exists)
                XCTAssertFalse(app.staticTexts["recovery.routeProgress"].exists, "An uncertainty-only checkpoint cannot invent ACK progress.")
            }
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            XCTAssertFalse(app.buttons["route.resume"].exists)
            assertNoMovement(app)
            reveal(app.buttons["recovery.discard"], in: app)
            app.buttons["recovery.discard"].tap()
            XCTAssertFalse(app.staticTexts["recovery.summary.title"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["recovery.notice"].exists)
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            waitForSaved(app)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.descendants(matching: .any)["recovery.notice"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["recovery.summary.title"].exists, "The initial-only file fixture must not reseed discarded summaries.")
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            reveal(app.buttons["recovery.settings"], in: app)
            app.buttons["recovery.settings"].tap()
            let reset = app.buttons["service.resetTunnel"]
            XCTAssertTrue(reset.waitForExistence(timeout: 5))
            XCTAssertTrue(reset.isEnabled)
            reset.tap()
            let restore = app.buttons["service.restoreGPS"]
            waitUntil { restore.isEnabled }
            restore.tap()
            waitUntil { restore.isEnabled }
            XCTAssertTrue(app.descendants(matching: .any)["service.error"].exists)
            let serviceAction = app.buttons["service.primary"]
            if serviceAction.label == "Start" { XCTAssertFalse(serviceAction.isEnabled) }
            else { XCTAssertEqual(serviceAction.label, "Stop") }
            XCTAssertEqual(app.staticTexts["service.gpsStatus"].label, "GPS recovery has not been confirmed.")
            app.navigationBars.buttons.firstMatch.tap()
            app.selectGoFlyMode("teleport")
            let query = app.textFields["search.query"]
            XCTAssertTrue(query.waitForExistence(timeout: 5))
            query.tap()
            query.typeText("25.0478, 121.5170")
            XCTAssertTrue(app.buttons["map.candidate.go"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled)
            XCTAssertTrue(app.descendants(matching: .any)["recovery.notice"].exists)
            XCTAssertEqual(app.alerts.count, 0)
            attach(app, "13-\(fixture)-discard-reset-failed-clear-still-held")
            app.terminate()
        }
    }

    func testThreeLanguageLargeDarkBlockedArchiveKeepsWarningAndRecoveryActionsReachable() throws {
        try simulatorOnly()
        for language in ["en", "zh-Hant", "zh-Hans"] {
            let app = makeApp(fixture: "corrupt", language: language)
            app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let error = app.descendants(matching: .any)["recovery.storageError"]
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            let expected = language == "en" ? "The saved session is damaged. Its data has not been replaced." :
                (language == "zh-Hant" ? "已存工作階段已損壞，原始資料未被取代。" : "已存会话已损坏，原始数据未被替换。")
            XCTAssertEqual(error.label, expected)
            XCTAssertFalse(app.buttons["recovery.retrySaving"].exists, "An unreadable archive must not offer a rejected overwrite retry.")
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            XCTAssertFalse(app.buttons["recovery.discard"].exists)
            for id in ["recovery.restoreGPS", "recovery.checkConnection", "recovery.settings"] {
                let control = app.buttons[id]
                reveal(control, in: app)
                assertTarget(control, in: app)
            }
            XCTAssertEqual(app.alerts.count, 0)
            attach(app, "13-corrupt-\(language)-max-dark-recovery-actions")
            app.terminate()
            app.launch()
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            XCTAssertEqual(error.label, expected, "Relaunch must preserve the blocked archive, not overwrite it with defaults.")
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            app.terminate()
        }
    }

    private func makeApp(fixture: String? = nil, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString,
                               "-gofly.onboarding.complete", "YES", "-gofly-ui-map-metrics",
                               "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-imports-store", UUID().uuidString,
                               "-gofly-ui-favorite-routes-store", UUID().uuidString,
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_TW"]
        if let fixture { app.launchArguments += ["-gofly-ui-session-fixture", fixture] }
        return app
    }
    private func confirmCoordinate(_ value: String, in app: XCUIApplication) {
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        query.typeText(value)
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["map.candidate.go"].exists)
        app.buttons["route.picker.confirm"].tap()
    }
    private func assertImportedPreview(_ app: XCUIApplication) {
        let summary = app.descendants(matching: .any)["route.importedSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertTrue(summary.label.contains("tenThousand.gpx"))
        XCTAssertTrue(summary.label.replacingOccurrences(of: ",", with: "").contains("10000"))
        waitUntil { Int(app.staticTexts["map.routePreview.points"].label.filter(\.isNumber)) == 10_000
            && app.staticTexts["map.routePreview.visible"].label == "true" }
        XCTAssertFalse(app.buttons["route.addNode"].exists)
    }
    private func waitForSaved(_ app: XCUIApplication) {
        waitUntil { app.staticTexts["session.persistence.status"].label == "saved" }
    }
    private func assertNoMovement(_ app: XCUIApplication) {
        XCTAssertFalse(app.staticTexts["operation.attempt"].exists)
        XCTAssertFalse(app.buttons["route.resume"].exists)
        XCTAssertEqual(app.alerts.count, 0)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["map.panels.scroll"].exists)
        for _ in 0..<12 {
            let viewport = panelViewport(app)
            let frame = element.frame
            if viewport.contains(frame) && (element.isHittable || !element.isEnabled) { return }
            guard frame.height <= viewport.height, frame.width <= viewport.width else { break }
            // Use the measured visible slot, not the AX ScrollView content extent.
            // Small held drags avoid coarse swipe inertia skipping over a large-text target.
            let distance = frame.midY - viewport.midY
            let travel = min(abs(distance), viewport.height * 0.45)
            guard travel > 0 else { break }
            let direction: CGFloat = distance > 0 ? 1 : -1
            let startY = viewport.midY + direction * viewport.height * 0.25
            let endY = max(viewport.minY + 8, min(viewport.maxY - 8, startY - direction * travel))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: viewport.midX, dy: startY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: viewport.midX, dy: endY)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        let viewport = panelViewport(app)
        if viewport.contains(element.frame) && (element.isHittable || !element.isEnabled) { return }
        attach(app, "13-unreachable-" + element.identifier)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "13-unreachable-" + element.identifier + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(viewport.contains(element.frame),
                      "Full target \(element.identifier) \(element.frame) must fit actual viewport \(viewport).")
        XCTAssertTrue(element.isHittable || !element.isEnabled)
    }
    private func assertTarget(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44 - 0.000001)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44 - 0.000001)
        XCTAssertTrue(panelViewport(app).contains(element.frame), "The complete target must fit inside the measured parent viewport.")
        XCTAssertTrue(element.isHittable || !element.isEnabled)
    }
    private func panelViewport(_ app: XCUIApplication) -> CGRect {
        let values = app.staticTexts["map.panel.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 4)
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            .intersection(app.windows.firstMatch.frame)
            .insetBy(dx: -0.000001, dy: -0.000001)
    }
    private func waitUntil(timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Recovery UI tests use real private files and the simulator's actual failure path; native clear and movement proof are tested separately.")
        #endif
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
