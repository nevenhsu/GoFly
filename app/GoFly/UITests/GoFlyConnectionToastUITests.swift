import XCTest

/// Connection lost is an error toast with the shared 重試; the GPS-not-allowed warning toast is gone.
final class GoFlyConnectionToastUITests: GoFlyRouteModeTestCase {
    func testConnectionLostToastIsAnErrorWithARetryButton() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let toast = element(app, "recovery.connectionBanner")
            XCTAssertTrue(element(app, "recovery.notice").label.contains("連線無法使用"))
            let action = element(app, "recovery.checkConnection")
            XCTAssertEqual(action.label, "重試", "two-character toast button")
            XCTAssertGreaterThan(toast.frame.height, 60)
            XCTAssertFalse(app.descendants(matching: .any)["map.locationNotice"].exists, "no GPS-not-allowed toast")
            evidence(app, task: "T", name: "connection-lost-\(appearance)")
            app.terminate()
        }
    }

    func testNoGPSWarningToastInJoystickEither() throws {
        let app = launch()
        app.selectGoFlyMode("joystick")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertFalse(app.descendants(matching: .any)["map.locationNotice"].exists)
    }
}
