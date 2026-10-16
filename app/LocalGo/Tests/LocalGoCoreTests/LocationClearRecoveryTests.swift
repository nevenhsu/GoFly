import XCTest
@testable import LocalGoCore

final class LocationClearRecoveryTests: XCTestCase {
    func testCachedSuccessClosesWithoutOpeningFresh() {
        check(cached: 0, open: 0, fresh: 0, expected: 0,
              events: ["cached", "cleanup"])
    }

    func testMissingCachedChannelOpensAndClearsFresh() {
        check(cached: nil, open: 0, fresh: 0, expected: 0,
              events: ["cached", "cleanup", "open", "clear", "cleanup"])
    }

    func testStaleCachedChannelRecoversOnlyAfterFreshAcknowledgement() {
        check(cached: 12, open: 0, fresh: 0, expected: 0,
              events: ["cached", "cleanup", "open", "clear", "cleanup"])
    }

    func testFailedOpenClosesPartialResourcesAndKeepsFailure() {
        check(cached: 12, open: 3, fresh: 0, expected: 3,
              events: ["cached", "cleanup", "open", "cleanup"])
    }

    func testFailedFreshClearClosesAndKeepsFailure() {
        check(cached: 12, open: 0, fresh: 12, expected: 12,
              events: ["cached", "cleanup", "open", "clear", "cleanup"])
    }

    private func check(cached: Int32?, open: Int32, fresh: Int32,
                       expected: Int32, events expectedEvents: [String],
                       file: StaticString = #filePath, line: UInt = #line) {
        var events: [String] = []
        let result = LocationClearRecovery.run(
            clearCached: { events.append("cached"); return cached },
            openFresh: { events.append("open"); return open },
            clearFresh: { events.append("clear"); return fresh },
            cleanup: { events.append("cleanup") }
        )
        XCTAssertEqual(result, expected, file: file, line: line)
        XCTAssertEqual(events, expectedEvents, file: file, line: line)
    }
}
