import XCTest

/// R1 shared speed preference, driven through the joystick chip and D7 sheet.
final class GoFlySpeedUITests: GoFlyRouteModeTestCase {
    func testSpeedDefaultsToTwentyFiveAndPersistsAcrossRelaunch() throws {
        let store = UUID().uuidString
        var app = launch(preferencesStore: store)
        app.selectGoFlyMode("joystick")
        var chip = element(app, "joystick.speed")
        XCTAssertTrue(chip.label.contains("25"), "first install shows 25, got \(chip.label)")
        chip.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "route.speed.value").firstMatch.label, "25")
        for preset in [5, 25, 50, 100] { XCTAssertTrue(app.buttons["route.speed.preset.\(preset)"].exists) }
        XCTAssertFalse(app.buttons["route.speed.preset.20"].exists)
        evidence(app, task: "R1", name: "speed-sheet-light")
        app.buttons["route.speed.preset.50"].tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "route.speed.value").firstMatch.label, "50")
        app.buttons["route.speed.done"].tap()
        app.terminate()

        app = launch(preferencesStore: store)
        app.selectGoFlyMode("joystick")
        chip = element(app, "joystick.speed")
        XCTAssertTrue(chip.label.contains("50"), "preference survives relaunch, got \(chip.label)")
        chip.tap()
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "route.speed.value").firstMatch.label, "50")
    }

    func testSpeedSheetInDarkAppearance() throws {
        let app = launch(appearance: "dark")
        app.selectGoFlyMode("joystick")
        let chip = element(app, "joystick.speed")
        XCTAssertTrue(chip.label.contains("25"), "fresh store must show 25, got \(chip.label)")
        chip.tap()
        _ = element(app, "route.speed.confirm")
        Thread.sleep(forTimeInterval: 0.8)
        evidence(app, task: "R1", name: "speed-sheet-dark")
    }
}
