import Combine
import Foundation

@MainActor
public final class ContinuedProcessingController: ObservableObject {
    @Published public private(set) var state: ContinuedProcessingState = .idle
    @Published public private(set) var currentRequest: ContinuedProcessingRequest?
    @Published public private(set) var grant: ContinuedProcessingGrant?
    @Published public private(set) var progress: ContinuedProcessingProgress = .zero
    @Published public private(set) var completionOutcome: ContinuedProcessingCompletionOutcome?
    @Published public private(set) var error: ContinuedProcessingFailure?
    @Published public private(set) var receipts: [ContinuedProcessingReceipt] = []

    private let driver: any ContinuedProcessingDriving
    private let now: @Sendable () -> Date
    private let onRuntimeUnavailable: @MainActor @Sendable (UUID, ContinuedProcessingRuntimeLoss) -> Void
    private var registrationResult: Bool?
    private var generation: UInt64 = 0
    private var currentTitle = ""
    private var currentSubtitle = ""
    private var runtimeLossPublished = false

    public init(driver: any ContinuedProcessingDriving,
                now: @escaping @Sendable () -> Date = { Date() },
                onRuntimeUnavailable: @escaping @MainActor @Sendable (UUID, ContinuedProcessingRuntimeLoss) -> Void = { _, _ in }) {
        self.driver = driver
        self.now = now
        self.onRuntimeUnavailable = onRuntimeUnavailable
    }

    public var hasRuntime: Bool {
        guard state == .running, let request = currentRequest, let grant else { return false }
        return grant.isValid && grant.requestID == request.requestID &&
            grant.movementID == request.movementID && grant.lease == request.lease
    }

    @discardableResult
    public func register() -> Bool {
        if let registrationResult { return registrationResult }
        let result = driver.register()
        registrationResult = result
        guard result else {
            error = .registrationFailed
            if currentRequest == nil { state = .rejected }
            return false
        }
        return true
    }

    public func begin(_ request: ContinuedProcessingRequest, isForeground: Bool) async -> Bool {
        guard registrationResult == true else {
            rejectWithoutReplacement(.registrationFailed)
            return false
        }
        guard isForeground else {
            rejectWithoutReplacement(.notForeground)
            return false
        }

        supersedeCurrentIfNeeded()
        guard generation < UInt64.max else {
            state = .rejected
            error = .submissionRejected
            return false
        }
        generation += 1
        let submissionGeneration = generation
        currentRequest = request
        currentTitle = request.title
        currentSubtitle = request.subtitle
        progress = .zero
        grant = nil
        completionOutcome = nil
        error = nil
        runtimeLossPublished = false
        state = .submitting
        appendReceipt(for: request, event: .submitted)

        let eventHandler: @MainActor @Sendable (ContinuedProcessingEvent) -> Void = { [weak self] event in
            self?.receive(event, generation: submissionGeneration)
        }
        return await withTaskCancellationHandler(operation: {
            do {
                try await driver.submit(request, onEvent: eventHandler)
                guard !Task.isCancelled else {
                    cancelGeneration(submissionGeneration, reason: .cancelled)
                    return false
                }
                return acceptSubmission(submissionGeneration, request: request)
            } catch is CancellationError {
                cancelGeneration(submissionGeneration, reason: .cancelled)
                return false
            } catch let failure as ContinuedProcessingFailure {
                rejectSubmission(submissionGeneration, request: request, failure: failure)
                return false
            } catch {
                rejectSubmission(submissionGeneration, request: request, failure: .submissionRejected)
                return false
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelGeneration(submissionGeneration, reason: .cancelled)
            }
        })
    }

    @discardableResult
    public func update(requestID: UUID, progress newProgress: ContinuedProcessingProgress,
                       title: String, subtitle: String) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              state == .submitting || state == .accepted || state == .running,
              ContinuedProcessingRequest.isValidPresentation(title, maximumUTF8Bytes: 128),
              ContinuedProcessingRequest.isValidPresentation(subtitle, maximumUTF8Bytes: 512),
              isProgressAllowed(newProgress, for: request) else { return false }

