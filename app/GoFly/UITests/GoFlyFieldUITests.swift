import XCTest

/// C4 SearchField / Progress / Slider in the simulator gallery.
final class GoFlyFieldUITests: GoFlyRouteModeTestCase {
    func testSearchFieldProgressAndSliderMatchSharedSpec() throws {
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let focused = element(app, "gallery.field.focused")
            let normal = element(app, "gallery.field.default")
            XCTAssertGreaterThanOrEqual(focused.frame.height, 44)
            XCTAssertEqual(focused.frame.width, normal.frame.width, accuracy: 1)
            let progress = element(app, "gallery.progress")
            XCTAssertEqual(progress.frame.height, 6, accuracy: 0.5)
            let slider = app.sliders["gallery.slider"]
            XCTAssertTrue(slider.exists)
            let gallery = app.scrollViews["gallery"]
            for _ in 0..<10 where !slider.isHittable { gallery.swipeUp() }
            XCTAssertTrue(slider.isHittable)
            let initialValue = slider.value as? String
            slider.adjust(toNormalizedSliderPosition: 0.75)
            let adjustedValue = slider.value as? String
            XCTAssertNotEqual(adjustedValue, initialValue,
                              "the native Slider must remain interactive while its available width changes")
            let resize = app.buttons["gallery.slider.resize"]
            for _ in 0..<5 where !resize.isHittable { gallery.swipeUp() }
            XCTAssertTrue(resize.isHittable)
            let widthBeforeResize = slider.frame.width
            resize.tap()
            XCTAssertNotEqual(slider.frame.width, widthBeforeResize,
                              "the fixture must change the slider's available width")
            XCTAssertEqual(slider.value as? String, adjustedValue,
                           "resizing the native Slider must preserve its value proportion")
            try figmaEvidence(app, ticket: "04", name: "fields-\(appearance)")
            app.terminate()
        }
    }
}
