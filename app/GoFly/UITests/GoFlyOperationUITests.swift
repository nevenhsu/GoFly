import XCTest

@MainActor
final class GoFlyOperationUITests: XCTestCase {
    func testPreparingCancelWaitsForReturnAndPreservesPointAndStartSources() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test uses the simulator's delayed deviceRequired failure; physical checks are deferred.")
        #else
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-preparation-delay"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        let selected = pin.value as? String
        app.buttons["map.candidate.go"].tap()
        XCTAssertTrue(app.staticTexts["operation.attempt"].waitForExistence(timeout: 5))
        XCTAssertTrue(source(app).contains("|point|"))
        XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled)
        app.buttons["operation.cancel"].tap()
        assertCancellationWaitingIfPresent(app)
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        XCTAssertEqual(query.value as? String, "25.0478, 121.5170")
        XCTAssertEqual(pin.value as? String, selected)
        XCTAssertTrue(app.buttons["map.candidate.go"].isEnabled)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)

        app.buttons["map.serviceControl"].tap()
        XCTAssertTrue(app.staticTexts["operation.attempt"].waitForExistence(timeout: 5))
        XCTAssertTrue(source(app).contains("|start|"))
        XCTAssertEqual(app.staticTexts["operation.source"].label, "Prepares the service without changing location.")
        XCTAssertEqual(pin.value as? String, selected)
        app.buttons["operation.cancel"].tap()
        assertCancellationWaitingIfPresent(app)
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        XCTAssertEqual(pin.value as? String, selected)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "04-cancel-preserves-search-and-candidate")
        #endif
    }

    func testFailedRetryUsesOriginalSnapshotAfterBrowsingAnotherCandidate() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This failure-path test uses the simulator's real deviceRequired adapter; no device ACK is simulated.")
        #else
        let app = makeApp()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        app.buttons["map.candidate.go"].tap()
        let error = app.staticTexts["map.serviceError.message"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("prepared physical iPhone"))
        let original = source(app).components(separatedBy: "|")
        XCTAssertEqual(original.count, 6)
        XCTAssertEqual(original.last, "3")
        let firstCandidate = pin.value as? String
        let originalSummary = "Destination: \(firstCandidate ?? "")"
        XCTAssertEqual(app.staticTexts["operation.source"].label, originalSummary)
        let metrics = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(metrics.count, 6)
        guard metrics.count == 6, original.count == 6 else { return }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: metrics[0] + min(60, metrics[4] / 4), dy: metrics[1])).tap()
        let browsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (pin.value as? String) != firstCandidate
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [browsed], timeout: 5), .completed)
        let newerCandidate = pin.value as? String
        XCTAssertEqual(app.staticTexts["operation.source"].label, originalSummary)
        app.buttons["operation.retry"].tap()
        let newRound = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = self.source(app).components(separatedBy: "|")
            return current.count == 6 && current[0] != original[0] && current.last == "3"
                && app.buttons["operation.retry"].isEnabled
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [newRound], timeout: 10), .completed)
        let retried = source(app).components(separatedBy: "|")
        XCTAssertEqual(Array(retried.dropFirst().dropLast()), Array(original.dropFirst().dropLast()),
                       "Retry must keep the original point intent, candidate identity and coordinate.")
        XCTAssertEqual(pin.value as? String, newerCandidate)
        XCTAssertEqual(app.staticTexts["operation.source"].label, originalSummary)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, name: "04-failed-original-source-retry-dark")
        app.buttons["map.serviceError.dismiss"].tap()
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, newerCandidate)
        XCTAssertFalse(error.exists)
        #endif
    }

    func testLargeDarkFailurePanelKeepsActionsAndPinReachable() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test uses the simulator deviceRequired failure; physical verification is deferred.")
        #else
        let app = makeApp()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        let go = app.buttons["map.candidate.go"]
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        go.tap()
        XCTAssertTrue(app.staticTexts["map.serviceError.message"].waitForExistence(timeout: 10))
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let v = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
            return v.count == 6 && v[4] > 0 && v[5] > 0
                && abs(v[0] - v[2]) < 3 && abs(v[1] - v[3]) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 8), .completed)
        let v = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
        if v.count == 6 {
            let visible = CGRect(x: v[0] - v[4] / 2, y: v[1] - v[5] / 2,
                                 width: v[4], height: v[5]).insetBy(dx: -3, dy: -3)
            XCTAssertTrue(visible.contains(go.frame), "Go must remain above Pin inside the actual map viewport.")
        }
        XCTAssertTrue(pin.isHittable)
        let panel = app.scrollViews["operation.panel"]
        let error = app.staticTexts["map.serviceError.message"]
        for _ in 0..<3 where !error.isHittable { panel.swipeUp() }
        attach(app, name: "04-large-dark-failure-reason")
        let retry = app.buttons["operation.retry"]
        revealFully(retry, in: panel)
        attach(app, name: "04-large-dark-failure-retry")
        let cancel = app.buttons["map.serviceError.dismiss"]
        revealFully(cancel, in: panel)
        XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
        attach(app, name: "04-large-dark-failure-actions")
        cancel.tap()
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertEqual(query.value as? String, "25.0478, 121.5170")
        XCTAssertTrue(pin.isHittable)
        #endif
    }

    private func assertCancellationWaitingIfPresent(_ app: XCUIApplication) {
        // The real native return may finish between UI snapshots. While still
        // pending, cancellation cannot enable another native operation.
        if app.buttons["operation.cancel"].exists {
            XCTAssertFalse(app.buttons["operation.cancel"].isEnabled)
            XCTAssertFalse(app.buttons["map.serviceControl"].isEnabled)
            XCTAssertFalse(app.buttons["map.candidate.go"].isEnabled)
        }
    }

    private func revealFully(_ action: XCUIElement, in panel: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            let viewport = panel.frame.insetBy(dx: -1, dy: -1)
            if action.isHittable && viewport.contains(action.frame) { return }
            if action.frame.midY < viewport.midY { panel.swipeDown() }
            else { panel.swipeUp() }
        }
        XCTAssertTrue(action.isHittable, file: file, line: line)
        XCTAssertTrue(panel.frame.insetBy(dx: -1, dy: -1).contains(action.frame),
                      "The complete action must be inside the panel viewport. Action: \(action.frame); panel: \(panel.frame)",
                      file: file, line: line)
    }

    private func source(_ app: XCUIApplication) -> String {
        app.staticTexts["operation.sourceMetrics"].label
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-map-metrics",
                               "-gofly-ui-operation-metrics", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