        if state == .running {
            guard let grant, grant.isValid,
                  grant.requestID == request.requestID, grant.movementID == request.movementID,
                  grant.lease == request.lease else { return false }
        }

        let sameProgress = progress == newProgress
        let samePresentation = currentTitle == title && currentSubtitle == subtitle
        guard !sameProgress || !samePresentation else { return true }
        self.progress = newProgress
        currentTitle = title
        currentSubtitle = subtitle
        appendReceipt(for: request, event: .progressUpdated)

        guard state == .running, let grant, grant.isValid,
              grant.requestID == request.requestID, grant.movementID == request.movementID,
              grant.lease == request.lease else {
            return state != .running
        }
        driver.update(requestID: requestID, progress: newProgress, title: title, subtitle: subtitle)
        return true
    }

    @discardableResult
    public func finishFiniteArrival(requestID: UUID) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              request.kind == .finiteRoute,
              case .finiteDistance(let goal) = request.goal,
              progress.cumulativeAcknowledgedDistanceMeters == goal,
              state == .submitting || state == .accepted || state == .running else { return false }

        let oldGeneration = retireGeneration()
        let hadGrant = grant != nil
        guard hadGrant else {
            driver.cancel(requestID: requestID)
            state = .finished
            error = .cancelled
            appendReceipt(for: request, event: .cancelRequested)
            return false
        }

        let outcome = driver.finish(requestID: requestID, success: true)
        grant?.revoke()
        appendReceipt(for: request, event: .completionRequested(outcome))
        switch outcome {
        case .success:
            completionOutcome = .success
            error = nil
            state = .finished
            return true
        case .expired:
            completionOutcome = .expired
            state = .expired
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .expired)
            return false
        case .cancelled:
            completionOutcome = .cancelled
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .cancelled)
            return false
        case .invalidated:
            completionOutcome = .invalidated
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .invalidated)
            return false
        case .failed:
            completionOutcome = .failed
            state = .finished
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .invalidated)
            return false
        case nil:
            driver.cancel(requestID: requestID)
            state = .finished
            error = .cancelled
            return false
        }
    }

    @discardableResult
    public func cancel(requestID: UUID) -> Bool {
        guard let request = currentRequest, request.requestID == requestID,
              state == .submitting || state == .accepted || state == .running else { return false }
        let hadGrant = grant != nil
        let oldGeneration = retireGeneration()
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .cancelRequested)
        driver.cancel(requestID: requestID)
        if hadGrant {
            publishRuntimeLoss(requestID: requestID, generation: oldGeneration, reason: .cancelled)
        }
        return true
    }

    private func receive(_ event: ContinuedProcessingEvent, generation eventGeneration: UInt64) {
        guard eventGeneration == generation else {
            if case .launched(let incomingGrant) = event, incomingGrant !== grant { incomingGrant.revoke() }
            return
        }
        guard let request = currentRequest else {
            if case .launched(let incomingGrant) = event, incomingGrant !== grant { incomingGrant.revoke() }
            return
        }
        switch event {
        case .launched(let incomingGrant):
            guard incomingGrant.requestID == request.requestID,
                  incomingGrant.movementID == request.movementID,
                  incomingGrant.lease == request.lease,
                  incomingGrant.isValid,
                  state == .submitting || state == .accepted || state == .running else {
                incomingGrant.revoke()
                return
            }
            if let existingGrant = grant {
                if existingGrant === incomingGrant { return }
                incomingGrant.revoke()
                return
            }
            grant = incomingGrant
            state = .running
            appendReceipt(for: request, event: .launched)
            if progress != .zero || currentTitle != request.title || currentSubtitle != request.subtitle {
                driver.update(requestID: request.requestID, progress: progress,
                              title: currentTitle, subtitle: currentSubtitle)
            }
        case .expired(let requestID):
            guard requestID == request.requestID,
                  state == .submitting || state == .accepted || state == .running else { return }
            grant?.revoke()
            state = .expired
            completionOutcome = .expired
            appendReceipt(for: request, event: .expired)
            publishRuntimeLoss(requestID: requestID, generation: eventGeneration, reason: .expired)
        case .invalidated(let requestID):
            guard requestID == request.requestID,
                  state == .submitting || state == .accepted || state == .running else { return }
            grant?.revoke()
            state = .finished
            completionOutcome = .invalidated
            appendReceipt(for: request, event: .invalidated)
            publishRuntimeLoss(requestID: requestID, generation: eventGeneration, reason: .invalidated)
        }
    }

    private func acceptSubmission(_ eventGeneration: UInt64, request: ContinuedProcessingRequest) -> Bool {
        guard eventGeneration == generation, currentRequest?.requestID == request.requestID,
              state == .submitting || state == .accepted || state == .running else { return false }
        appendReceipt(for: request, event: .accepted)
        if state == .submitting { state = .accepted }
        return state == .accepted || state == .running
    }

    private func rejectSubmission(_ eventGeneration: UInt64, request: ContinuedProcessingRequest,
                                  failure: ContinuedProcessingFailure) {
        guard eventGeneration == generation, currentRequest?.requestID == request.requestID,
              state == .submitting || state == .accepted || state == .running else { return }
        let hadGrant = grant != nil
        let retiredGeneration = retireGeneration()
        grant?.revoke()
        state = .rejected
        error = failure
        appendReceipt(for: request, event: .rejected(failure))
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: retiredGeneration, reason: .submissionRejected) }
    }

    private func rejectWithoutReplacement(_ failure: ContinuedProcessingFailure) {
        guard state == .submitting || state == .accepted || state == .running else {
            state = .rejected
            error = failure
            return
        }
        error = failure
    }

    private func supersedeCurrentIfNeeded() {
        guard let request = currentRequest,
              state == .submitting || state == .accepted || state == .running else { return }
        let oldGeneration = retireGeneration()
        let hadGrant = grant != nil
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .superseded)
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: oldGeneration, reason: .superseded) }
    }

    private func cancelGeneration(_ eventGeneration: UInt64, reason: ContinuedProcessingRuntimeLoss) {
        guard eventGeneration == generation, let request = currentRequest,
              state == .submitting || state == .accepted || state == .running else { return }
        let hadGrant = grant != nil
        let retiredGeneration = retireGeneration()
        grant?.revoke()
        state = .finished
        error = .cancelled
        completionOutcome = nil
        appendReceipt(for: request, event: .cancelRequested)
        driver.cancel(requestID: request.requestID)
        if hadGrant { publishRuntimeLoss(requestID: request.requestID, generation: retiredGeneration, reason: reason) }
    }

    private func isProgressAllowed(_ candidate: ContinuedProcessingProgress,
                                   for request: ContinuedProcessingRequest) -> Bool {
        guard candidate.acknowledgedWrites >= progress.acknowledgedWrites,
              candidate.cumulativeAcknowledgedDistanceMeters >= progress.cumulativeAcknowledgedDistanceMeters else { return false }
        if case .finiteDistance(let goal) = request.goal {
            return candidate.cumulativeAcknowledgedDistanceMeters <= goal
        }
        return true
    }

    private func publishRuntimeLoss(requestID: UUID, generation eventGeneration: UInt64,
                                    reason: ContinuedProcessingRuntimeLoss) {
        guard eventGeneration == generation || (eventGeneration < UInt64.max && eventGeneration + 1 == generation),
              !runtimeLossPublished else { return }
        runtimeLossPublished = true
        onRuntimeUnavailable(requestID, reason)
    }

    @discardableResult
    private func retireGeneration() -> UInt64 {
        let retired = generation
        if generation < UInt64.max { generation += 1 }
        return retired
    }

    private func appendReceipt(for request: ContinuedProcessingRequest,
                               event: ContinuedProcessingReceiptEvent) {
        let receipt = ContinuedProcessingReceipt(timestamp: now(), requestID: request.requestID,
                                                 kind: request.kind, event: event, progress: progress)
        receipts.append(receipt)
        if receipts.count > 256 { receipts.removeFirst(receipts.count - 256) }
    }
}
