import Combine
import Foundation

@MainActor
public final class ServiceController: ObservableObject {
    @Published public private(set) var phase: ServicePhase = .stopped
    @Published public private(set) var nativeBusy = false
    @Published public private(set) var error: DeviceServiceFailure?
    @Published public private(set) var clearState: ClearState = .unknown
    @Published public private(set) var clearConfirmedAt: Date?
    @Published public private(set) var realLocation: RealLocationObservation?

    private let service: any DeviceService
    private let operationTimeout: Duration
    private let now: @Sendable () -> Date
    private var revision: UInt64 = 0
    private var outstandingWork = 0
    private var clearScheduled = false
    private var clearAttempted = false
    private var tail: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    public init(
        service: any DeviceService, operationTimeout: Duration = .seconds(30),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.service = service
        self.operationTimeout = operationTimeout
        self.now = now
    }
    public var statusKey: String {
        if phase == .stopped, clearAttempted, clearState == .unknown {
            return "service.stoppedGPSPending"
        }
        return "service.\(phase.rawValue)"
    }
    public var gpsStatusKey: String {
        switch clearState {
        case .unknown: return "gps.unknown"
        case .pending: return "gps.clearing"
        case .confirmed:
            guard let realLocation, let clearConfirmedAt,
                  realLocation.observedAt >= clearConfirmedAt else { return "gps.clearedWaiting" }
            return "gps.observed"
        }
    }
    public var canStart: Bool { !nativeBusy && phase == .stopped }
    public var canStop: Bool {
        !clearScheduled && (phase == .ready || phase == .preparing || phase == .repairRequired)
    }
    public var canRestoreGPS: Bool { !nativeBusy && phase == .stopped }
    public var canResetTunnel: Bool { canRestoreGPS }

    @discardableResult public func start() -> Bool {
        guard canStart else { return false }
        enqueue(.preparing) { try await $0.prepare() }
        return true
    }

    /// Invalidates visible results immediately. Safety cleanup is a separate,
    /// unconditional FIFO command: a canceled preparation cannot skip it.
    @discardableResult public func stop() -> Bool {
        guard canStop else { return false }
        clearScheduled = true
        clearAttempted = true
        clearState = .pending
        clearConfirmedAt = nil
        realLocation = nil
        enqueue(.stopping) { try await $0.clearLocation() }
        return true
    }

    @discardableResult public func restoreGPS() -> Bool {
        guard canRestoreGPS else { return false }
        clearScheduled = true
        clearAttempted = true
        clearState = .pending
        clearConfirmedAt = nil
        realLocation = nil
        enqueue(.restoring) { try await $0.clearLocation() }
        return true
    }

    @discardableResult public func resetTunnel() -> Bool {
        guard canResetTunnel else { return false }
        enqueue(.resetting) { try await $0.resetClientConnection() }
        return true
    }

    /// GPS and clear are independent evidence. Valid readings can center the
    /// map even before clear; only a post-clear reading proves that sequence.
    public func observeRealLocation(_ observation: RealLocationObservation?) {
        guard let observation,
              observation.observedAt <= now(),
              now().timeIntervalSince(observation.observedAt) <= 15 else {
            realLocation = nil
            return
        }
        realLocation = observation
    }

    private func enqueue(
        _ operation: ServicePhase,
        work: @escaping @Sendable (any DeviceService) async throws -> Void
    ) {
        revision &+= 1
        let token = revision
        let previous = tail
        phase = operation
        error = nil
        nativeBusy = true
        outstandingWork += 1
        watchdog?.cancel()
        let timeout = operationTimeout
        watchdog = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.revision == token, self.nativeBusy else { return }
            self.revision &+= 1
            self.phase = .repairRequired
            self.error = .operationTimedOut
            if operation == .stopping || operation == .restoring {
                self.clearState = .unknown
            }
            // Do not cancel, free, or mark the native work complete. Only its
            // actual return can unlock commands; Stop may queue one clear.
        }
        let service = service
        tail = Task { [weak self] in
            await previous?.value
            let result: Result<Void, DeviceServiceFailure>
            do {
                try await work(service)
                result = .success(())
            } catch {
                result = .failure(error as? DeviceServiceFailure ?? .serviceUnavailable)
            }
            self?.complete(operation, token: token, result: result)
        }
    }

    private func complete(
        _ operation: ServicePhase, token: UInt64,
        result: Result<Void, DeviceServiceFailure>
    ) {
        outstandingWork -= 1
        if operation == .stopping || operation == .restoring { clearScheduled = false }
        if token == revision {
            watchdog?.cancel()
            switch result {
            case .success:
                phase = operation == .preparing ? .ready : .stopped
                error = nil
                if operation == .stopping || operation == .restoring {
                    clearState = .confirmed
                    clearConfirmedAt = now()
                }
            case .failure(let failure):
                phase = .stopped
                error = failure
                if operation == .stopping || operation == .restoring {
                    clearState = .unknown
                    clearConfirmedAt = nil
                }
            }
        }
        if outstandingWork == 0 {
            nativeBusy = false
            tail = nil
            if phase == .repairRequired { phase = .stopped }
        }
    }
}
