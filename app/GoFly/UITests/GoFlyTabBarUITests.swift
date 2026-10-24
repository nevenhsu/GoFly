import XCTest

/// C6 TabBar in the simulator gallery and the real map screen.
final class GoFlyTabBarUITests: GoFlyRouteModeTestCase {
    func testTabBarMatchesSpecAndMapScreen() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let bar = element(app, "map.bottomBar")
            XCTAssertEqual(bar.frame.height, 83, accuracy: 1, "tab bar is 83 pt including home indicator")
            XCTAssertEqual(bar.frame.maxY, app.frame.maxY, accuracy: 1)
            let tabs = ["teleport", "route", "joystick"].map { app.buttons["mode.\($0)"] }
            for tab in tabs {
                XCTAssertTrue(tab.exists)
                XCTAssertEqual(tab.frame.width, app.frame.width / 3, accuracy: 1)
                XCTAssertGreaterThanOrEqual(tab.frame.height, 49)
            }
            app.selectGoFlyMode("route")
            XCTAssertTrue(app.buttons["mode.route"].isSelected)
            XCTAssertFalse(app.buttons["mode.teleport"].isSelected)
            evidence(app, task: "C6", name: "tabbar-route-\(appearance)")
            app.terminate()
        }
    }
}
