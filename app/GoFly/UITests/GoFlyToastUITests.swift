import XCTest

/// C1 Toast in the simulator gallery.
final class GoFlyToastUITests: GoFlyRouteModeTestCase {
    func testToastMatchesSharedSpecInBothAppearances() throws {
        var normalHeight: CGFloat = 0
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let toast = element(app, "gallery.banner.danger")
            XCTAssertEqual(toast.frame.width, app.frame.width - 32, accuracy: 1)
            XCTAssertGreaterThanOrEqual(toast.frame.height, 60)
            let action = app.buttons["gallery.banner.danger.action"]
            XCTAssertTrue(action.exists)
            XCTAssertGreaterThanOrEqual(action.frame.width, 56)
            XCTAssertGreaterThanOrEqual(action.frame.height, 32)
            XCTAssertTrue(app.buttons["gallery.banner.danger.dismiss"].exists)
            XCTAssertTrue(app.buttons["gallery.banner.warning.action"].exists)
            XCTAssertFalse(app.buttons["gallery.banner.success.action"].exists)
            normalHeight = toast.frame.height
            evidence(app, task: "C1", name: "toast-\(appearance)")
            app.terminate()
        }
        let large = launchGallery(largeText: true)
        let toast = element(large, "gallery.banner.danger")
        XCTAssertGreaterThan(toast.frame.height, normalHeight, "toast must grow and wrap at the largest text size")
        evidence(large, task: "C1", name: "toast-axxxl")
    }
}
