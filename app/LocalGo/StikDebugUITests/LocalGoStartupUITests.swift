import XCTest

final class LocalGoStartupUITests: XCTestCase {
    @MainActor
    func testRestoreWithoutStartupCanRetryAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let restore = app.buttons["localgo.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 10),
                      "Restore must be available before startup after an app update or relaunch")
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        let cleared = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "狀態：已送出清除；請確認真實定位，未恢復可再次清除")
        ).firstMatch
        XCTAssertTrue(cleared.waitForExistence(timeout: 30), "Explicit restore was not acknowledged")
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 30))
        let deadline = Date().addingTimeInterval(30)
        while !restore.isEnabled && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertTrue(restore.isEnabled, "Repeated restore did not finish")
        app.terminate()
        app.launch()
        XCTAssertTrue(restore.waitForExistence(timeout: 10), "Restore disappeared after relaunch")
    }

    @MainActor
    func testStartupReachesControls() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let identified = app.buttons["localgo.start"]
        let start = identified.exists ? identified : app.buttons["啟動"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "LocalGo did not show its start action")
        start.tap()
        let controls = app.otherElements["localgo.controls"]
        let failed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "啟動失敗")).firstMatch
        let deadline = Date().addingTimeInterval(60)
        while !controls.exists && !failed.exists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "LocalGo startup state"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(failed.exists, "LocalGo displayed startup failure")
        XCTAssertTrue(controls.exists, "LocalGo did not reach its active controls")
    }

    @MainActor
    func testStopAfterStartupReturnsToStart() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let start = app.buttons["localgo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.otherElements["localgo.controls"].waitForExistence(timeout: 60))
        let stop = app.buttons["停止並自動清除模擬位置"]
        XCTAssertTrue(stop.exists)
        stop.tap()
        XCTAssertTrue(start.waitForExistence(timeout: 30), "LocalGo could not confirm clear and return to Start")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "尚未清除")).firstMatch.exists)
    }


    @MainActor
    func testStopAfterTeleportReturnsToStart() throws { try runTeleportAndStop(relaunch: false) }

    @MainActor
    func testStopAfterRelaunchReturnsToStart() throws { try runTeleportAndStop(relaunch: true) }

    @MainActor
    private func runTeleportAndStop(relaunch: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        startService(app)
        let search = app.textFields["搜尋地址或地點"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("25.0330, 121.5654\n")
        let teleport = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "瞬移到這裡")).firstMatch
        XCTAssertTrue(teleport.waitForExistence(timeout: 10))
        if !teleport.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(teleport.isEnabled)
        teleport.tap()
        let accepted = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "狀態：位置已送出；可在其他 App 查看目前位置")
        ).firstMatch
        XCTAssertTrue(accepted.waitForExistence(timeout: 60), "Teleport was not acknowledged")
        if relaunch {
            app.terminate()
            app.launch()
            startService(app)
        }
        app.buttons["停止並自動清除模擬位置"].tap()
        XCTAssertTrue(app.buttons["localgo.start"].waitForExistence(timeout: 30),
                      "LocalGo could not confirm clear and return to Start")
    }

    @MainActor
    private func startService(_ app: XCUIApplication) {
        let start = app.buttons["localgo.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.otherElements["localgo.controls"].waitForExistence(timeout: 60))
    }

}
