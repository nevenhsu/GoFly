import XCTest

@MainActor
extension XCUIApplication {
    /// Use the same visible native choices as a person, including the large-text menu fallback.
    func selectGoFlyMode(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let container = descendants(matching: .any)["map.mode"]
        XCTAssertTrue(container.waitForExistence(timeout: 10), file: file, line: line)
        let menu = buttons["map.mode.menu"]
        let usedMenu = menu.exists
        if usedMenu {
            assertGoFlyModeTarget(menu, file: file, line: line)
            menu.tap()
        } else {
            for name in ["teleport", "route", "joystick"] {
                let option = buttons["mode." + name]
                if option.exists { assertGoFlyModeTarget(option, file: file, line: line) }
            }
        }
        let option = buttons["mode." + name]
        XCTAssertTrue(option.waitForExistence(timeout: 5), file: file, line: line)
        assertGoFlyModeTarget(option, file: file, line: line)
        option.tap()
        if !usedMenu { XCTAssertTrue(option.isSelected, file: file, line: line) }
    }

    private func assertGoFlyModeTarget(_ option: XCUIElement, file: StaticString, line: UInt) {
        let minimum: CGFloat = 44 - 0.000001
        XCTAssertGreaterThanOrEqual(option.frame.width, minimum, file: file, line: line)
        XCTAssertGreaterThanOrEqual(option.frame.height, minimum, file: file, line: line)
        XCTAssertTrue(option.isHittable, file: file, line: line)
    }
}
