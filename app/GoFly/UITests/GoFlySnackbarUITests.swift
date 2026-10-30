import XCTest

/// C2 Snackbar in the simulator gallery.
final class GoFlySnackbarUITests: GoFlyRouteModeTestCase {
    func testSnackbarUndoVariantHasPillActionAndMinimumHeight() throws {
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let preview = element(app, "gallery.snackbar.preview")
            XCTAssertEqual(preview.frame.height, 52, accuracy: 1)
            let action = app.buttons["snackbar.action"].firstMatch
            XCTAssertTrue(action.exists)
            XCTAssertGreaterThanOrEqual(action.frame.width, 56)
            XCTAssertGreaterThanOrEqual(action.frame.height, 32)
            try figmaEvidence(app, ticket: "04", name: "snackbar-\(appearance)")
            app.terminate()
        }
    }

    func testUndoSnackbarOutlivesTwoSecondsAndDisappearsAfterFive() throws {
        let app = launchGallery()
        let show = app.buttons["gallery.snackbar.show"]
        for _ in 0..<6 where !show.isHittable { app.swipeUp() }
        let snackbars = app.buttons.matching(identifier: "snackbar.action")
        let before = snackbars.count
        show.tap()
        let appeared = NSPredicate { _, _ in snackbars.count > before }
        expectation(for: appeared, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertGreaterThan(snackbars.count, before, "undo snackbar must stay about 5 seconds")
        let gone = NSPredicate { _, _ in snackbars.count == before }
        expectation(for: gone, evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }
}
