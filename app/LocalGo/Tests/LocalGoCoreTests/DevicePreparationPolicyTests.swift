import XCTest
@testable import LocalGoCore

final class DevicePreparationPolicyTests: XCTestCase {
    func testExistingMountDoesNotRequireFilesOrRemount() throws {
        try DevicePreparationPolicy.ensureMounted(
            isMounted: { true },
            filesReady: { XCTFail("Already-mounted devices need no files"); return false },
            attemptMount: { XCTFail("Must not remount") }
        )
    }

    func testDeviceStatusWinsAfterAnAttemptThatReportsAnError() throws {
        var mounted = false
        var attempts = 0
        try DevicePreparationPolicy.ensureMounted(
            isMounted: { mounted },
            filesReady: { true },
            attemptMount: {
                attempts += 1
                // The live mount wrapper can report an error while the remote
                // device completes the installation. Only status decides.
                mounted = true
            }
        )
        XCTAssertEqual(attempts, 1)
    }

    func testMissingFilesDoNotAttemptAMount() {
        XCTAssertThrowsError(try DevicePreparationPolicy.ensureMounted(
            isMounted: { false },
            filesReady: { false },
            attemptMount: { XCTFail("Missing files must block mount") }
        ))
    }

    func testSuccessfulCallWithoutMountedDeviceIsFailure() {
        var attempts = 0
        XCTAssertThrowsError(try DevicePreparationPolicy.ensureMounted(
            isMounted: { false },
            filesReady: { true },
            attemptMount: { attempts += 1 }
        ))
        XCTAssertEqual(attempts, 1)
    }
}
