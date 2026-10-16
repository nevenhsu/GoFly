import Combine
import Dispatch
import Foundation

/// The synchronous engine boundary used by the command coordinator.
///
/// Implementations are expected to own their device/FFI handle and to be safe
/// to call from the coordinator's private serial operation queue.
public protocol LocationEngine: Sendable {
    func set(latitude: Double, longitude: Double) throws
    func clear() throws
}

public struct LocationCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LocationCommandPhase: Equatable, Sendable {
    case idle
    case preparing
    case applying
    case accepted
    case clearing
    case unknownFailure
}

public struct LocationCommandError: Equatable, Identifiable, Sendable {
    public enum Stage: String, Equatable, Sendable {
        case setup
        case validation
        case applying
        case clearing
        case rejected
    }

    public let code: Int
    public let stage: Stage
    public let message: String

    /// Stable numeric identifier for UI, logs, and telemetry without exposing
    /// an engine's raw error value.
    public var numericCode: Int {
        code
    }

    public var id: String {
        "\(code):\(stage.rawValue)"
    }

    public init(code: Int, stage: Stage, message: String) {
        self.code = code
        self.stage = stage
        self.message = message
    }
}

/// Owns all location-engine calls and exposes a small main-actor state model.
///
/// Every set is admitted on the main actor and executed in order on the
/// private serial queue. `stop()` immediately invalidates all queued sets;
/// an already-running synchronous set is allowed to return, after which the
/// queued clear is the next engine operation.
@MainActor
public final class LocationCommandCoordinator: ObservableObject {
    @Published public private(set) var phase: LocationCommandPhase
    @Published public private(set) var latestAcceptedCoordinate: LocationCoordinate?
    @Published public private(set) var error: LocationCommandError?

    private let engine: (any LocationEngine)?
    private let operationQueue: DispatchQueue
    private let gate: LocationOperationGate

    public init(
        engine: (any LocationEngine)?,
        setupFailureMessage: String = "Location engine is unavailable."
    ) {
        self.engine = engine
        self.operationQueue = DispatchQueue(
            label: "com.stikdebug.localgo.location-command",
            qos: .userInitiated
        )
        self.gate = LocationOperationGate(isEngineReady: engine != nil)
        self.latestAcceptedCoordinate = nil

        if engine == nil {
            self.phase = .unknownFailure
            self.error = LocationCommandError(
                code: LocationCommandErrorCode.setupUnavailable,
                stage: .setup,
                message: LocationCommandCoordinator.sanitizeSetupMessage(setupFailureMessage)
            )
        } else {
            self.phase = .idle
            self.error = nil
        }
    }

    public func apply(latitude: Double, longitude: Double) {
        guard let coordinate = Self.validatedCoordinate(latitude: latitude, longitude: longitude) else {
            error = Self.validationError(latitude: latitude, longitude: longitude)
            return
        }

        switch gate.admitSet(coordinate) {
        case .accepted(let token):
            phase = .preparing
            error = nil
            enqueueSet(token)
        case .engineUnavailable:
            phase = .unknownFailure
            if error?.stage != .setup {
                error = LocationCommandError(
                    code: LocationCommandErrorCode.setupUnavailable,
                    stage: .setup,
                    message: "Location engine is unavailable."
                )
            }
        case .clearing:
            error = LocationCommandError(
                code: LocationCommandErrorCode.rejectedWhileClearing,
                stage: .rejected,
                message: "Location changes are paused while clearing."
            )
        case .failed:
            phase = .unknownFailure
            error = LocationCommandError(
                code: LocationCommandErrorCode.rejectedAfterFailure,
                stage: .rejected,
                message: "Location changes are unavailable after a failure."
            )
        }
    }

    /// Explicit recovery may reissue a clear even after a prior acknowledgement.
    /// An in-flight clear is still shared and queued sets remain invalidated.
    public func stop(forceClear: Bool = false) {
        switch gate.admitStop(forceClear: forceClear) {
        case .scheduled(let token):
            latestAcceptedCoordinate = nil
            error = nil
            phase = .clearing
            enqueueClear(token)
        case .alreadyScheduled:
            latestAcceptedCoordinate = nil
            error = nil
            phase = .clearing
        case .nothingToDo:
            latestAcceptedCoordinate = nil
            error = nil
            phase = .idle
        case .engineUnavailable:
            phase = .unknownFailure
            if error?.stage != .setup {
                error = LocationCommandError(
                    code: LocationCommandErrorCode.setupUnavailable,
                    stage: .setup,
                    message: "Location engine is unavailable."
                )
            }
        }
    }

