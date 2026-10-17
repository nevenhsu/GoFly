import XCTest

@MainActor
final class GoFlyWaypointUITests: XCTestCase {
    func testProvisionalNodesAndExplicitCurrentClearPreserveIdentityWithoutPhantomRows() throws {
        try simulatorOnly()
        let app = makeApp(count: 1)
        app.launch()
        openRoute(app)
        let original = nodeIDs(app)
        XCTAssertEqual(original.count, 1)
        XCTAssertEqual(app.buttons["route.addNode"].label, "Add destination")
        app.buttons["route.addNode"].tap()
        enter(app, "25.0330, 121.5654")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), original)
        XCTAssertFalse(app.buttons["route.node.destination"].exists)

        app.buttons["route.node.start"].tap()
        revealClear(app)
        app.buttons["route.picker.clearPlace"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["route.picker.current"].value as? String, "0")
        XCTAssertTrue(app.buttons["route.picker.confirm"].isEnabled)
        let current = app.descendants(matching: .any)["route.picker.current"]
        revealPickerAction(current, app: app)
        current.tap()
        XCTAssertEqual(current.value as? String, "1")
        current.tap()
        XCTAssertEqual(current.value as? String, "0")
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled,
                       "Choosing current location and then deselecting it must not revive an older clear intent.")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), original)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")

        app.buttons["route.node.start"].tap()
        revealClear(app)
        app.buttons["route.picker.clearPlace"].tap()
        app.buttons["route.picker.confirm"].tap()
        XCTAssertTrue(app.buttons["route.addNode"].waitForExistence(timeout: 5))
        XCTAssertEqual(nodeIDs(app), [])
        XCTAssertEqual(app.buttons["route.addNode"].label, "Add origin")
        XCTAssertFalse(app.buttons["route.node.start"].exists)
        XCTAssertFalse(app.buttons["route.start"].isEnabled)
        app.buttons["route.addNode"].tap()
        enter(app, "25.0478, 121.5170")
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(nodeIDs(app).count, 1)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.buttons["route.addNode"].label, "Add destination")
        app.buttons["route.addNode"].tap()
        enter(app, "25.0330, 121.5654")
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(nodeIDs(app).count, 2)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        attach(app, "07-zero-origin-destination-confirmed-only")
    }

    func testExplicitClearIntentCannotReviveThroughInvalidQueryAndKeywordClear() throws {
        try simulatorOnly()
        let app = makeApp(count: 3)
        app.launch()
        openRoute(app)
        let original = nodeIDs(app)
        XCTAssertEqual(original.count, 3)
        let middle = app.buttons["route.node.waypoint.1"]
        let savedValue = middle.value as? String
        middle.tap()
        revealClear(app)
        app.buttons["route.picker.clearPlace"].tap()
        enter(app, "91, 121")
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled)
        let queryClear = app.buttons["search.clear"]
        XCTAssertTrue(queryClear.waitForExistence(timeout: 5))
        queryClear.tap()
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled,
                       "Normal keyword clear must not revive an earlier explicit place-clear intent.")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), original)
        XCTAssertEqual(middle.value as? String, savedValue)

        middle.tap()
        revealClear(app)
        app.buttons["route.picker.clearPlace"].tap()
        enter(app, "25.0400, 121.5300")
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(nodeIDs(app), original, "A fresh valid selection wins over the previous clear intent.")
        XCTAssertEqual(middle.value as? String, "25.040000, 121.530000")
        middle.tap()
        revealClear(app)
        app.buttons["route.picker.clearPlace"].tap()
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(nodeIDs(app), [original[0], original[2]])
        XCTAssertFalse(middle.exists)
        app.buttons["route.delete.\(original[0])"].tap()
        XCTAssertEqual(nodeIDs(app), [original[2]])
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.004000, 121.504000")
        app.buttons["route.delete.\(original[2])"].tap()
        XCTAssertEqual(nodeIDs(app), [])
        XCTAssertEqual(app.buttons["route.addNode"].label, "Add origin")
        attach(app, "07-clear-query-delete-stable-identities")
    }

    func testHandleOnlyDragMovesWholeNodeAndSeparateTargetsRemain44Points() throws {
        try simulatorOnly()
        let app = makeApp(count: 3)
        app.launch()
        openRoute(app)
        let original = nodeIDs(app)
        XCTAssertEqual(original.count, 3)
        guard original.count == 3 else { return }
        let handle = app.descendants(matching: .any)["route.handle.\(original[0])"]
        let edit = app.buttons["route.node.start"]
        let delete = app.buttons["route.delete.\(original[0])"]
        for target in [handle, edit, delete] {
            XCTAssertGreaterThanOrEqual(target.frame.width, 44)
            XCTAssertGreaterThanOrEqual(target.frame.height, 44)
        }
        XCTAssertLessThanOrEqual(handle.frame.maxX, edit.frame.minX + 0.5)
        XCTAssertLessThanOrEqual(edit.frame.maxX, delete.frame.minX + 0.5)
        XCTAssertTrue(handle.label.contains("Origin"))
        XCTAssertTrue(handle.label.contains("Current location"))
        XCTAssertEqual(delete.label, "Delete Origin")
        edit.tap()
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), original, "Editing the middle target must not reorder the node.")

        let destination = app.descendants(matching: .any)["route.handle.\(original[2])"]
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5,
                   thenDragTo: destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        waitForOrder(app, [original[1], original[2], original[0]])
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "Current location")
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "25.002000, 121.502000")
        app.buttons["route.node.destination"].tap()
        XCTAssertTrue(app.staticTexts["route.picker.existingCurrent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["route.picker.current"].exists,
                       "Current location moves with its node, but a non-first role cannot introduce another current choice.")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(nodeIDs(app), [original[1], original[2], original[0]])
        attach(app, "07-handle-drag-whole-current-node-reassigned-role")
    }

    func testTwentySevenNodeEdgeAutoscrollCommitsOneStableOrderAndDeletionReenablesAdd() throws {
        try simulatorOnly()
        let app = makeApp(count: 27)
        app.launch()
        openRoute(app)
        let original = nodeIDs(app)
        XCTAssertEqual(original.count, 27)
        guard original.count == 27 else { return }
        XCTAssertFalse(app.buttons["route.addNode"].isEnabled)
        let viewport = nodeViewport(app)
        XCTAssertGreaterThan(viewport.height, 72)
        let handle = app.descendants(matching: .any)["route.handle.\(original[0])"]
        XCTAssertTrue(handle.isHittable)
        let edge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: handle.frame.midX, dy: viewport.maxY - 12))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: edge, withVelocity: .slow, thenHoldForDuration: 5)
        let expected = Array(original.dropFirst()) + [original[0]]
        waitForOrder(app, expected)
        XCTAssertEqual(Set(nodeIDs(app)), Set(original))
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "Current location")
        XCTAssertFalse(app.buttons["route.addNode"].isEnabled)
        attach(app, "07-twenty-seven-node-edge-autoscroll")
        let delete = app.buttons["route.delete.\(original[0])"]
        if !delete.isHittable { app.descendants(matching: .any)["route.panel.content"].swipeUp() }
        delete.tap()
        XCTAssertEqual(nodeIDs(app), Array(original.dropFirst()))
        XCTAssertTrue(app.buttons["route.addNode"].isEnabled)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Multi-node UI tests use editable initial data only; phone/VoiceOver/OS gesture cancellation checks are deferred.")
        #endif
    }
    private func makeApp(count: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-map-metrics", "-gofly-ui-route-draft-count", String(count),
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }
    private func openRoute(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["mode.route"].waitForExistence(timeout: 10))
        app.buttons["mode.route"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["route.panel"].waitForExistence(timeout: 5))
    }
    private func nodeIDs(_ app: XCUIApplication) -> [String] {
        let metric = app.staticTexts["route.nodes.order"]
        guard metric.exists else { return [] }
        return metric.label.split(separator: ",").map(String.init)
    }
    private func nodeViewport(_ app: XCUIApplication) -> CGRect {
        let values = app.staticTexts["route.nodes.viewport"].label.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    private func waitForOrder(_ app: XCUIApplication, _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.nodeIDs(app) == expected }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed,
                       "Actual stable node order: \(nodeIDs(app))", file: file, line: line)
    }
    private func enter(_ app: XCUIApplication, _ coordinate: String) {
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        query.tap()
        let old = query.value as? String ?? ""
        let count = old == "Search places, addresses or coordinates" ? 0 : old.count
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + coordinate)
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }
    private func revealClear(_ app: XCUIApplication) {
        revealPickerAction(app.buttons["route.picker.clearPlace"], app: app)
    }
    private func revealPickerAction(_ element: XCUIElement, app: XCUIApplication) {
        let metric = app.staticTexts["route.picker.viewportMetrics"]
        for _ in 0..<5 {
            let values = metric.label.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { return XCTFail("The actual picker viewport is required.") }
            let viewport = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            if element.exists, element.isHittable, viewport.contains(element.frame) { break }
            let base = app.coordinate(withNormalizedOffset: .zero)
            base.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + 10))
                .press(forDuration: 0.01, thenDragTo: base.withOffset(CGVector(dx: viewport.midX, dy: viewport.maxY - 10)))
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
