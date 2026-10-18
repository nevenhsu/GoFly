import Foundation

/// The data-only management operation requested for an installed app.
public enum ManagementKind: String, Equatable, Sendable {
    case renew
    case repair
}

/// The source application's acknowledgement phase.
public enum ManagementSourcePhase: String, Equatable, Sendable {
    case preparing
    case ready
    case released
}

/// Stable failures exposed by the management value and codec boundary.
public enum ManagementFailure: Error, Equatable, Sendable {
    case invalidInput
    case unsupportedVersion
    case identityMismatch
    case limitExceeded
    case unsafeFile
    case storageUnavailable
    case conflict
    case unavailable
}

/// The immutable, data-only management request exchanged with the source app.
public struct ManagementRequest: Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumBytes = 32 * 1_024

    public let version: Int
    public let managementID: UUID
    public let nonce: UUID
    public let kind: ManagementKind
    public let expectedDeviceUDID: String
    public let sourceSetupID: UUID
    public let sourceApp: SetupAppIdentity
    public let sourceActivationSHA256: String
    public let sourceRestoreRootSHA256: String?
    public let teamID: String
    public let targetSetupID: UUID
    public let targetApp: SetupAppIdentity

    public init(version: Int = Self.schemaVersion,
                managementID: UUID,
                nonce: UUID,
                kind: ManagementKind,
                expectedDeviceUDID: String,
                sourceSetupID: UUID,
                sourceApp: SetupAppIdentity,
                sourceActivationSHA256: String,
                sourceRestoreRootSHA256: String?,
                teamID: String,
                targetSetupID: UUID,
                targetApp: SetupAppIdentity) throws {
        guard version == Self.schemaVersion else { throw ManagementFailure.unsupportedVersion }
        guard sourceSetupID != targetSetupID else { throw ManagementFailure.identityMismatch }
        guard SetupValidation.validUDID(expectedDeviceUDID),
              SetupValidation.isLowerHex(sourceActivationSHA256, count: 64),
              sourceRestoreRootSHA256.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true,
              Self.validTeamID(teamID),
              SetupAppIdentity.valid(bundleID: sourceApp.bundleID, build: sourceApp.build,
                                     profileSHA256: sourceApp.profileSHA256,
                                     executableSHA256: sourceApp.executableSHA256),
              SetupAppIdentity.valid(bundleID: targetApp.bundleID, build: targetApp.build,
                                     profileSHA256: targetApp.profileSHA256,
                                     executableSHA256: targetApp.executableSHA256) else {
            throw ManagementFailure.invalidInput
        }
        if kind == .repair, targetApp != sourceApp {
            throw ManagementFailure.identityMismatch
        }
        self.version = version
        self.managementID = managementID
        self.nonce = nonce
        self.kind = kind
        self.expectedDeviceUDID = expectedDeviceUDID
        self.sourceSetupID = sourceSetupID
        self.sourceApp = sourceApp
        self.sourceActivationSHA256 = sourceActivationSHA256
        self.sourceRestoreRootSHA256 = sourceRestoreRootSHA256
        self.teamID = teamID
        self.targetSetupID = targetSetupID
        self.targetApp = targetApp
    }

    static func validTeamID(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90)
        }
    }
}

/// A request together with the exact bytes and digest that were received.
public struct ManagementInput: Equatable, Sendable {
    public let request: ManagementRequest
    public let rawRequest: Data
    public let rawRequestSHA256: String

    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= ManagementRequest.maximumBytes else {
            throw ManagementFailure.limitExceeded
        }
        self.request = try ManagementCodec.decodeRequest(data)
        self.rawRequest = data
        self.rawRequestSHA256 = SetupValidation.sha256(data)
    }

}

/// A data-only acknowledgement from the source application.
public struct ManagementSourceReceipt: Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumBytes = 64 * 1_024

    public let version: Int
    public let managementID: UUID
    public let nonce: UUID
    public let requestSHA256: String
    public let phase: ManagementSourcePhase
    public let pid: Int32
    public let app: SetupAppIdentity
    public let sourceSetupID: UUID
    public let activationSHA256: String
    public let restoreRootSHA256: String?

    public init(version: Int = Self.schemaVersion,
                managementID: UUID,
                nonce: UUID,
                requestSHA256: String,
                phase: ManagementSourcePhase,
                pid: Int32,
                app: SetupAppIdentity,
                sourceSetupID: UUID,
                activationSHA256: String,
                restoreRootSHA256: String?) throws {
        guard version == Self.schemaVersion else { throw ManagementFailure.unsupportedVersion }
        guard SetupValidation.isLowerHex(requestSHA256, count: 64),
              pid > 0,
              SetupValidation.isLowerHex(activationSHA256, count: 64),
              restoreRootSHA256.map({ SetupValidation.isLowerHex($0, count: 64) }) ?? true,
              SetupAppIdentity.valid(bundleID: app.bundleID, build: app.build,
                                     profileSHA256: app.profileSHA256,
                                     executableSHA256: app.executableSHA256) else {
            throw ManagementFailure.invalidInput
        }
        self.version = version
        self.managementID = managementID
        self.nonce = nonce
        self.requestSHA256 = requestSHA256
        self.phase = phase
        self.pid = pid
        self.app = app
        self.sourceSetupID = sourceSetupID
        self.activationSHA256 = activationSHA256
        self.restoreRootSHA256 = restoreRootSHA256
    }

    /// Checks that this acknowledgement is bound to the exact received request.
    public func bound(to input: ManagementInput) throws {
        let request = input.request
        guard managementID == request.managementID,
              nonce == request.nonce,
              requestSHA256 == input.rawRequestSHA256,
              app == request.sourceApp,
              sourceSetupID == request.sourceSetupID,
              activationSHA256 == request.sourceActivationSHA256,
              restoreRootSHA256 == request.sourceRestoreRootSHA256 else {
            throw ManagementFailure.identityMismatch
        }
    }
}
