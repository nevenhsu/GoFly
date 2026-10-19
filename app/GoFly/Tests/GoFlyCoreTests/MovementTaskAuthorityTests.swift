import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct MovementTaskAuthorityTests {
    @Test func handoffRevokesTheExactOldLeaseAndRejectsQueuedOldWrites() throws {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let captured = authority.snapshot
        let oldTick = PointDispatchGate(authority: authority, lease: old)
        #expect(oldTick.claim())
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        #expect(authority.updateRunState(.running, for: old))
        #expect(authority.snapshot == captured, "A healthy old acknowledgement is not an ownership or health transition")
        let new = MovementTaskLease()
        let handoff = PointDispatchGate(authority: authority, lease: new, replacing: captured)
        #expect(handoff.claim())
        #expect(authority.snapshot.lease == new)
        #expect(!PointDispatchGate(authority: authority, lease: old).claim())
        #expect(!authority.updateHealth(.unknown, for: old))
        #expect(authority.snapshot.health == .unknown)
        #expect(!PointDispatchGate(authority: authority, lease: new).claim())
    }
    @Test func aHealthOrRunStateChangeInvalidatesCapturedHandoffAndTheGateCannotTryAgain() {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let captured = authority.snapshot
        let gate = PointDispatchGate(authority: authority, lease: MovementTaskLease(), replacing: captured)
        #expect(authority.updateHealth(.interrupted(.tunnelUnavailable), for: old))
        #expect(!gate.claim())
        #expect(gate.state == .invalidated)
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        #expect(!gate.claim())
        #expect(authority.snapshot.lease == old)
        #expect(!PointDispatchGate(authority: authority, lease: old, replacing: captured).claim())
        #expect(authority.updateRunState(.paused, for: old))
        #expect(!PointDispatchGate(authority: authority, lease: old).claim())
    }

    @Test func cancelBeforeClaimLeavesTheExactAuthorityAndClaimBeforeCancelCannotPretendCancelled() {
        let authority = MovementTaskAuthority()
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let captured = authority.snapshot
        let cancelled = PointDispatchGate(authority: authority, lease: MovementTaskLease(), replacing: captured)
        #expect(cancelled.invalidateIfAvailable())
        #expect(!cancelled.claim())
        #expect(authority.snapshot == captured)
        let new = MovementTaskLease()
        let sending = PointDispatchGate(authority: authority, lease: new, replacing: captured)
        #expect(sending.claim())
        #expect(!sending.invalidateIfAvailable())
        #expect(sending.state == .dispatched)
        #expect(authority.snapshot.lease == new)
        authority.revokeAll()
        #expect(!PointDispatchGate(authority: authority, lease: old).claim())
        #expect(!PointDispatchGate(authority: authority, lease: new).claim())
    }

    @Test func serviceAvailabilityFenceInvalidatesOldCASWithoutChangingCleanupState() {
        let service = ServiceController(service: FenceDevice())
        let authority = service.movementAuthority
        let old = MovementTaskLease()
        #expect(authority.install(old, replacing: authority.snapshot))
        #expect(authority.updateHealth(.confirmedHealthy, for: old))
        let captured = authority.snapshot

        service.setMovementConnectionAvailable(false)

        #expect(!authority.permitsDispatch(for: old))
        #expect(!authority.install(MovementTaskLease(), replacing: captured))
        #expect(authority.snapshot.lease == old)
        #expect(authority.snapshot.health == .confirmedHealthy)

        service.setMovementConnectionAvailable(true)
        #expect(!PointDispatchGate(authority: authority, lease: MovementTaskLease(), replacing: captured).claim())
        #expect(authority.permitsDispatch(for: old))
    }

    @Test func availabilityPublicationSeesClosedFenceAndColdRestoreRejectsLateProof() {
        let service = ServiceController(service: FenceDevice())
        let authority = service.movementAuthority
        var fenceWasClosedDuringPublication = false
        let oldLease = MovementTaskLease()
        #expect(authority.install(oldLease, replacing: authority.snapshot))
        let observation = service.objectWillChange.sink { _ in
            if service.movementConnectionAvailable {
                fenceWasClosedDuringPublication = !service.canTeleport &&
                    !service.movementAuthority.permitsDispatch(for: oldLease)
            }
        }
        service.setMovementConnectionAvailable(false)
        observation.cancel()
        #expect(fenceWasClosedDuringPublication)
        authority.revokeAll()

        let position = SessionDisplayPosition(
            coordinate: GeoCoordinate(latitude: 25, longitude: 121)!, source: .gps
        )
        let restored = service.restoreColdRecovery(position: position)
        #expect(restored)
        service.markColdClearPending()
        #expect(service.coldClearPending)
        #expect(!service.restoreColdRecovery(position: nil))

        let late = ServiceController(service: FenceDevice())
        late.observeRealLocation(RealLocationObservation(
            latitude: 25, longitude: 121, horizontalAccuracy: 5, observedAt: Date()
        ))
        #expect(!late.restoreColdRecovery(position: position))
    }
}

private struct FenceDevice: DeviceService {
    func prepare() async throws {}
    func clearLocation() async throws {}
    func resetClientConnection() async throws {}
    func movePoint(to coordinate: GeoCoordinate, dispatch: PointDispatchGate) async -> PointDeliveryOutcome {
        .notSent(.operationCancelled)
    }
}
