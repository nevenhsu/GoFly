import XCTest

/// R2: start and destination rows are always present, can be empty, and are cleared (not removed) by ✕.
final class GoFlyRouteEndpointUITests: GoFlyRouteModeTestCase {
    func testEndpointRowsClearInPlaceAndStartStaysDisabled() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            app.selectGoFlyMode("route")
            let start = element(app, "route.node.start")
            let destination = element(app, "route.node.destination")
            XCTAssertEqual(start.value as? String, "目前位置")
            XCTAssertEqual(destination.value as? String, "選擇目的地")

            let removes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route.delete.'"))
            XCTAssertEqual(removes.count, 2, "start and destination always show ✕")
            XCTAssertTrue(removes.element(boundBy: 0).isEnabled, "a filled start can be cleared")
            XCTAssertFalse(removes.element(boundBy: 1).isEnabled, "an empty destination ✕ is disabled")
            XCTAssertFalse(app.buttons["route.start"].isEnabled)
            if appearance == "light" { evidence(app, task: "R2", name: "endpoints-default-\(appearance)") }

            removes.element(boundBy: 0).tap()
            XCTAssertEqual(element(app, "route.node.start").value as? String, "選擇起點")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route.delete.'")).count, 2,
                           "the cleared row stays")
            XCTAssertFalse(removes.element(boundBy: 0).isEnabled)
            XCTAssertFalse(app.buttons["route.start"].isEnabled)
            evidence(app, task: "R2", name: "endpoints-cleared-\(appearance)")
            app.terminate()
        }
    }

    func testVoiceOverLabelsDistinguishClearFromDelete() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        let removes = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'route.delete.'"))
        XCTAssertTrue(removes.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertEqual(removes.element(boundBy: 0).label, "清除起點")
        XCTAssertEqual(removes.element(boundBy: 1).label, "清除終點")
    }

    func testAddingWaypointFromPanelAndAllPointsCreatesSelectedDestinationInBothAppearances() throws {
        for appearance in ["light", "dark"] {
            let panelApp = launch(["-gofly-ui-frame", "D2"], appearance: appearance)
            element(panelApp, "route.addNode").tap()
            assertAppendedDestination(panelApp)
            try figmaEvidence(panelApp, ticket: "10", name: "D2-panel-add-stop-\(appearance)")
            openDestinationSearch(panelApp)
            panelApp.terminate()

            let listApp = launch(["-gofly-ui-frame", "D2"], appearance: appearance)
            element(listApp, "route.viewList").tap()
            XCTAssertTrue(element(listApp, "route.list").exists)
            element(listApp, "route.list.addWaypoint").tap()
            assertAppendedDestination(listApp)
            try figmaEvidence(listApp, ticket: "10", name: "D2-all-points-add-stop-\(appearance)")
            openDestinationSearch(listApp)
            listApp.terminate()
        }
    }

    func testD8PlanningFailureActionAndAutomaticRepairInBothAppearances() throws {
        for appearance in ["light", "dark"] {
            let failedApp = launch(["-gofly-ui-frame", "D8", "-gofly-ui-route-outcome", "planningFailed"],
                                   appearance: appearance)
            let failure = element(failedApp, "route.error")
            XCTAssertTrue(element(failedApp, "route.error.title").label.contains("無法規劃路線"))
            XCTAssertTrue(element(failedApp, "route.error.message").label.contains("點選修正"))
            XCTAssertTrue(element(failedApp, "map.statusPill").label.contains("啟動"),
                           "D8 keeps the session pill at Started while its route toast reports planning failure")
            let fix = failedApp.buttons["route.error.action"]
            XCTAssertEqual(fix.label, "修正")
            XCTAssertGreaterThanOrEqual(fix.frame.height, 44)
            XCTAssertTrue(failedApp.buttons["route.start"].isEnabled,
                          "a non-connection planning error must not disable Start")
            try figmaEvidence(failedApp, ticket: "11", name: "D8-failure-\(appearance)")

            let originalStart = element(failedApp, "route.node.start").value as? String
            let originalWaypoint = element(failedApp, "route.node.waypoint.1").value as? String
            let originalDestination = element(failedApp, "route.node.destination").value as? String
            fix.tap()
            XCTAssertTrue(failure.waitForExistence(timeout: 10), "an unsuccessful search keeps the toast")
            XCTAssertEqual(element(failedApp, "route.node.start").value as? String, originalStart)
            XCTAssertEqual(element(failedApp, "route.node.waypoint.1").value as? String, originalWaypoint)
            XCTAssertEqual(element(failedApp, "route.node.destination").value as? String, originalDestination)
            try figmaEvidence(failedApp, ticket: "11", name: "D8-failure-retained-\(appearance)")
            failedApp.terminate()

            let repairedApp = launch(["-gofly-ui-frame", "D8", "-gofly-ui-route-outcome", "reorderedSuccess"],
                                     appearance: appearance)
            let repairedBanner = element(repairedApp, "route.error")
            XCTAssertEqual(repairedApp.buttons["route.error.action"].label, "修正")
            repairedApp.buttons["route.error.action"].tap()
            let disappeared = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: repairedBanner)
            XCTAssertEqual(XCTWaiter.wait(for: [disappeared], timeout: 10), .completed)
            XCTAssertEqual(element(repairedApp, "route.node.start").value as? String, "目前位置")
            XCTAssertEqual(element(repairedApp, "route.node.waypoint.1").value as? String, "選擇目的地")
            XCTAssertEqual(element(repairedApp, "route.node.destination").value as? String, "台北 101")
            XCTAssertTrue(repairedApp.buttons["route.start"].exists)
            try figmaEvidence(repairedApp, ticket: "11", name: "D8-repaired-\(appearance)")
            repairedApp.terminate()
        }
    }

    func testD7SpeedSheetUsesTwentyPointTopAndFortyPointBottomInsets() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-frame", "D7"], appearance: appearance)
            let speed = app.buttons["route.speedChip"]
            XCTAssertTrue(speed.waitForExistence(timeout: 20))
            speed.tap()

            let confirm = app.buttons["route.speed.confirm"]
            let lowerSliderLabel = app.staticTexts["120 km/h"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 10))
            XCTAssertTrue(lowerSliderLabel.waitForExistence(timeout: 10))
            let topGap = confirm.frame.minY - lowerSliderLabel.frame.maxY
            let bottomGap = app.windows.firstMatch.frame.maxY - confirm.frame.maxY
            XCTAssertGreaterThanOrEqual(topGap, 24)
            XCTAssertLessThanOrEqual(topGap, 30)
            XCTAssertGreaterThanOrEqual(bottomGap, 36)
            XCTAssertLessThanOrEqual(bottomGap, 44)

            try figmaEvidence(app, ticket: "12", name: "D7-speed-sheet-spacing-\(appearance)")
            app.terminate()
        }

        let largeTextApp = launch(["-gofly-ui-frame", "D7"], appearance: "dark", largeText: true)
        let speed = largeTextApp.buttons["route.speedChip"]
        XCTAssertTrue(speed.waitForExistence(timeout: 20))
        speed.tap()
        let confirm = largeTextApp.buttons["route.speed.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(largeTextApp.sliders["route.speed"].isHittable)
        let window = largeTextApp.windows.firstMatch
        XCTAssertGreaterThanOrEqual(confirm.frame.minY, window.frame.minY)
        XCTAssertLessThanOrEqual(confirm.frame.maxY, window.frame.maxY)
        try figmaEvidence(largeTextApp, ticket: "12", name: "D7-speed-sheet-accessibility-large-text")
        largeTextApp.terminate()
    }

    private func assertAppendedDestination(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let originalDestination = app.buttons["route.node.waypoint.4"]
        let newDestination = app.buttons["route.node.destination"]
        XCTAssertTrue(originalDestination.waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertEqual(originalDestination.value as? String, "松山機場", file: file, line: line)
        XCTAssertTrue(newDestination.waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertEqual(newDestination.value as? String, "選擇目的地", file: file, line: line)
        XCTAssertTrue(newDestination.isSelected, "the new blank endpoint is selected", file: file, line: line)
        XCTAssertGreaterThanOrEqual(newDestination.frame.height, 44, file: file, line: line)
    }

    private func openDestinationSearch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let destination = app.buttons["route.node.destination"]
        destination.tap()
        destination.tap()
        XCTAssertTrue(element(app, "search.role").waitForExistence(timeout: 8), file: file, line: line)
        XCTAssertTrue(app.staticTexts["正在選：終點"].exists, file: file, line: line)
    }
}
