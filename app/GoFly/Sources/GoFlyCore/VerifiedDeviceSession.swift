import Foundation

/// All methods must use the same owned RSD adapter/handshake. The owner calls
/// this boundary only on its serial native queue; no handles escape it.
public protocol DeviceSession: AnyObject {
    func deviceIdentifier() throws -> String
    func isSupportPrepared() throws -> Bool
    func mountProvisionedSupport() throws
    func validateLocationService() throws
    func clearLocation() throws
}

public struct VerifiedDeviceSession {
    private let session: any DeviceSession
    private let expectedIdentifier: String

    public init(session: any DeviceSession, expectedIdentifier: String) {
        self.session = session
        self.expectedIdentifier = expectedIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public func prepare() throws {
        try verifyIdentity()
        if try !session.isSupportPrepared() {
            try verifyIdentity()
            try session.mountProvisionedSupport()
            try verifyIdentity()
            guard try session.isSupportPrepared() else {
                throw DeviceServiceFailure.devicePreparationRequired
            }
        }
        try verifyIdentity()
        try session.validateLocationService()
    }

    public func clearLocation() throws {
        try verifyIdentity()
        try session.clearLocation()
    }

    private func verifyIdentity() throws {
        let actual = try session.deviceIdentifier().trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !expectedIdentifier.isEmpty, actual == expectedIdentifier else {
            throw DeviceServiceFailure.identityMismatch
        }
    }
}
