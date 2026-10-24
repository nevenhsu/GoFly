import XCTest

/// B10: the missing Wi-Fi toast is the danger Toast with a 重試 pill, 8 pt below the status pill.
final class GoFlyWiFiToastUITests: GoFlyRouteModeTestCase {
    func testWiFiToastMatchesB10() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-wifi-disconnected"], appearance: appearance)
            let toast = element(app, "map.wifiError")
            let pill = element(app, "map.statusPill")
            XCTAssertEqual(element(app, "map.wifiError.title").label.hasSuffix("需要連接 Wi-Fi"), true)
            XCTAssertEqual(element(app, "map.wifiError.message").label, "GoFly 需要連接與 Mac 相同的區域 Wi-Fi 才能進行模擬同步。")
            let action = element(app, "map.wifiError.action")
            XCTAssertEqual(action.label, "重試")
            XCTAssertGreaterThanOrEqual(action.frame.width, 56)
            XCTAssertEqual(action.frame.height, 32, accuracy: 1)
            XCTAssertEqual(toast.frame.minY - pill.frame.maxY, 8, accuracy: 1.5, "toast sits 8 pt below the status pill")
            XCTAssertEqual(toast.frame.width, app.frame.width - 32, accuracy: 1)
            XCTAssertEqual(toast.frame.height, 85, accuracy: 3, "two-line description: 85 pt in Figma")
            evidence(app, task: "B10", name: "wifi-toast-\(appearance)")
            app.terminate()
        }
    }
}
