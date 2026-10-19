import XCTest

@MainActor
extension XCUIApplication {
    /// Use the same visible native choices as a person, including the large-text menu fallback.
    func selectGoFlyMode(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let container = descendants(matching: .any)["map.mode"]
        XCTAssertTrue(container.waitForExistence(timeout: 10), file: file, line: line)
        let menu = buttons["map.mode.menu"]
        if menu.exists {
            menu.tap()
        }
        let option = buttons["mode." + name]
        XCTAssertTrue(option.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(option.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(option.frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(option.frame.height, 44, file: file, line: line)
        option.tap()
    }
}
