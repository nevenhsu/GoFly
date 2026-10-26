import XCTest

/// R5: D1 / D2 / D3 panel spacing as implemented (2026-10-26; Figma 04 not yet synced): content starts
/// below the 33 pt grabber row and the Start row ends 20 pt above the tab bar (393 × 852 reference).
final class GoFlyRoutePanelLayoutUITests: GoFlyRouteModeTestCase {
    private let grabberRow: CGFloat = 33

    func testInitialPanelSpacingMatchesD1() throws {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            app.selectGoFlyMode("route")
            let sheet = element(app, "map.sheet")
            let bar = element(app, "map.bottomBar")
            let header = element(app, "route.importedRoutes")
            let card = element(app, "route.nodes.card")
            let add = element(app, "route.addNode")
            let star = element(app, "route.favorite.toggle")
            let start = element(app, "route.start")
            Thread.sleep(forTimeInterval: 0.6)

            XCTAssertEqual(header.frame.minY - sheet.frame.minY, grabberRow, accuracy: 1, "header right below the grabber row")
            XCTAssertEqual(header.frame.height, 44, accuracy: 1)
            XCTAssertEqual(card.frame.minY - header.frame.maxY, 12, accuracy: 1, "list 12 pt below the header")
            XCTAssertEqual(card.frame.height, 120, accuracy: 1, "two 60 pt rows")
            XCTAssertEqual(card.frame.width, app.frame.width - 40, accuracy: 1)
            XCTAssertEqual(add.frame.minY - card.frame.maxY, 4, accuracy: 1)
            XCTAssertEqual(star.frame.minY - add.frame.maxY, 16, accuracy: 1, "Start row 16 pt below the action row")
            XCTAssertEqual(star.frame.height, 56, accuracy: 1)
            XCTAssertEqual(start.frame.height, 56, accuracy: 1)
            XCTAssertEqual(bar.frame.minY - star.frame.maxY, 20, accuracy: 1, "20 pt between the Start row and the tab bar")
            XCTAssertEqual(bar.frame.minY - sheet.frame.maxY, 0, accuracy: 1, "the sheet ends where the tab bar begins")
            evidence(app, task: "R5", name: "d1-initial-\(appearance)")
            app.terminate()
        }
    }

    func testCollapsedPanelIsTheNarrowestHeightD3() throws {
        let app = launch()
        app.selectGoFlyMode("route")
        Thread.sleep(forTimeInterval: 0.8)
        let grabber = app.buttons["map.sheet.grabber"]
        grabber.tap()
        Thread.sleep(forTimeInterval: 0.9)
        let sheet = element(app, "map.sheet")
        let bar = element(app, "map.bottomBar")
        let header = element(app, "route.importedRoutes")
        XCTAssertEqual(bar.frame.minY - sheet.frame.minY, 96, accuracy: 1, "collapsed sheet is 96 pt")
        XCTAssertEqual(header.frame.minY - sheet.frame.minY, grabberRow, accuracy: 1)
        XCTAssertEqual(sheet.frame.maxY - header.frame.maxY, 20, accuracy: 1)
        XCTAssertFalse(app.descendants(matching: .any)["route.nodes.card"].exists, "only the title and two buttons remain")
        let recenter = element(app, "map.recenter")
        XCTAssertEqual(sheet.frame.minY - recenter.frame.maxY, 16, accuracy: 1)
        evidence(app, task: "R5", name: "d3-collapsed-light")
    }
}
