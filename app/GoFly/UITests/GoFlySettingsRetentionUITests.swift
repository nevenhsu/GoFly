import XCTest
import UIKit

@MainActor
final class GoFlySettingsRetentionUITests: XCTestCase {
    func testAddressLanguageTracksPreferenceWithoutReplacingMapOrCamera() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-map-metrics"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        let mapID = element("map.instanceID", in: app).label
        let camera = element("map.camera.state", in: app).label
        XCTAssertFalse(mapID.isEmpty)
        for (choice, expected) in [("繁體中文", "zh-Hant"), ("简体中文", "zh-Hans"),
                                   ("English", "en"), ("System", "system")] {
            openSettings(app)
            choose(choice, row: "settings.language", in: app)
            goBack(app)
            XCTAssertEqual(element("map.address.requestLocale", in: app).label, expected)
            XCTAssertEqual(element("map.instanceID", in: app).label, mapID)
            XCTAssertEqual(element("map.camera.state", in: app).label, camera)
        }
    }

    func testAppearanceChoicePersistsAcrossRelaunchWithActualMapTrait() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-map-metrics"]
        app.launch()
        openSettings(app)
        choose("Dark", row: "settings.appearance", in: app)
        XCTAssertEqual(element("settings.appearance", in: app).value as? String, "Dark")
        app.terminate()
        app.launch()
        assertMapStyle("2", in: app)
        openSettings(app)
        XCTAssertEqual(element("settings.appearance", in: app).value as? String, "Dark")
    }

    /// The same test is run with the actual simulator OS set to light and dark.
    /// The UI runner is a different app and has no GoFly appearance override.
    func testSystemAppearanceResolvesActualOperatingSystemAppearance() throws {
        try simulatorOnly()
        let systemStyle = UIScreen.main.traitCollection.userInterfaceStyle
        XCTAssertTrue(systemStyle == .light || systemStyle == .dark,
                      "The actual OS trait must be known; an unspecified value cannot prove system following.")
        let app = makeApp(appearance: "system")
        app.launchArguments += ["-gofly-ui-map-metrics"]
        app.launch()
        assertMapStyle(String(systemStyle.rawValue), in: app)
        openSettings(app)
        choose("Dark", row: "settings.appearance", in: app)
        choose("System", row: "settings.appearance", in: app)
        XCTAssertEqual(element("settings.appearance", in: app).value as? String, "System")
        attachScreenshot(app, name: "settings-system-style-\(systemStyle.rawValue)")
        let language = element("settings.language", in: app)
        reveal(language, in: app)
        language.tap()
        XCTAssertTrue(app.buttons["English"].waitForExistence(timeout: 5))
        let settled = expectation(description: "Native appearance menu transition settles for capture")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        attachScreenshot(app, name: "settings-native-menu-system-style-\(systemStyle.rawValue)")
        app.navigationBars.firstMatch.tap()
        goBack(app)
        assertMapStyle(String(systemStyle.rawValue), in: app)
    }

    func testPreferenceChangesPreserveFavoriteLabelAndCurrentRouteDraft() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launchArguments += ["-gofly-ui-route-draft-count", "3", "-gofly-ui-map-metrics"]
        app.launch()

        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        let coordinate = "25.047800, 121.517000"
        let star = app.buttons["search.favorite.\(coordinate)"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        app.buttons["favorites.open"].tap()
        let favorite = app.buttons["favorites.place.\(coordinate)"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.press(forDuration: 0.8)
        let label = app.textFields["favorites.editor.label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.typeText("Home original")
        app.buttons["favorites.editor.save"].tap()
        XCTAssertEqual(favorite.label, "Home original")
        app.buttons["favorites.dismiss"].tap()

        app.selectGoFlyMode("route")
        let order = app.staticTexts["route.nodes.order"]
        XCTAssertTrue(order.waitForExistence(timeout: 5))
        let savedOrder = order.label
        XCTAssertEqual(savedOrder.split(separator: ",").count, 3)
        let start = app.buttons["route.node.start"].value as? String
        let waypoint = app.buttons["route.node.waypoint.1"].value as? String
        let destination = app.buttons["route.node.destination"].value as? String
        XCTAssertNotNil(start)
        XCTAssertNotNil(waypoint)
        XCTAssertNotNil(destination)

        openSettings(app)
        choose("繁體中文", row: "settings.language", in: app)
        XCTAssertEqual(element("settings.language", in: app).value as? String, "繁體中文")
        choose("深色", row: "settings.appearance", in: app)
        XCTAssertEqual(element("settings.appearance", in: app).value as? String, "深色")
        goBack(app)
        XCTAssertTrue(app.buttons["map.settings"].waitForExistence(timeout: 5))
        XCTAssertEqual(order.label, savedOrder)
        // User-entered coordinates and labels keep their original data values.
        XCTAssertEqual(app.buttons["route.node.waypoint.1"].value as? String, waypoint)
        XCTAssertEqual(app.buttons["route.node.destination"].value as? String, destination)
        if start != "Current location" {
            XCTAssertEqual(app.buttons["route.node.start"].value as? String, start)
        }
        app.selectGoFlyMode("teleport")
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "Home original")
        app.buttons["favorites.dismiss"].tap()

        app.terminate()
        app.launch()
        app.selectGoFlyMode("teleport")
        app.buttons["favorites.open"].tap()
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "Home original")
    }

    func testDevicePageKeepsUnknownExpiryAndMacGuideWithoutVPNAction() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openSettings(app)
        openPage("settings.device", root: "settings.device.page", in: app)
        let expiry = element("settings.device.signingExpiry", in: app)
        XCTAssertTrue(expiry.waitForExistence(timeout: 5))
        XCTAssertTrue(expiry.label.contains("Not obtained"))
        let version = element("settings.device.version", in: app)
        XCTAssertNotNil(version.label.range(of: "\\([0-9]+\\)", options: .regularExpression))
        let guide = element("settings.device.signingGuide", in: app)
        reveal(guide, in: app)
        XCTAssertTrue(guide.exists)
        XCTAssertTrue(app.staticTexts["Update signing"].exists)
        XCTAssertFalse(app.buttons["settings.vpn.open"].exists)
        XCTAssertFalse(app.buttons["settings.vpn.check"].exists)
        XCTAssertFalse(app.buttons["settings.vpn.reset"].exists)
    }

    func testMissingLocalDevVPNShowsActualOpenFailureWithoutClaimingConnection() throws {
        try simulatorOnly()
        let app = makeApp()
        app.launch()
        openSettings(app)
        openPage("settings.vpn", root: "settings.vpn.page", in: app)
        let open = app.buttons["settings.vpn.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
        open.tap()
        let failure = app.staticTexts[
            "LocalDevVPN could not be opened. Open it manually, connect the tunnel, then return to GoFly."
        ]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(element("settings.vpn.page", in: app).exists)
        XCTAssertFalse(element("settings.vpn.status", in: app).label.contains(", Available"))
        XCTAssertTrue(app.buttons["settings.vpn.check"].exists)
        XCTAssertTrue(app.buttons["settings.vpn.reset"].exists)
        attachScreenshot(app, name: "settings-localdevvpn-actual-open-failure")
    }

    private func simulatorOnly() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Settings storage and missing-app checks use isolated simulator data; phone acceptance is deferred.")
        #endif
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeApp(appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly-ui-preferences-store", UUID().uuidString,
            "-gofly-ui-preferences-language", "en",
            "-gofly-ui-preferences-appearance", appearance,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        return app
    }

    private func openSettings(_ app: XCUIApplication) {
        let settings = app.buttons["map.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(element("settings.language", in: app).waitForExistence(timeout: 5))
    }

    private func assertMapStyle(_ expected: String, in app: XCUIApplication) {
        let metric = element("map.trait.userInterfaceStyle", in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 10))
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (metric.value as? String ?? metric.label) == expected
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [matches], timeout: 5), .completed)
        XCTAssertEqual(metric.value as? String ?? metric.label, expected)
    }

    private func openPage(_ link: String, root: String, in app: XCUIApplication) {
        let row = element(link, in: app)
        reveal(row, in: app)
        row.tap()
        XCTAssertTrue(element(root, in: app).waitForExistence(timeout: 5))
    }

    private func choose(_ option: String, row: String, in app: XCUIApplication) {
        let picker = element(row, in: app)
        reveal(picker, in: app)
        picker.tap()
        let choice = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", option)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !target.isHittable { app.swipeDown() }
        for _ in 0..<8 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable)
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
