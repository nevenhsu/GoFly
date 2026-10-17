import Testing
@testable import GoFlyCore

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
}
