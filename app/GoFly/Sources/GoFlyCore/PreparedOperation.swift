import Foundation

public enum PreparedOperationSource: Equatable, Sendable {
    case start
    case point(PointMoveIntent)
    case route(RouteExecutionIntent)
    case joystick(JoystickMovementIntent)

    /// Stable, short label for diagnostics records. Never includes coordinates.
    public var diagnosticsLabel: String {
        switch self {
        case .start: "start"
        case .point: "point"
        case .route: "route.begin"
        case .joystick: "joystick.begin"
        }
    }
}

public struct PreparationAttempt: Equatable, Sendable {
    public let value: Int
    public init?(_ value: Int) {
        guard (1...3).contains(value) else { return nil }
        self.value = value
    }
    static let first = PreparationAttempt(1)!
    var next: PreparationAttempt? { PreparationAttempt(value + 1) }
}

public enum PreparedOperationState: Equatable, Sendable {
    case preparing
    case failed(DeviceServiceFailure)
    case cancelled
}

public struct PreparedOperationSnapshot: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: PreparedOperationSource
    public let attempt: PreparationAttempt
    public let state: PreparedOperationState
}
