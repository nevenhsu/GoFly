import Foundation
import Testing
@testable import GoFlyCore

@Suite
struct SessionRecoveryGateTests {
    @Test
    func initialUnknownGateAllowsOneSamePointRecoveryAndKeepsDispatchTruth() throws {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease,
                                     replacing: authority.snapshot)

        #expect(gate.claim())
        #expect(gate.hasDispatched)
        #expect(authority.permitsRecovery(for: lease))
        #expect(gate.claimRecovery())
        #expect(gate.hasDispatched)
        #expect(!gate.claimRecovery())
    }

    @Test
    func invalidationRevokesRecoveryAfterDispatchWithoutRewritingOriginalState() throws {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease,
                                     replacing: authority.snapshot)

        #expect(gate.claim())
        gate.invalidate()
        #expect(gate.state == .dispatched)
        #expect(gate.hasDispatched)
        #expect(!gate.recoveryAvailable)
        #expect(!gate.claimRecovery())
    }

    @Test
    func recoveryRequiresCurrentRunningHealthAndAdmission() throws {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease,
                                     replacing: authority.snapshot)
        #expect(gate.claim())
        #expect(authority.updateHealth(.confirmedHealthy, for: lease))

        #expect(authority.updateRunState(.paused, for: lease))
        #expect(!gate.claimRecovery())
        #expect(authority.updateRunState(.running, for: lease))
        #expect(authority.updateHealth(.unknown, for: lease))
        #expect(!gate.claimRecovery())
        #expect(authority.updateHealth(.confirmedHealthy, for: lease))

        authority.setAdmissionFence(connectionBlocked: true, coldRecoveryHeld: false)
        #expect(!gate.claimRecovery())
        authority.setAdmissionFence(connectionBlocked: false, coldRecoveryHeld: true)
        #expect(!gate.claimRecovery())
    }

    @Test
    func backgroundRecoveryNeedsExactLiveGrantAndClosedGrantIsDenied() throws {
        let authority = MovementTaskAuthority()
        let lease = MovementTaskLease()
        let gate = PointDispatchGate(authority: authority, lease: lease,
                                     replacing: authority.snapshot)
        #expect(gate.claim())
        #expect(authority.updateHealth(.confirmedHealthy, for: lease))
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: lease)
        #expect(authority.bind(grant))
        authority.setSceneActive(false)
        #expect(gate.claimRecovery())

        let secondAuthority = MovementTaskAuthority()
        let secondLease = MovementTaskLease()
        let secondGate = PointDispatchGate(authority: secondAuthority, lease: secondLease,
                                           replacing: secondAuthority.snapshot)
        #expect(secondGate.claim())
        #expect(secondAuthority.updateHealth(.confirmedHealthy, for: secondLease))
        let closedGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: secondLease)
        #expect(secondAuthority.bind(closedGrant))
        closedGrant.revoke()
        #expect(!secondGate.claimRecovery())
    }

    @Test
    func leaseHandoffAndIdentityMismatchPreventReplay() throws {
        let authority = MovementTaskAuthority()
        let oldLease = MovementTaskLease()
        let oldGate = PointDispatchGate(authority: authority, lease: oldLease,
                                        replacing: authority.snapshot)
        #expect(oldGate.claim())
        #expect(authority.updateHealth(.confirmedHealthy, for: oldLease))
        let captured = authority.snapshot
        let newLease = MovementTaskLease()
        let newGate = PointDispatchGate(authority: authority, lease: newLease,
                                        replacing: captured)
        #expect(newGate.claim())
        #expect(!oldGate.claimRecovery())

        let session = RecoverySession(identifier: "other-device")
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        #expect(verified.movePoint(to: try #require(GeoCoordinate(latitude: 25, longitude: 121)),
                                  dispatch: newGate, recovering: true) == .notSent(.identityMismatch))
        #expect(session.coordinates.isEmpty)
    }
}

private final class RecoverySession: DeviceSession {
    let identifier: String
    var coordinates: [GeoCoordinate] = []

    init(identifier: String) { self.identifier = identifier }
    func deviceIdentifier() throws -> String { identifier }
    func isSupportPrepared() throws -> Bool { true }
    func mountProvisionedSupport() throws {}
    func validateLocationService() throws {}
    func clearLocation() throws {}
    func setLocation(_ coordinate: GeoCoordinate) throws { coordinates.append(coordinate) }
}
