import XCTest

/// R6: D6 execution controls geometry and the D6.a end-route dialog (gallery; a route cannot run in the simulator).
final class GoFlyRouteExecutionUITests: GoFlyRouteModeTestCase {
    private func scrollTo(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        let target = app.descendants(matching: .any)[id]
        for _ in 0..<12 where !target.exists || !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.waitForExistence(timeout: 5), "missing \(id)")
        return target
    }

    func testRunningControlsMatchD6Spacing() throws {
        let app = launchGallery()
        let end = scrollTo(app, "route.cancel")
        let progress = element(app, "route.progress")
        let percent = element(app, "route.position.value")
        let repeatButton = element(app, "route.control.repeat")
        let chip = element(app, "route.speedChip")
        let pause = element(app, "route.pause")

        XCTAssertEqual(progress.frame.height, 6, accuracy: 1)
        XCTAssertEqual(progress.frame.minY - percent.frame.maxY, 8, accuracy: 2, "label row to progress is 8 pt")
        XCTAssertEqual(repeatButton.frame.width, 36, accuracy: 1)
        XCTAssertEqual(repeatButton.frame.height, 36, accuracy: 1)
        XCTAssertEqual(chip.frame.width, 68, accuracy: 1)
        XCTAssertEqual(chip.frame.height, 36, accuracy: 1)
        XCTAssertEqual(repeatButton.frame.minY - progress.frame.maxY, 20, accuracy: 1.5, "progress to controls row is 20 pt")
        XCTAssertEqual(end.frame.minY - repeatButton.frame.maxY, 20, accuracy: 1.5, "controls row to buttons is 20 pt")
        XCTAssertEqual(end.frame.height, 56, accuracy: 1)
        XCTAssertEqual(pause.frame.height, 56, accuracy: 1)
        XCTAssertEqual(end.frame.width, 120, accuracy: 1)
        // The action style pads its label by 16 pt on each side outside the reported element frame.
        XCTAssertEqual(pause.frame.width + 32, app.frame.width - 40 - 120 - 12, accuracy: 1)
        evidence(app, task: "R6", name: "d6-controls-light")
    }
}
