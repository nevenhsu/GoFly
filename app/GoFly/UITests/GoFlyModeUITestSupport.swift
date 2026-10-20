import XCTest

@MainActor
extension XCUIApplication {
    /// The redesign keeps all three mode tabs visible and equal width, so the
    /// person (and the test) always taps the same bottom-bar button.
    func selectGoFlyMode(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let container = descendants(matching: .any)["map.bottomBar"]
        XCTAssertTrue(container.waitForExistence(timeout: 10), file: file, line: line)
        let option = buttons["mode." + name]
        XCTAssertTrue(option.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(option.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(option.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(option.frame.height, 44, file: file, line: line)
        option.tap()
    }
}
