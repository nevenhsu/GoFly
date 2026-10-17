import Foundation

public enum ContinuedProcessingKind: String, CaseIterable, Equatable, Sendable {
    case finiteRoute
    case roundTrip
    case wander
}

public enum ContinuedProcessingGoal: Equatable, Sendable {
    case finiteDistance(meters: Double)
    case experimentalIndeterminate
}

public struct ContinuedProcessingRequest: Equatable, Sendable {
    public let requestID: UUID
    public let movementID: UUID
    public let lease: MovementTaskLease
    public let kind: ContinuedProcessingKind
    public let goal: ContinuedProcessingGoal
    public let title: String
    public let subtitle: String

    public init?(requestID: UUID = UUID(), movementID: UUID, lease: MovementTaskLease,
                 kind: ContinuedProcessingKind, goal: ContinuedProcessingGoal,
                 title: String, subtitle: String) {
        guard Self.isValidPresentation(title, maximumUTF8Bytes: 128),
              Self.isValidPresentation(subtitle, maximumUTF8Bytes: 512),
              Self.isValid(kind: kind, goal: goal) else { return nil }
        self.requestID = requestID
        self.movementID = movementID
        self.lease = lease
        self.kind = kind
        self.goal = goal
        self.title = title
        self.subtitle = subtitle
    }

    static func isValidPresentation(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumUTF8Bytes else { return false }
        return !value.unicodeScalars.contains { $0.value == 0 }
    }

    static func isValid(kind: ContinuedProcessingKind, goal: ContinuedProcessingGoal) -> Bool {
        switch (kind, goal) {
        case (.finiteRoute, .finiteDistance(let meters)):
            return meters.isFinite && meters > 0
        case (.finiteRoute, .experimentalIndeterminate):
            return false
        case (.roundTrip, .experimentalIndeterminate), (.wander, .experimentalIndeterminate):
            return true
        case (.roundTrip, .finiteDistance), (.wander, .finiteDistance):
            return false
        }
    }
}

public struct ContinuedProcessingProgress: Equatable, Sendable {
    public let acknowledgedWrites: Int64
    public let cumulativeAcknowledgedDistanceMeters: Double

    public init?(acknowledgedWrites: Int64, cumulativeAcknowledgedDistanceMeters: Double) {
        guard acknowledgedWrites >= 0,
              cumulativeAcknowledgedDistanceMeters.isFinite,
              cumulativeAcknowledgedDistanceMeters >= 0 else { return nil }
        self.acknowledgedWrites = acknowledgedWrites
        self.cumulativeAcknowledgedDistanceMeters = cumulativeAcknowledgedDistanceMeters
    }

    public static let zero = ContinuedProcessingProgress(acknowledgedWrites: 0,
                                                          cumulativeAcknowledgedDistanceMeters: 0)!
}

public enum ContinuedProcessingFailure: Error, Equatable, Sendable {
    case unsupportedSystem
    case registrationFailed
    case notForeground
    case submissionRejected
    case cancelled
    case invalidProgress
}

public enum ContinuedProcessingState: Equatable, Sendable {
    case idle
    case submitting
    case accepted
    case running
    case rejected
    case expired
    case finished
}

public enum ContinuedProcessingRuntimeLoss: Equatable, Sendable {
    case expired
    case invalidated
    case submissionRejected
    case cancelled
    case superseded
}

public enum ContinuedProcessingEvent: Sendable {
    case launched(ContinuedProcessingGrant)
    case expired(requestID: UUID)
    case invalidated(requestID: UUID)
}

public enum ContinuedProcessingCompletionOutcome: String, Equatable, Sendable {
    case success
    case expired
    case cancelled
    case invalidated
    case failed
}

public struct ContinuedProcessingCompletionClaim: Equatable, Sendable {
    public let outcome: ContinuedProcessingCompletionOutcome
    public let isFirst: Bool

    init(outcome: ContinuedProcessingCompletionOutcome, isFirst: Bool) {
        self.outcome = outcome
        self.isFirst = isFirst
    }
}

public enum ContinuedProcessingReceiptEvent: Equatable, Sendable {
    case submitted
    case accepted
    case launched
    case rejected(ContinuedProcessingFailure)
    case expired
    case invalidated
    case cancelRequested
    case superseded
    case progressUpdated
    case completionRequested(ContinuedProcessingCompletionOutcome?)
}

public struct ContinuedProcessingReceipt: Equatable, Sendable {
    public let timestamp: Date
    public let requestID: UUID
    public let kind: ContinuedProcessingKind
    public let event: ContinuedProcessingReceiptEvent
    public let acknowledgedWrites: Int64
    public let cumulativeAcknowledgedDistanceMeters: Double
    public let candidateVersion: Int

    init(timestamp: Date, requestID: UUID, kind: ContinuedProcessingKind,
         event: ContinuedProcessingReceiptEvent, progress: ContinuedProcessingProgress,
         candidateVersion: Int = 1) {
        self.timestamp = timestamp
        self.requestID = requestID
        self.kind = kind
        self.event = event
        self.acknowledgedWrites = progress.acknowledgedWrites
        self.cumulativeAcknowledgedDistanceMeters = progress.cumulativeAcknowledgedDistanceMeters
        self.candidateVersion = candidateVersion
    }
}

@MainActor
public protocol ContinuedProcessingDriving: AnyObject {
    func register() -> Bool
    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws
    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String)
    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome?
    func cancel(requestID: UUID)
}
