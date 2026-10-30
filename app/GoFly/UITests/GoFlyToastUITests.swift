import XCTest

/// C1 Toast in the simulator gallery.
final class GoFlyToastUITests: GoFlyRouteModeTestCase {
    func testToastMatchesSharedSpecInBothAppearances() throws {
        var normalHeight: CGFloat = 0
        for appearance in ["light", "dark"] {
            let app = launchGallery(appearance: appearance)
            let toast = element(app, "gallery.banner.danger")
            XCTAssertEqual(toast.frame.width, app.frame.width - 32, accuracy: 2)
            XCTAssertEqual(toast.frame.height, 85, accuracy: 2,
                           "the danger Toast uses the 361 × 85 pt Figma component geometry")
            let action = app.buttons["gallery.banner.danger.action"]
            XCTAssertTrue(action.exists)
            XCTAssertGreaterThanOrEqual(action.frame.width, 56)
            XCTAssertGreaterThanOrEqual(action.frame.height + 0.01, 44,
                                         "the Toast action needs a 44 pt hit target")
            XCTAssertTrue(app.buttons["gallery.banner.danger.dismiss"].exists)
            let dismiss = app.buttons["gallery.banner.danger.dismiss"]
            XCTAssertGreaterThanOrEqual(dismiss.frame.width + 0.01, 44)
            XCTAssertGreaterThanOrEqual(dismiss.frame.height + 0.01, 44)
            XCTAssertTrue(app.buttons["gallery.banner.warning.action"].exists)
            XCTAssertFalse(app.buttons["gallery.banner.success.action"].exists)
            normalHeight = toast.frame.height
            try figmaEvidence(app, ticket: "04", name: "toast-\(appearance)")
            app.terminate()
        }
        let large = launchGallery(largeText: true)
        let toast = element(large, "gallery.banner.danger")
        XCTAssertGreaterThan(toast.frame.height, normalHeight, "toast must grow and wrap at the largest text size")
        let action = large.buttons["gallery.banner.danger.action"]
        let message = element(large, "gallery.banner.danger.message")
        XCTAssertTrue(action.isHittable, "the action must remain available at the largest text size")
        XCTAssertGreaterThanOrEqual(action.frame.height + 0.01, 44)
        XCTAssertGreaterThanOrEqual(action.frame.minY, message.frame.maxY - 1,
                                     "the large-text action should follow the wrapped message")
        let dismiss = large.buttons["gallery.banner.danger.dismiss"]
        XCTAssertGreaterThanOrEqual(dismiss.frame.width + 0.01, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height + 0.01, 44)
        try figmaEvidence(large, ticket: "04", name: "toast-axxxl")
    }

    func testFeedbackComponentGalleryInBothAppearances() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-gallery", "-gofly-ui-feedback-components"], appearance: appearance)
            let scroll = app.scrollViews["gallery.feedbackComponents"]
            XCTAssertTrue(scroll.waitForExistence(timeout: 10))
            XCTAssertTrue(element(app, "gallery.banner.danger.action").exists)
            XCTAssertTrue(element(app, "gallery.banner.warning.action").exists)
            XCTAssertTrue(element(app, "gallery.banner.success.dismiss").exists)
            try figmaEvidence(app, ticket: "04", name: "components-\(appearance)-toast")

            scroll.swipeUp()
            let startedPill = app.buttons["gallery.pill.status.pill.started"]
            let errorPill = app.buttons["gallery.pill.status.pill.error"]
            XCTAssertTrue(startedPill.waitForExistence(timeout: 10))
            XCTAssertTrue(errorPill.exists)
            XCTAssertGreaterThanOrEqual(startedPill.frame.height + 0.01, 44,
                                        "the tappable status pill needs a 44 pt target")
            try figmaEvidence(app, ticket: "04", name: "components-\(appearance)-pill-snackbar")

            scroll.swipeUp()
            XCTAssertTrue(app.sliders["gallery.slider"].exists)
            XCTAssertEqual(element(app, "gallery.progress").frame.height, 6, accuracy: 0.5)
            try figmaEvidence(app, ticket: "04", name: "components-\(appearance)-progress-slider")
            app.terminate()
        }
    }

    func testSystemSheetDimSupplementInBothAppearances() throws {
        for appearance in ["light", "dark"] {
            let app = launch(["-gofly-ui-gallery", "-gofly-ui-feedback-components"], appearance: appearance)
            let show = app.buttons["gallery.systemDim.show"]
            XCTAssertTrue(show.waitForExistence(timeout: 10))
            show.tap()
            XCTAssertTrue(element(app, "route.speed.value").waitForExistence(timeout: 10))
            try figmaEvidence(app, ticket: "04", name: "system-sheet-dim-\(appearance)")
            app.terminate()
        }
    }

    func testFeedbackComponentsRemainUsableWithLargeTextAndReduceMotion() throws {
        let app = launch(["-gofly-ui-gallery", "-gofly-ui-feedback-components", "-gofly-ui-reduce-motion"],
                         appearance: "dark", largeText: true)
        let show = app.buttons["gallery.feedback.snackbar.show"]
        XCTAssertTrue(show.waitForExistence(timeout: 10))
        show.tap()
        let snackbarAction = app.buttons.matching(identifier: "snackbar.action").firstMatch
        XCTAssertTrue(snackbarAction.waitForExistence(timeout: 5))
        XCTAssertTrue(snackbarAction.isHittable)
        XCTAssertGreaterThanOrEqual(snackbarAction.frame.height + 0.01, 44)

        let scroll = app.scrollViews["gallery.feedbackComponents"]
        scroll.swipeUp()
        let started = app.buttons["gallery.pill.status.pill.started"]
        XCTAssertTrue(started.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(started.frame.height + 0.01, 44)
        try figmaEvidence(app, ticket: "04", name: "components-dark-axxxl-reduce-motion")
    }
}
