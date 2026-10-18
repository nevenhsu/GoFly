import XCTest

@MainActor
final class GoFlyIconUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testProductionIconsInLightAndDarkAppearance() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Icon component preview is only compiled into the Debug simulator app.")
        #else
        for appearance in ["light", "dark"] {
            let app = launchPreview(appearance: appearance)
            XCTAssertTrue(app.staticTexts["iconPreview.title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["iconPreview.symbolAvailability"].label, "SF Symbols: OK")
            XCTAssertEqual(app.staticTexts["iconPreview.presentation"].label, "zh-Hant · \(appearance)")
            XCTAssertEqual(app.staticTexts["iconPreview.startup"].label, "Startup: idle")
            XCTAssertTrue(app.staticTexts["iconPreview.scope"].label.contains("不代表裝置、GPS 或 ACK 驗證"))
            XCTAssertFalse(app.buttons["map.serviceControl"].exists)
            for role in ["recenter", "settings", "favorite", "play", "pause"] {
                let control = app.buttons["iconPreview.control.\(role)"]
                XCTAssertTrue(control.isHittable)
                XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                XCTAssertGreaterThanOrEqual(control.frame.minX, 0)
                XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.width)
            }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "icon-components-zh-Hant-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let search = app.textFields["iconPreview.search"]
            if !search.isHittable {
                app.swipeUp()
                let inputAttachment = XCTAttachment(screenshot: app.screenshot())
                inputAttachment.name = "icon-input-zh-Hant-\(appearance)"
                inputAttachment.lifetime = .keepAlways
                add(inputAttachment)
            }
            XCTAssertTrue(search.isHittable)
            app.terminate()
        }
        #endif
    }

    private func launchPreview(appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-icon-preview",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-setup-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-preferences-appearance", appearance,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        return app
    }
}
