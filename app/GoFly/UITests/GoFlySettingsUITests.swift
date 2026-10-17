import XCTest

@MainActor
final class GoFlySettingsUITests: XCTestCase {
    func testSettingsExposesNativeLanguagePreferenceRow() {
        let app = launch()
        openSettings(in: app)
        XCTAssertTrue(languageRow(in: app).exists)
    }

    func testLanguagePickerShowsAutonymsAndCommitsSelection() {
        let app = launch(languageSeed: "en", appearanceSeed: "light")
        openSettings(in: app)
        attachSettingsScreenshot(app, name: "settings-c01-light")

        let language = languageRow(in: app)
        XCTAssertEqual(pickerValue(language), "English")
        language.tap()

        for option in ["System", "English", "繁體中文", "简体中文"] {
            let menuItem = menuOption(option, in: app)
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), option)
            XCTAssertTrue(menuItem.isHittable, option)
        }
        settleForScreenshot()
        attachSettingsScreenshot(app, name: "settings-language-menu-light")

        tapMenuOption("繁體中文", in: app)
        XCTAssertEqual(pickerValue(languageRow(in: app)), "繁體中文")
    }

    func testEveryLanguageChoiceCommitsItsSavedAutonym() {
        for (option, expected) in [
            ("System", "System"),
            ("English", "English"),
            ("繁體中文", "繁體中文"),
            ("简体中文", "简体中文")
        ] {
            let app = launch(languageSeed: "en")
            openSettings(in: app)
            let language = languageRow(in: app)
            language.tap()
            tapMenuOption(option, in: app)
            XCTAssertEqual(pickerValue(languageRow(in: app)), expected, option)
            app.terminate()
        }
    }

    func testEveryAppearanceChoiceCommitsItsSavedTitle() {
        for (option, expected) in [("System", "System"), ("Light", "Light"), ("Dark", "Dark")] {
            let app = launch(appearanceSeed: "system")
            openSettings(in: app)
            let appearance = appearanceRow(in: app)
            scrollIntoView(appearance, in: app)
            appearance.tap()
            tapMenuOption(option, in: app)
            XCTAssertEqual(pickerValue(appearanceRow(in: app)), expected, option)
            app.terminate()
        }
    }

    func testUnsupportedPreferenceSeedsFallBackToSystemAndUnsupportedSystemLanguageUsesEnglish() {
        let app = launch(languageSeed: "invalid-language", appearanceSeed: "invalid-appearance")
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["map.settings"].label, "Settings")
        openSettings(in: app)
        XCTAssertEqual(pickerValue(languageRow(in: app)), "System")
        let appearance = appearanceRow(in: app)
        scrollIntoView(appearance, in: app)
        XCTAssertEqual(pickerValue(appearance), "System")

        let unsupported = launch(languageSeed: "system", appleLanguage: "xx", appleLocale: "xx_XX")
        XCTAssertTrue(unsupported.buttons["map.settings"].waitForExistence(timeout: 10))
        XCTAssertEqual(unsupported.buttons["map.settings"].label, "Settings")
        openSettings(in: unsupported)
        XCTAssertEqual(languageRow(in: unsupported).label, "Language")
    }

    func testLanguagePickerDismissalLeavesSavedSelectionUnchanged() {
        let store = UUID().uuidString
        let app = launch(languageSeed: "en", store: store)
        openSettings(in: app)

        let language = languageRow(in: app)
        XCTAssertEqual(pickerValue(language), "English")
        language.tap()
        XCTAssertTrue(menuOption("繁體中文", in: app).waitForExistence(timeout: 5))
        app.navigationBars.firstMatch.tap()

        XCTAssertEqual(pickerValue(languageRow(in: app)), "English")
        app.terminate()

        let relaunched = launch(store: store)
        openSettings(in: relaunched)
        XCTAssertEqual(pickerValue(languageRow(in: relaunched)), "English")
    }

    func testLanguageSelectionPersistsAcrossRelaunch() {
        let store = UUID().uuidString
        let app = launch(languageSeed: "en", store: store)
        openSettings(in: app)

        let language = languageRow(in: app)
        language.tap()
        tapMenuOption("简体中文", in: app)
        XCTAssertEqual(pickerValue(languageRow(in: app)), "简体中文")
        app.terminate()

        let relaunched = launch(store: store)
        openSettings(in: relaunched)
        XCTAssertEqual(pickerValue(languageRow(in: relaunched)), "简体中文")
    }

    func testAppearanceSelectionUpdatesMapTraitWithoutReplacingMapOrCamera() {
        let store = UUID().uuidString
        let app = launch(
            appearanceSeed: "system",
            store: store,
            extraArguments: ["-gofly-ui-map-metrics"]
        )

        let mapInstance = metric("map.instanceID", in: app)
        let cameraState = metric("map.camera.state", in: app)
        XCTAssertFalse(mapInstance.isEmpty)
        XCTAssertFalse(cameraState.isEmpty)

        openSettings(in: app)
        let appearance = appearanceRow(in: app)
        scrollIntoView(appearance, in: app)
        XCTAssertTrue(appearance.isHittable)
        appearance.tap()
        tapMenuOption("Dark", in: app)
        XCTAssertEqual(pickerValue(appearanceRow(in: app)), "Dark")
        attachSettingsScreenshot(app, name: "settings-c01-dark")

        tapSettingsBack(in: app)
        XCTAssertEqual(metric("map.instanceID", in: app), mapInstance)
        XCTAssertEqual(metric("map.camera.state", in: app), cameraState)
        XCTAssertEqual(metric("map.trait.userInterfaceStyle", in: app), "2")

        app.buttons["map.settings"].tap()
        let lightAppearance = appearanceRow(in: app)
        scrollIntoView(lightAppearance, in: app)
        lightAppearance.tap()
        tapMenuOption("Light", in: app)
        XCTAssertEqual(pickerValue(appearanceRow(in: app)), "Light")
        tapSettingsBack(in: app)

        XCTAssertEqual(metric("map.instanceID", in: app), mapInstance)
        XCTAssertEqual(metric("map.camera.state", in: app), cameraState)
        XCTAssertEqual(metric("map.trait.userInterfaceStyle", in: app), "1")
    }

    func testSettingsPagesExposeFrozenRootsAndActualStatusFields() {
        let app = launch()
        openSettings(in: app)

        assertPage(
            linkIdentifier: "settings.location",
            rootIdentifier: "settings.location.page",
            fieldIdentifiers: ["settings.location.status"],
            in: app
        )
        assertPage(
            linkIdentifier: "settings.background",
            rootIdentifier: "settings.background.page",
            fieldIdentifiers: ["settings.background.status", "background.card"],
            in: app
        )
        assertPage(
            linkIdentifier: "settings.vpn",
            rootIdentifier: "settings.vpn.page",
            fieldIdentifiers: ["settings.vpn.status"],
            in: app
        )
        assertPage(
            linkIdentifier: "settings.device",
            rootIdentifier: "settings.device.page",
            fieldIdentifiers: ["settings.device.pairing", "settings.device.service"],
            in: app
        )
        assertPage(
            linkIdentifier: "settings.help",
            rootIdentifier: "settings.help.page",
            fieldIdentifiers: [],
            in: app
        )
        tapSettingsBack(in: app)
    }

    func testThreeLanguagesLargeTextKeepAllSettingsPagesAccessible() {
        let languages = [("en", "en_US"), ("zh-Hant", "zh_TW"), ("zh-Hans", "zh_CN")]
        for (language, locale) in languages {
            let app = launch(
                languageSeed: language,
                appleLanguage: language,
                appleLocale: locale,
                extraArguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            )
            openSettings(in: app)
            attachSettingsScreenshot(app, name: "settings-c01-xxxl-\(language)")
            for (link, root, fields) in [
                ("settings.location", "settings.location.page", ["settings.location.status"]),
                ("settings.background", "settings.background.page", ["settings.background.status", "background.card"]),
                ("settings.vpn", "settings.vpn.page", ["settings.vpn.status"]),
                ("settings.device", "settings.device.page", ["settings.device.pairing", "settings.device.service"]),
                ("settings.help", "settings.help.page", [] as [String])
            ] {
                assertPage(
                    linkIdentifier: link,
                    rootIdentifier: root,
                    fieldIdentifiers: fields,
                    screenshotName: language == "en" ? "settings-\(language)-xxxl-\(root)" : nil,
                    in: app
                )
            }
            tapSettingsBack(in: app)
            app.terminate()
        }
    }

    private func launch(
        languageSeed: String? = nil,
        appearanceSeed: String? = nil,
        store: String? = nil,
        appleLanguage: String = "en",
        appleLocale: String = "en_US",
        extraArguments: [String] = []
    ) -> XCUIApplication {
        var arguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-AppleLanguages", "(\(appleLanguage))",
            "-AppleLocale", appleLocale,
            "-gofly-ui-preferences-store", store ?? UUID().uuidString
        ]
        if let languageSeed {
            arguments += ["-gofly-ui-preferences-language", languageSeed]
        }
        if let appearanceSeed {
            arguments += ["-gofly-ui-preferences-appearance", appearanceSeed]
        }
        arguments += extraArguments
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 10))
        app.buttons["map.settings"].tap()
        let language = languageRow(in: app)
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        for _ in 0..<8 where !language.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(language.isHittable)
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !element.isHittable {
            if element.frame.minY < 100 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
    }

    private func tapSettingsBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 5))
    }

    private func attachSettingsScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func settleForScreenshot() {
        let expectation = expectation(description: "menu settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.5)
    }

    private func assertPage(
        linkIdentifier: String,
        rootIdentifier: String,
        fieldIdentifiers: [String],
        screenshotName: String? = nil,
        in app: XCUIApplication
    ) {
        let link = app.descendants(matching: .any)[linkIdentifier]
        scrollIntoView(link, in: app)
        XCTAssertTrue(link.isHittable, linkIdentifier)
        link.tap()

        let page = app.descendants(matching: .any)[rootIdentifier]
        XCTAssertTrue(page.waitForExistence(timeout: 5), rootIdentifier)
        for identifier in fieldIdentifiers {
            let field = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5), identifier)
            scrollIntoView(field, in: app)
            XCTAssertTrue(field.isHittable, identifier)
            XCTAssertGreaterThan(field.frame.width, 0, identifier)
            XCTAssertGreaterThan(field.frame.height, 0, identifier)
        }
        if let screenshotName {
            attachSettingsScreenshot(app, name: screenshotName)
        }
        tapNestedSettingsBack(in: app)
    }

    private func tapNestedSettingsBack(in app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.location"].waitForExistence(timeout: 5))
    }

    private func languageRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.language"]
    }

    private func appearanceRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.appearance"]
    }

    private func metric(_ identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10), identifier)
        return (element.value as? String) ?? element.label
    }

    private func pickerValue(_ element: XCUIElement) -> String? {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label.isEmpty ? nil : element.label
    }

    private func menuOption(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func tapMenuOption(_ title: String, in app: XCUIApplication) {
        let option = menuOption(title, in: app)
        XCTAssertTrue(option.waitForExistence(timeout: 5), title)
        option.tap()
    }
}
