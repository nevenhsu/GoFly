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

    func testEndDialogCancelAndConfirm() throws {
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            scrollTo(app, "route.cancel").tap()
            XCTAssertEqual(element(app, "route.end.dialog.title").label, "結束這次路線？")
            XCTAssertTrue(element(app, "route.end.dialog.message").label.contains("停止模擬路線並保留目前位置"))
            let cancel = element(app, "route.end.dialog.cancel")
            let confirm = element(app, "route.end.dialog.confirm")
            XCTAssertEqual(cancel.label, "取消")
            XCTAssertEqual(confirm.label, "結束路線")
            // 320 pt dialog with 20 pt padding leaves a 280 pt action row.
            XCTAssertEqual(confirm.frame.maxX - cancel.frame.minX, 280, accuracy: 2)
            XCTAssertEqual(cancel.frame.midX + confirm.frame.midX, app.frame.width, accuracy: 2, "dialog is centered")
            XCTAssertEqual(cancel.frame.height, 48, accuracy: 1)
            XCTAssertEqual(confirm.frame.height, 48, accuracy: 1)
            XCTAssertEqual(cancel.frame.width, confirm.frame.width, accuracy: 1)
            // A touch on the controls underneath is swallowed by the scrim: the dialog stays and nothing runs.
            app.buttons["route.pause"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["route.end.dialog.cancel"].exists, "dialog is still open")
            XCTAssertEqual(element(app, "gallery.endResult").label, "idle", "the pause control did not fire")
            evidence(app, task: "R6", name: "d6a-dialog-\(appearance)")

            cancel.tap()
            XCTAssertFalse(app.descendants(matching: .any)["route.end.dialog"].exists)
            XCTAssertEqual(element(app, "gallery.endResult").label, "cancelled")

            scrollTo(app, "route.cancel").tap()
            element(app, "route.end.dialog.confirm").tap()
            XCTAssertEqual(element(app, "gallery.endResult").label, "ended")
            app.terminate()
        }
    }
}
