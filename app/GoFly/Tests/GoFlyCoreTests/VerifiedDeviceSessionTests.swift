import Testing
@testable import GoFlyCore

struct VerifiedDeviceSessionTests {
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
    init(identifier: String, prepared: Bool) { self.identifier = identifier; self.prepared = prepared }
    func deviceIdentifier() throws -> String { identifier }
    func isSupportPrepared() throws -> Bool {
        if changeIdentityAfterSupportCheck { identifier = "other-device" }
        return prepared
    }
    func mountProvisionedSupport() throws { throw DeviceServiceFailure.devicePreparationRequired }
    func validateLocationService() throws { effects.append("validate") }
    func clearLocation() throws { effects.append("clear") }
}