    private func enqueueSet(_ token: LocationOperationGate.SetToken) {
        guard let engine else { return }
        let gate = gate
        operationQueue.async { [weak self, engine, gate] in
            guard gate.beginSet(token) else { return }

            Task { @MainActor [weak self, gate] in
                guard let self, gate.shouldPublishApplying(token) else { return }
                self.phase = .applying
            }

            do {
                try engine.set(latitude: token.coordinate.latitude, longitude: token.coordinate.longitude)
                let result = gate.finishSet(token, succeeded: true)
                guard case .accepted = result else { return }
                Task { @MainActor [weak self, gate] in
                    guard let self, gate.shouldPublishSet(token) else { return }
                    self.latestAcceptedCoordinate = token.coordinate
                    self.phase = .accepted
                    self.error = nil
                }
            } catch {
                let result = gate.finishSet(token, succeeded: false)
                guard case .failed = result else { return }
                Task { @MainActor [weak self, gate] in
                    guard let self, gate.shouldPublishSetFailure(token) else { return }
                    self.phase = .unknownFailure
                    self.error = LocationCommandError(
                        code: LocationCommandErrorCode.engineSetFailed,
                        stage: .applying,
                        message: "The location engine could not apply the coordinate."
                    )
                }
            }
        }
    }

    private func enqueueClear(_ token: LocationOperationGate.ClearToken) {
        guard let engine else { return }
        let gate = gate
        operationQueue.async { [weak self, engine, gate] in
            guard gate.beginClear(token) else { return }

            do {
                try engine.clear()
                let result = gate.finishClear(token, succeeded: true)
                guard case .succeeded = result else { return }
                Task { @MainActor [weak self, gate] in
                    guard let self, gate.shouldPublishClear(token) else { return }
                    self.latestAcceptedCoordinate = nil
                    self.phase = .idle
                    self.error = nil
                }
            } catch {
                let result = gate.finishClear(token, succeeded: false)
                guard case .failed = result else { return }
                Task { @MainActor [weak self, gate] in
                    guard let self, gate.shouldPublishClearFailure(token) else { return }
                    self.latestAcceptedCoordinate = nil
                    self.phase = .unknownFailure
                    self.error = LocationCommandError(
                        code: LocationCommandErrorCode.engineClearFailed,
                        stage: .clearing,
                        message: "The location engine could not clear the coordinate."
                    )
                }
            }
        }
    }

    private static func validatedCoordinate(latitude: Double, longitude: Double) -> LocationCoordinate? {
        guard latitude.isFinite, longitude.isFinite,
              (-90.0...90.0).contains(latitude),
              (-180.0...180.0).contains(longitude) else {
            return nil
        }
        return LocationCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func validationError(latitude: Double, longitude: Double) -> LocationCommandError {
        if !latitude.isFinite || !(-90.0...90.0).contains(latitude) {
            return LocationCommandError(
                code: LocationCommandErrorCode.invalidLatitude,
                stage: .validation,
                message: "Latitude must be a finite value from -90 to 90."
            )
        }
        if !longitude.isFinite || !(-180.0...180.0).contains(longitude) {
            return LocationCommandError(
                code: LocationCommandErrorCode.invalidLongitude,
                stage: .validation,
                message: "Longitude must be a finite value from -180 to 180."
            )
        }
        return LocationCommandError(
            code: LocationCommandErrorCode.invalidCoordinate,
            stage: .validation,
            message: "The coordinate is outside the supported range."
        )
    }

    private static func sanitizeSetupMessage(_ message: String) -> String {
        let singleLine = message
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else { return "Location engine is unavailable." }
        return String(singleLine.prefix(160))
    }
}

private enum LocationCommandErrorCode {
    static let setupUnavailable = 1001
    static let invalidLatitude = 2001
    static let invalidLongitude = 2002
    static let invalidCoordinate = 2003
    static let rejectedWhileClearing = 3001
    static let rejectedAfterFailure = 3002
    static let engineSetFailed = 4001
    static let engineClearFailed = 5001
}

private final class LocationOperationGate: @unchecked Sendable {
    struct SetToken: Equatable, Sendable {
        let id: UInt64
        let generation: UInt64
        let coordinate: LocationCoordinate
    }

