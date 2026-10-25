import Foundation

/// Shared by all movement modes and both session pills. Probe progress is
/// deliberately independent of the last completed connectivity result.
public enum SessionDisplayStatus: Equatable, Sendable {
    case started, simulating, paused, stopped, error

    public init(hasError: Bool, running: Bool, paused: Bool, hasSimulated: Bool) {
        if hasError { self = .error }
        else if running { self = .simulating }
        else if paused { self = .paused }
        else { self = hasSimulated ? .stopped : .started }
    }

    public var textKey: String {
        switch self {
        case .started: "status.pill.started"
        case .simulating: "status.pill.simulating"
        case .paused: "status.pill.paused"
        case .stopped: "status.pill.stopped"
        case .error: "status.pill.error"
        }
    }
}

public struct MovementConnectionRecovery: Equatable, Sendable {
    public let id: UUID
    public let executionID: UUID
    public let lease: MovementTaskLease
    public let coordinate: GeoCoordinate
    public let failure: DeviceServiceFailure
    public let resumesTask: Bool
    /// Only a user Retry repairs at this level. An automatic request means the
    /// device keeper's own reconnect already failed or is out of budget.
    public let explicitlyRequested: Bool
}

/// Concrete error messages behind the shared Error pill. Dismissing a toast
/// does not clear its underlying error; successful normal operations do.
public struct SessionStatusErrors: Equatable, Sendable {
    public let keys: [String]
    public var isEmpty: Bool { keys.isEmpty }

    public init(connection: VPNCheckState, service: DeviceServiceFailure? = nil,
                route: RouteExecutionFailure? = nil, joystick: JoystickFailure? = nil,
                wander: WanderSelectionFailure? = nil, wifiAvailable: Bool = true,
                dataErrors: [String] = []) {
        var messages: [String] = []
        if !wifiAvailable { messages.append("wifi.error.title") }
        switch connection {
        case .unavailable: messages.append(DeviceServiceFailure.tunnelUnavailable.rawValue)
        case .timedOut: messages.append(DeviceServiceFailure.operationTimedOut.rawValue)
        case .unknown, .checking, .reachable: break
        }
        messages += [service?.rawValue, route?.localizationKey, joystick?.localizationKey,
                     wander?.localizationKey].compactMap { $0 }
        messages += dataErrors
        var seen: Set<String> = []
        keys = messages.filter {
            $0 != DeviceServiceFailure.operationCancelled.rawValue && !IssueCatalog.isValidation($0)
                && seen.insert($0).inserted
        }
    }
}
