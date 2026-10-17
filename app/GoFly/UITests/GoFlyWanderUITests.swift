import XCTest

@MainActor
final class GoFlyWanderUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testUnavailableWanderCannotStartAndSetStartPreservesCandidateAndImmediateFavorite() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This verifies the actual simulator origin-unavailable path, not successful wander movement.")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["-gofly-ui-session-store", UUID().uuidString, "-gofly.onboarding.complete", "YES", "-gofly-ui-map-metrics",
                               "-gofly-ui-favorites-store", UUID().uuidString,
                               "-gofly-ui-imports-store", UUID().uuidString,
                               "-gofly-ui-favorite-routes-store", UUID().uuidString,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        query.typeText("25.0478, 121.5170")
        if app.keyboards.buttons["Done"].exists { app.keyboards.buttons["Done"].tap() }
        let pin = app.buttons["map.candidate.pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        let selectionID = app.staticTexts["map.candidate.selectionID"].label
        let star = app.buttons["search.favorite.25.047800, 121.517000"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        star.tap()
        XCTAssertEqual(star.value as? String, "Favorite")

        app.selectGoFlyMode("joystick")
        let wander = app.switches["joystick.wander"]
        XCTAssertTrue(wander.waitForExistence(timeout: 5))
        XCTAssertEqual(wander.label, "Wander")
        XCTAssertEqual(wander.value as? String, "0")
        XCTAssertFalse(wander.isEnabled)
        XCTAssertGreaterThanOrEqual(wander.frame.height, 44 - 0.000001)
        XCTAssertGreaterThanOrEqual(wander.frame.width, 44 - 0.000001)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(wander.frame))
        // A real tap on the disabled control must not create an intent or destination.
        wander.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(wander.value as? String, "0")
        XCTAssertFalse(app.buttons["joystick.randomDestination"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["joystick.pad"].exists)
        XCTAssertFalse(app.staticTexts["operation.attempt"].exists)
        XCTAssertFalse(app.staticTexts["map.serviceError.message"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["map.positionStatus"].label.contains("Stopped"))
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, "12-unavailable-wander-disabled-before-set-start")

        app.buttons["joystick.setOrigin"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(pin.value as? String, "25.047800, 121.517000")
        XCTAssertEqual(app.staticTexts["map.candidate.selectionID"].label, selectionID)
        XCTAssertEqual(star.value as? String, "Favorite")
        XCTAssertFalse(app.buttons["map.wander.target"].exists)
        XCTAssertFalse(app.staticTexts["operation.attempt"].exists)
        pin.tap()
        XCTAssertTrue(app.buttons["placeDetails.favorite"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["placeDetails.favorite"].value as? String, "Favorite")
        app.buttons["placeDetails.favorite"].tap()
        XCTAssertEqual(app.buttons["placeDetails.favorite"].value as? String, "Not a favorite")
        app.buttons["placeDetails.dismiss"].tap()
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        XCTAssertEqual(star.value as? String, "Not a favorite")
        XCTAssertEqual(app.staticTexts["map.candidate.selectionID"].label, selectionID)
        app.selectGoFlyMode("joystick")
        XCTAssertTrue(wander.waitForExistence(timeout: 5))
        XCTAssertEqual(wander.value as? String, "0")
        XCTAssertFalse(wander.isEnabled)
        XCTAssertEqual(app.alerts.count, 0)
        attach(app, "12-set-start-keeps-candidate-and-shared-star-without-execution")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
