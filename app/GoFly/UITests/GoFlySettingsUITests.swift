import XCTest

@MainActor
final class GoFlySettingsUITests: XCTestCase {
    func testLanguagePickerCommitsTraditionalChinese() {
        let app = launch(languageSeed: "en", appearanceSeed: "light")
        openSettings(app)
        let link = app.buttons["settings.language"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        let language = languageRow(app)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        XCTAssertTrue(pickerValue(language)?.contains("English") == true)
        language.tap()
        tapMenuOption("繁體中文", app)
        XCTAssertTrue(pickerValue(languageRow(app))?.contains("繁體中文") == true)
    }

    func testAppearancePickerCommitsDark() {
        let app = launch(appearanceSeed: "system")
        openSettings(app)
        let link = app.buttons["settings.appearance"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        link.tap()
        let appearance = appearanceRow(app)
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        scrollIntoView(appearance, app)
        appearance.tap()
        tapMenuOption("Dark", app)
        XCTAssertTrue(pickerValue(appearanceRow(app))?.contains("Dark") == true)
    }

    private func launch(languageSeed: String? = nil, appearanceSeed: String? = nil) -> XCUIApplication {
        var arguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        if let languageSeed { arguments += ["-gofly-ui-preferences-language", languageSeed] }
        if let appearanceSeed { arguments += ["-gofly-ui-preferences-appearance", appearanceSeed] }
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
        app.buttons["map.settings"].tap()
    }

    private func scrollIntoView(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            if element.frame.minY < 100 { app.swipeDown() } else { app.swipeUp() }
        }
    }

    private func languageRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.language"]
    }

    private func appearanceRow(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.appearance"]
    }

    private func pickerValue(_ element: XCUIElement) -> String? {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label.isEmpty ? nil : element.label
    }

    private func tapMenuOption(_ title: String, _ app: XCUIApplication) {
        let option = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), title)
        option.tap()
    }
}
