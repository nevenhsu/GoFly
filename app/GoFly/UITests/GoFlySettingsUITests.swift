import XCTest

@MainActor
final class GoFlySettingsUITests: XCTestCase {
    func testLanguagePickerCommitsTraditionalChinese() {
        let app = launch(languageSeed: "en", appearanceSeed: "light")
        openSettings(app)
        let language = languageRow(app)
        XCTAssertEqual(pickerValue(language), "English")
        language.tap()
        tapMenuOption("繁體中文", app)
        XCTAssertEqual(pickerValue(languageRow(app)), "繁體中文")
    }

    func testAppearancePickerCommitsDark() {
        let app = launch(appearanceSeed: "system")
        openSettings(app)
        let appearance = appearanceRow(app)
        scrollIntoView(appearance, app)
        appearance.tap()
        tapMenuOption("Dark", app)
        XCTAssertEqual(pickerValue(appearanceRow(app)), "Dark")
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
        let language = languageRow(app)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        for _ in 0..<8 where !language.isHittable { app.swipeUp() }
        XCTAssertTrue(language.isHittable)
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
