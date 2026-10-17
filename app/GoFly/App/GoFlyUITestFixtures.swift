#if DEBUG && targetEnvironment(simulator)
import GoFlyCore

/// UI fault injection only: it creates an uncertain command state without
/// claiming a successful device write, GPS fix, or recipient-app observation.
struct UnconfirmedPointUITestService: DeviceService {
    private let unavailableDevice = NativeDeviceService()

    func prepare() async throws { try await unavailableDevice.prepare() }
    func clearLocation() async throws { try await unavailableDevice.clearLocation() }
    func resetClientConnection() async throws { try await unavailableDevice.resetClientConnection() }
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        guard dispatch.claim() else { return .notSent(.operationCancelled) }
        return .unconfirmed(.operationTimedOut)
    }
}

/// A deterministic planning failure; it neither supplies a path nor calls native code.
struct DelayedFailureRouteUITestPlanner: RoutePlanning {
    func plan(from: GeoCoordinate, to: GeoCoordinate) async throws -> [GeoCoordinate] {
        try await Task.sleep(for: .seconds(5))
        try Task.checkCancellation()
        throw RouteExecutionFailure.planningFailed
    }
}
#endif
