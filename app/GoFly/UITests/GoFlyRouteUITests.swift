import XCTest

@MainActor
final class GoFlyRouteUITests: XCTestCase {
    private let origin = "25.047800, 121.517000"
    private let destination = "25.033000, 121.565400"

    func testPickerConfirmationCancellationAndImmediateFavoriteStaySeparate() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
        XCTAssertFalse(app.buttons["route.start"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["route.error"].exists)
        XCTAssertFalse(app.sliders["route.speed"].exists)
        app.buttons["route.node.destination"].tap()
        let emptyQuery = app.textFields["search.query"]
        XCTAssertTrue(emptyQuery.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Opening a node should focus search automatically.")
        emptyQuery.tap()
        XCTAssertTrue(app.buttons["favorites.open"].exists)
        enter(app, "25.0330, 121.5654")
        XCTAssertFalse(app.buttons["favorites.open"].exists)
        XCTAssertTrue(app.buttons["map.candidate.pin"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["map.candidate.pin"].value as? String, destination)
        XCTAssertGreaterThanOrEqual(app.buttons["map.candidate.pin"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["map.candidate.pin"].frame.height, 44)
        XCTAssertFalse(app.buttons["map.candidate.go"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["route.picker.current"].exists)
        let star = app.buttons["search.favorite.\(destination)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(star.frame.width, 44)
        XCTAssertGreaterThanOrEqual(star.frame.height, 44)
        star.tap()
        XCTAssertEqual(star.value as? String, "Favorite")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, "Choose destination")
        app.buttons["route.node.destination"].tap()
        app.buttons["favorites.open"].tap()
        let saved = app.buttons["favorites.place.\(destination)"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.buttons["route.picker.confirm"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["route.picker.confirm"].isEnabled, true)
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        app.buttons["route.node.start"].tap()
        let current = app.descendants(matching: .any)["route.picker.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(current.frame.height, 44)
        XCTAssertEqual(current.value as? String, "1")
        current.tap()
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, "Current location")
        app.buttons["route.node.start"].tap()
        enter(app, "25.0478, 121.5170")
        XCTAssertEqual(app.descendants(matching: .any)["route.picker.current"].value as? String, "0")
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, origin)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        attach(app, "06-two-confirmed-nodes")
        app.buttons["route.node.destination"].tap()
        enter(app, "91, 121")
        XCTAssertTrue(app.staticTexts["search.inputError"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled)
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        app.buttons["route.node.destination"].tap()
        enter(app, "Unselected destination " + UUID().uuidString, dismissKeyboard: false)
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled,
                       "A new name search cannot confirm the previously seeded, hidden place.")
        XCTAssertTrue(app.buttons["favorites.open"].waitForExistence(timeout: 5))
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        let chosenCard = app.buttons["search.result.\(destination)"]
        XCTAssertTrue(chosenCard.waitForExistence(timeout: 5))
        XCTAssertTrue(chosenCard.isSelected, "A favorite chosen from an empty result list must become the visible selected option.")
        XCTAssertTrue(app.buttons["route.picker.confirm"].isEnabled)
        app.buttons["route.picker.confirm"].tap()
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        app.buttons["route.node.destination"].tap()
        enter(app, "Unselected replacement " + UUID().uuidString, dismissKeyboard: false)
        XCTAssertFalse(app.buttons["route.picker.confirm"].isEnabled)
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testMapPickedPlaceFillsInputAndPinWithoutGoAndOnlyConfirmationChangesNode() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openRoute(app)
        app.buttons["route.node.destination"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissKeyboard(app)
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.25)).tap()
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        assertCentered(app)
        guard let firstCoordinate = pin.value as? String else { return XCTFail("Map selection must expose its real coordinate.") }
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertNotEqual(query.value as? String, "Search places, addresses or coordinates")
        XCTAssertFalse((query.value as? String ?? "").isEmpty)
        XCTAssertFalse(app.buttons["map.candidate.go"].exists)
        XCTAssertTrue(app.buttons["route.picker.confirm"].isEnabled)
        attach(app, "06-map-place-input-pin-confirm-only")
        app.buttons["route.picker.confirm"].tap()
        XCTAssertTrue(app.buttons["route.node.destination"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons["route.node.destination"].value as? String, "Choose destination")
        app.buttons["route.node.destination"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, firstCoordinate)
        dismissKeyboard(app)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            pin.exists && (pin.value as? String) != firstCoordinate
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["map.candidate.go"].exists)
        app.buttons["route.picker.cancel"].tap()
        app.buttons["route.node.destination"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, firstCoordinate, "Cancelling another map selection must preserve the confirmed node coordinate.")
        app.buttons["route.picker.cancel"].tap()
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testSpeedDetailsAndPlanningCancellationPreserveDraftThroughLateFailure() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-route-planning-delay"]
        app.launch()
        openRoute(app)
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.sliders["route.speed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "20 km/h")
        app.sliders["route.speed"].adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, "100 km/h")
        app.sliders["route.speed"].adjust(toNormalizedSliderPosition: 0)
        let lowSpeed = app.staticTexts["route.speed.value"].label
        let lowValue = Int(lowSpeed.components(separatedBy: " ")[0]) ?? 0
        // XCTest's synthesized drag ends within a few pixels of the native thumb edge.
        XCTAssertTrue((2...4).contains(lowValue))
        attach(app, "06-speed-details-native-slider")
        app.buttons["route.details.back"].tap()
        setNode(app, "route.node.start", "25.0478, 121.5170")
        setNode(app, "route.node.destination", "25.0330, 121.5654")
        app.buttons["route.start"].tap()
        let cancel = app.buttons["route.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route.node.start"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["map.mode"].exists)
        attach(app, "06-planning-cancellable")
        cancel.tap()
        XCTAssertTrue(app.buttons["route.node.start"].waitForExistence(timeout: 5))
        // A cancelled planner must never publish its eventual failure into this draft.
        let lateError = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.descendants(matching: .any)["route.error"].exists
        }, object: nil)
        lateError.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [lateError], timeout: 3), .completed)
        XCTAssertEqual(app.buttons["route.node.start"].value as? String, origin)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        app.buttons["route.details"].tap()
        XCTAssertTrue(app.staticTexts["route.speed.value"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["route.speed.value"].label, lowSpeed)
        app.buttons["route.details.back"].tap()
        app.buttons["route.start"].tap()
        let error = app.descendants(matching: .any)["route.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 8))
        XCTAssertTrue(error.label.contains("walking route could not be planned"))
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        XCTAssertTrue(app.buttons["route.start"].isEnabled)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        attach(app, "06-planning-failure-preserves-draft")
    }

    func testLargeDarkPickerKeepsKeyboardAndConfirmationReachable() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openRoute(app)
        let destinationNode = app.buttons["route.node.destination"]
        if !destinationNode.isHittable { app.scrollViews["route.panel"].swipeUp() }
        destinationNode.tap()
        enter(app, "25.0330, 121.5654", dismissKeyboard: false)
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        assertCentered(app)
        XCTAssertTrue(pin.isHittable)
        XCTAssertGreaterThanOrEqual(pin.frame.width, 44)
        XCTAssertGreaterThanOrEqual(pin.frame.height, 44)
        XCTAssertFalse(app.buttons["map.candidate.go"].exists)
        let confirm = app.buttons["route.picker.confirm"]
        if !confirm.isHittable { app.scrollViews["route.picker.content"].swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, app.maps.firstMatch.frame.maxY + 1,
                                 "The action must also fit within the keyboard-adjusted map surface, above keyboard accessories.")
        XCTAssertGreaterThanOrEqual(confirm.frame.minY, 0)
        let query = app.textFields["search.query"]
        let clear = app.buttons["search.clear"]
        let visibleInput = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let viewport = self.pickerViewport(app)
            return viewport.width > 0 && viewport.height > 0
                && viewport.contains(query.frame) && viewport.contains(clear.frame)
                && app.descendants(matching: .any)["search.panel"].frame.contains(query.frame)
                && app.descendants(matching: .any)["search.panel"].frame.contains(clear.frame)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visibleInput], timeout: 5), .completed,
                       "Full input and clear must fit inside actual route scroll viewport \(pickerViewport(app)); query \(query.frame), clear \(clear.frame).")
        XCTAssertGreaterThanOrEqual(clear.frame.width, 44)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        XCTAssertTrue(clear.isHittable)
        XCTAssertFalse(query.frame.intersects(confirm.frame))
        XCTAssertFalse(clear.frame.intersects(confirm.frame))
        attach(app, "06-max-dark-picker-keyboard")
        confirm.tap()
        XCTAssertTrue(destinationNode.waitForExistence(timeout: 5))
        XCTAssertEqual(destinationNode.value as? String, destination)
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Route UI tests use isolated simulator stores and failed planning only. Physical checks are deferred.")
        #endif
    }
    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-gofly.onboarding.complete", "YES", "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-map-metrics",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        return app
    }
    private func openRoute(_ app: XCUIApplication) {
        let mode = app.descendants(matching: .any)["map.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        for id in ["mode.teleport", "mode.route"] {
            let segment = app.buttons[id]
            XCTAssertGreaterThanOrEqual(segment.frame.height, 44, "Actual \(id) hit frame: \(segment.frame)")
            XCTAssertGreaterThanOrEqual(segment.frame.width, 44)
        }
        XCTAssertTrue(app.buttons["mode.teleport"].isSelected)
        app.buttons["mode.route"].tap()
        XCTAssertTrue(app.buttons["mode.route"].isSelected)
        XCTAssertTrue(app.buttons["route.node.destination"].waitForExistence(timeout: 5))
    }
    private func setNode(_ app: XCUIApplication, _ id: String, _ coordinate: String) {
        app.buttons[id].tap()
        enter(app, coordinate)
        app.buttons["route.picker.confirm"].tap()
        XCTAssertTrue(app.buttons[id].waitForExistence(timeout: 5))
    }
    private func enter(_ app: XCUIApplication, _ text: String, dismissKeyboard: Bool = true) {
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Opening a node should focus search automatically.")
        query.tap()
        let old = query.value as? String ?? ""
        let count = old == "Search places, addresses or coordinates" ? 0 : old.count
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
        if dismissKeyboard, app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
    }
    private func pickerViewport(_ app: XCUIApplication) -> CGRect {
        let values = app.staticTexts["route.picker.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return .zero }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
    private func assertCentered(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let values = app.staticTexts["map.viewportMetrics"].label.split(separator: ",").compactMap { Double($0) }
            return values.count == 6 && values[4] > 0 && values[5] > 0
                && abs(values[0] - values[2]) < 3 && abs(values[1] - values[3]) < 3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 8), .completed,
                       "The route edit Pin must center in the actual visible map.", file: file, line: line)
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
