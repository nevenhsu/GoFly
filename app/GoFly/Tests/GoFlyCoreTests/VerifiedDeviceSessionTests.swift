import Testing
@testable import GoFlyCore

struct VerifiedDeviceSessionTests {
    @Test func rejectedIdentityOrInvalidatedGateNeverDispatchesAndNativeFailureIsUnconfirmed() throws {
        let coordinate = try #require(GeoCoordinate(latitude: 25, longitude: 121))
        let wrong = Session(identifier: "other-device", prepared: true)
        #expect(VerifiedDeviceSession(session: wrong, expectedIdentifier: "bound-device")
            .movePoint(to: coordinate, dispatch: PointDispatchGate()) == .notSent(.identityMismatch))
        #expect(wrong.sentCoordinates.isEmpty)
        let session = Session(identifier: "bound-device", prepared: true)
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        let invalidated = PointDispatchGate()
        invalidated.invalidate()
        #expect(verified.movePoint(to: coordinate, dispatch: invalidated) == .notSent(.operationCancelled))
        #expect(session.sentCoordinates.isEmpty)
        session.pointFailure = .operationTimedOut
        #expect(verified.movePoint(to: coordinate, dispatch: PointDispatchGate()) == .unconfirmed(.operationTimedOut))
        #expect(session.sentCoordinates == [coordinate])
    }

    @Test func oneApprovedGateSendsTheExactCoordinateOnlyOnce() throws {
        let session = Session(identifier: "bound-device", prepared: true)
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        let coordinate = try #require(GeoCoordinate(latitude: 25.033, longitude: 121.5654))
        let dispatch = PointDispatchGate()
        #expect(verified.movePoint(to: coordinate, dispatch: dispatch) == .acknowledged)
        #expect(session.sentCoordinates == [coordinate])
        #expect(verified.movePoint(to: coordinate, dispatch: dispatch) == .notSent(.operationCancelled))
        #expect(session.sentCoordinates == [coordinate])
    }

    @Test func differentDeviceCannotMountOrClear() throws {
        let session = Session(identifier: "other-device", prepared: false)
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        #expect(throws: DeviceServiceFailure.identityMismatch) { try verified.prepare() }
        #expect(throws: DeviceServiceFailure.identityMismatch) { try verified.clearLocation() }
        #expect(session.effects.isEmpty)
    }

    @Test func identityChangeBeforeMountDoesNotWrite() throws {
        let session = Session(identifier: "bound-device", prepared: false)
        session.changeIdentityAfterSupportCheck = true
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        #expect(throws: DeviceServiceFailure.identityMismatch) { try verified.prepare() }
        #expect(session.effects.isEmpty)
    }

    @Test func mountedSupportIsReusedAndPrepareNeverClears() throws {
        let session = Session(identifier: "bound-device", prepared: true)
        try VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device").prepare()
        #expect(session.effects == ["validate"])
    }

    @Test func missingProvisionedSupportCannotClaimReady() throws {
        let session = Session(identifier: "bound-device", prepared: false)
        let verified = VerifiedDeviceSession(session: session, expectedIdentifier: "bound-device")
        #expect(throws: DeviceServiceFailure.devicePreparationRequired) { try verified.prepare() }
        #expect(!session.effects.contains("validate"))
    }
}

private final class Session: DeviceSession {
    var identifier: String
    let prepared: Bool
    var changeIdentityAfterSupportCheck = false
    var effects: [String] = []
    var sentCoordinates: [GeoCoordinate] = []
    var pointFailure: DeviceServiceFailure?
    init(identifier: String, prepared: Bool) { self.identifier = identifier; self.prepared = prepared }
    func deviceIdentifier() throws -> String { identifier }
    func isSupportPrepared() throws -> Bool {
        if changeIdentityAfterSupportCheck { identifier = "other-device" }
        return prepared
    }
    func mountProvisionedSupport() throws { throw DeviceServiceFailure.devicePreparationRequired }
    func validateLocationService() throws { effects.append("validate") }
    func clearLocation() throws { effects.append("clear") }
    func setLocation(_ coordinate: GeoCoordinate) throws {
        sentCoordinates.append(coordinate)
        if let pointFailure { throw pointFailure }
    }
}
