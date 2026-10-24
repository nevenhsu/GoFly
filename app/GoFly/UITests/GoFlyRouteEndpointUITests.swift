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
            XCTAssertEqual(destination.value as? String, "選擇終點")

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
}
