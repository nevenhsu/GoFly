import Foundation
import Testing
@testable import GoFlyCore
@Suite @MainActor struct CoreRetryTests {
    @Test func preparationAutomaticallyRetriesUntilItSucceeds() async {
        let device = RetryDevice()
        let service = ServiceController(service: device)
        service.observeRealLocation(RealLocationObservation(latitude: 25, longitude: 121,
            horizontalAccuracy: 5, observedAt: Date()))
        #expect(service.start())
        for _ in 0..<500 where service.phase != .ready || service.nativeBusy {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
        #expect(await device.prepares == 3)
        #expect(service.phase == .ready)
    }
}
private actor RetryDevice: DeviceService {
    private(set) var prepares = 0
    func prepare() async throws {
        prepares += 1
        if prepares < 3 { throw DeviceServiceFailure.serviceUnavailable }
    }
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        .notSent(.operationCancelled)
    }
}
