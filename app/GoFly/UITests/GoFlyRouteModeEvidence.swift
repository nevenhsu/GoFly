import XCTest

/// Route Mode redesign evidence: screenshots land in
/// `work/gofly-ios/route-mode/<task>/` (and as xcresult attachments) so they can
/// be compared with the Figma frames side by side.
@MainActor
class GoFlyRouteModeTestCase: XCTestCase {
    func launch(_ extra: [String] = [], appearance: String = "light", largeText: Bool = false,
                preferencesStore: String = UUID().uuidString) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-gofly-ui-session-store", UUID().uuidString,
            "-gofly.onboarding.complete", "YES",
            "-gofly-ui-favorites-store", UUID().uuidString,
            "-gofly-ui-imports-store", UUID().uuidString,
            "-gofly-ui-favorite-routes-store", UUID().uuidString,
            "-gofly-ui-preferences-store", preferencesStore,
            "-gofly-ui-preferences-language", "zh-Hant",
            "-gofly-ui-preferences-appearance", appearance,
            "-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW"
        ] + extra
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    func launchGallery(appearance: String = "light", largeText: Bool = false) -> XCUIApplication {
        launch(["-gofly-ui-gallery"], appearance: appearance, largeText: largeText)
    }

    func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let match = app.descendants(matching: .any)[id]
        XCTAssertTrue(match.waitForExistence(timeout: 10), "missing \(id)")
        return match
    }

    func evidence(_ app: XCUIApplication, task: String, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(task)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        // #filePath = <repo>/app/GoFly/UITests/<file>; the simulator shares the host file system.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let dir = root.appendingPathComponent("work/gofly-ios/route-mode/\(task)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent("\(name).png"))
    }

    func figmaEvidence(_ app: XCUIApplication, ticket: String, name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "ticket-\(ticket)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent(
            "work/gofly-ios-figma04/screenshots/ticket\(ticket)-feedback",
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