    struct ClearToken: Equatable, Sendable {
        let id: UInt64
        let generation: UInt64
        let session: UInt64
    }

    enum SetAdmission {
        case accepted(SetToken)
        case engineUnavailable
        case clearing
        case failed
    }

    enum StopAdmission {
        case scheduled(ClearToken)
        case alreadyScheduled
        case nothingToDo
        case engineUnavailable
    }

    enum SetCompletion {
        case accepted
        case failed
        case stale
    }

    enum ClearCompletion {
        case succeeded
        case failed
        case stale
    }

    private let lock = NSLock()
    private let isEngineReady: Bool
    private var generation: UInt64 = 0
    private var nextID: UInt64 = 0
    private var session: UInt64 = 0
    private var latestRequestedID: UInt64?
    private var pendingSets: [SetToken] = []
    private var runningSet: SetToken?
    private var sessionFailed = false
    private var stopRequested = false
    private var stopCompleted = false
    private var clearToken: ClearToken?
    private var runningClear: ClearToken?

    init(isEngineReady: Bool) {
        self.isEngineReady = isEngineReady
    }

    func admitSet(_ coordinate: LocationCoordinate) -> SetAdmission {
        lock.lock()
        defer { lock.unlock() }

        guard isEngineReady else { return .engineUnavailable }
        if clearToken != nil { return .clearing }
        if stopRequested || sessionFailed { return .failed }

        nextID &+= 1
        session &+= 1
        stopCompleted = false
        let token = SetToken(id: nextID, generation: generation, coordinate: coordinate)
        latestRequestedID = token.id
        pendingSets.append(token)
        return .accepted(token)
    }

    func admitStop(forceClear: Bool) -> StopAdmission {
        lock.lock()
        defer { lock.unlock() }

        guard isEngineReady else { return .engineUnavailable }
        if clearToken != nil { return .alreadyScheduled }
        if !forceClear && stopCompleted && pendingSets.isEmpty && runningSet == nil && !sessionFailed {
            return .nothingToDo
        }

        generation &+= 1
        stopRequested = true
        nextID &+= 1
        clearToken = ClearToken(id: nextID, generation: generation, session: session)
        return .scheduled(clearToken!)
    }

    func beginSet(_ token: SetToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let index = pendingSets.firstIndex(of: token) else { return false }
        pendingSets.remove(at: index)
        guard !stopRequested, !sessionFailed, token.generation == generation, runningSet == nil else {
            return false
        }
        runningSet = token
        return true
    }

    func finishSet(_ token: SetToken, succeeded: Bool) -> SetCompletion {
        lock.lock()
        defer { lock.unlock() }

        guard runningSet == token else { return .stale }
        runningSet = nil
        if stopRequested || token.generation != generation {
            return .stale
        }
        guard succeeded else {
            sessionFailed = true
            pendingSets.removeAll(keepingCapacity: false)
            return .failed
        }
        return .accepted
    }

    func beginClear(_ token: ClearToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard clearToken == token,
              runningClear == nil,
              runningSet == nil,
              pendingSets.isEmpty,
              stopRequested else {
            return false
        }
        runningClear = token
        return true
    }

    func finishClear(_ token: ClearToken, succeeded: Bool) -> ClearCompletion {
        lock.lock()
        defer { lock.unlock() }

        guard runningClear == token else { return .stale }
        runningClear = nil
        clearToken = nil
        guard succeeded else {
            sessionFailed = true
            stopCompleted = false
            return .failed
        }
        sessionFailed = false
        stopRequested = false
        stopCompleted = true
        latestRequestedID = nil
        return .succeeded
    }

    func shouldPublishSet(_ token: SetToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token.generation == generation && token.id == latestRequestedID
            && !stopRequested && !sessionFailed
    }

    func shouldPublishApplying(_ token: SetToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return runningSet == token && token.generation == generation && token.id == latestRequestedID
            && !stopRequested && !sessionFailed
    }

    func shouldPublishSetFailure(_ token: SetToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return token.generation == generation && !stopRequested
    }

    func shouldPublishClear(_ token: ClearToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return clearToken == nil && runningClear == nil && pendingSets.isEmpty && runningSet == nil
            && !sessionFailed && !stopRequested && session == token.session
    }

    func shouldPublishClearFailure(_ token: ClearToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return clearToken == nil && runningClear == nil && pendingSets.isEmpty && runningSet == nil
            && sessionFailed && stopRequested && session == token.session
    }

}
