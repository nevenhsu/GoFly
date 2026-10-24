import XCTest

/// C4 SearchField / Progress / Slider in the simulator gallery.
final class GoFlyFieldUITests: GoFlyRouteModeTestCase {
    func testSearchFieldProgressAndSliderMatchSharedSpec() throws {
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let focused = element(app, "gallery.field.focused")
            let normal = element(app, "gallery.field.normal")
            XCTAssertGreaterThanOrEqual(focused.frame.height, 48)
            XCTAssertEqual(focused.frame.width, normal.frame.width, accuracy: 1)
            let progress = element(app, "gallery.progress")
            XCTAssertEqual(progress.frame.height, 6, accuracy: 0.5)
            XCTAssertTrue(app.sliders["gallery.slider"].exists)
            evidence(app, task: "C4", name: "fields-\(appearance)")
            app.terminate()
        }
    }
}
