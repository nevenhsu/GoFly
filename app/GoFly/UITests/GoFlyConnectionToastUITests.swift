import XCTest

/// Connection lost is an error toast with the shared 重試; the GPS-not-allowed warning toast is gone.
final class GoFlyConnectionToastUITests: GoFlyRouteModeTestCase {
    func testConnectionLostToastIsAnErrorWithARetryButton() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let toast = element(app, "recovery.connectionBanner")
            XCTAssertTrue(element(app, "recovery.notice").label.contains("連線無法使用"))
            XCTAssertEqual(element(app, "recovery.connectionBanner.message").label, "請確認 Wi-Fi 與 VPN 後重試。")
            let action = element(app, "recovery.checkConnection")
            XCTAssertEqual(action.label, "重試", "two-character toast button")
            XCTAssertTrue((60...96).contains(toast.frame.height), "short message keeps the toast compact, got \(toast.frame.height)")
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
