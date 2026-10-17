import BackgroundTasks
import Foundation
import GoFlyCore

/// The concrete BackgroundTasks adapter for the continued-processing candidate.
///
/// One process-owned adapter translates Core lifecycle commands to actual
/// BackgroundTasks callbacks. Only a matching framework launch creates a grant.
@available(iOS 26.0, *)
@MainActor
public final class GoFlyContinuedProcessingDriver: ContinuedProcessingDriving {
    public static let shared = GoFlyContinuedProcessingDriver()

    private static let permittedIdentifier = "com.neven.gofly.movement.*"
    private static let identifierPrefix = "com.neven.gofly.movement."

    private let scheduler: BGTaskScheduler
    private var registrationResult: Bool?
    private let registrationBook = ContinuedProcessingRegistrationBook()
    private var currentRequest: ContinuedProcessingRequest?
    private var currentBox: TaskBox?
    private var currentEventHandler: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?

    // The map deliberately uses weak object identity for keys. Values stay
    // alive until the framework task has received its one completion request.
    // No retired-task array or raw-pointer cache is needed.
    private let taskBoxes = NSMapTable<BGTask, TaskBox>(
        keyOptions: [.weakMemory, .objectPointerPersonality],
        valueOptions: [.strongMemory]
    )

    private init() {
        scheduler = .shared
    }

    @discardableResult
    public func register() -> Bool {
        if let registrationResult {
            return registrationResult
        }

        // Continued-processing handlers may be registered after launch. The
        // plist permits a family; SDK registration uses each concrete ID below.
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
            as? [String] ?? []
        let result = permitted.contains(Self.permittedIdentifier)
        registrationResult = result
        return result
    }

    public func submit(
        _ request: ContinuedProcessingRequest,
        onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void
    ) async throws {
        guard register() else {
            throw ContinuedProcessingFailure.registrationFailed
        }
        switch registrationBook.reserve(request.requestID) {
        case .reserved:
            break
        case .alreadyAttempted:
            throw ContinuedProcessingFailure.registrationFailed
        case .capacityReached:
            throw ContinuedProcessingFailure.registrationLimitReached
        }

        let requestID = request.requestID
        let identifier = Self.identifier(for: request)
        // SDK has no unregister-handler API. Reserve every attempt permanently
        // within the bounded book; retain only a weak adapter and an identity.
        let registered = scheduler.register(forTaskWithIdentifier: identifier, using: .main) {
            [weak self] task in
            MainActor.assumeIsolated {
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.receive(task: task, expectedRequestID: requestID)
            }
        }
        guard registered else {
            throw ContinuedProcessingFailure.registrationFailed
        }

        // Registration failure does not retire another current task. Actual
        // takeover follows the Core consent/ownership policy before submission.
        retireCurrentRequest()
        currentRequest = request
        currentBox = nil
        currentEventHandler = onEvent

        let taskRequest = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: request.title,
            subtitle: request.subtitle
        )
        taskRequest.strategy = .fail
        // The empty option set is the SDK spelling of default CPU/network
        // resources. GPU is intentionally never requested.
        taskRequest.requiredResources = []

        do {
            if #available(iOS 27.0, *) {
                try await scheduler.submitTaskRequest(taskRequest)
            } else {
                // SDK 26 exposes only the throwing legacy submission method.
                try scheduler.submit(taskRequest)
            }
        } catch is CancellationError {
            if isCurrent(requestID: request.requestID), currentBox == nil {
                clearCurrentRequest()
            }
            throw CancellationError()
        } catch {
            // Keep a launched box installed. Core will close it through
            // cancel(), which handles the rejected-after-launch race.
            if isCurrent(requestID: request.requestID), currentBox == nil {
                clearCurrentRequest()
            }
            throw ContinuedProcessingFailure.submissionRejected
        }

        // The async submission completion can be delayed until after launch,
        // cancellation, or supersession. It never reopens old work.
        guard isCurrent(requestID: request.requestID) else {
            throw CancellationError()
        }
        if Task.isCancelled {
            cancel(requestID: request.requestID)
            throw CancellationError()
        }
    }

    public func update(
        requestID: UUID,
        progress: ContinuedProcessingProgress,
        title: String,
        subtitle: String
    ) {
        guard let request = currentRequest,
              request.requestID == requestID,
              let box = currentBox,
              isValidPresentation(title, maximumUTF8Bytes: 128),
              isValidPresentation(subtitle, maximumUTF8Bytes: 512) else {
            return
        }
        box.update(progress: progress, request: request, title: title, subtitle: subtitle)
    }

    public func finish(
        requestID: UUID,
        success: Bool
    ) -> ContinuedProcessingCompletionOutcome? {
        guard let request = currentRequest,
              request.requestID == requestID,
              let box = currentBox else {
            return nil
        }

        let mayCompleteSuccessfully: Bool
        switch request.goal {
        case .finiteDistance:
            mayCompleteSuccessfully = request.kind == .finiteRoute
        case .experimentalIndeterminate:
            mayCompleteSuccessfully = false
        }
        let outcome = box.finish(success: success && mayCompleteSuccessfully)
        clearCurrentRequest()
        return outcome
    }

    public func cancel(requestID: UUID) {
        guard let request = currentRequest, request.requestID == requestID else {
            return
        }

        // Close the actual task before clearing ownership. A late expiry then
        // sees the sealed cancellation and remains silent.
        currentBox?.cancel()
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier(for: request))
        clearCurrentRequest()
    }

    private func receive(task: BGTask, expectedRequestID: UUID) {
        // A duplicate callback for the same object reuses its box. In
        // particular, it never replaces a valid current task or completes the
        // framework object a second time.
        if taskBoxes.object(forKey: task) != nil {
            return
        }

        guard let continuedTask = task as? BGContinuedProcessingTask,
              let request = currentRequest,
              request.requestID == expectedRequestID,
              currentBox == nil,
              task.identifier == Self.identifier(for: request),
              let eventHandler = currentEventHandler else {
            dispose(task: task)
            return
        }

        // Install the registry, current ownership, and expiry handler before
        // invoking Core's potentially reentrant launch callback.
        let grant = ContinuedProcessingGrant(
            requestID: request.requestID,
            movementID: request.movementID,
            lease: request.lease
        )
        let box = TaskBox(
            task: continuedTask,
            requestID: request.requestID,
            grant: grant,
            onEvent: eventHandler
        )
        taskBoxes.setObject(box, forKey: task)
        currentBox = box
        box.installExpirationHandler()

        eventHandler(.launched(grant))
    }

    private func dispose(task: BGTask) {
        let box = TaskBox(task: task, requestID: nil, grant: nil, onEvent: nil)
        taskBoxes.setObject(box, forKey: task)
        box.installExpirationHandler()
        box.dispose()
    }

    private func retireCurrentRequest() {
        guard let request = currentRequest else { return }
        currentBox?.cancel()
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier(for: request))
        clearCurrentRequest()
    }

    private func clearCurrentRequest() {
        currentRequest = nil
        currentBox = nil
        currentEventHandler = nil
    }

    private func isCurrent(requestID: UUID) -> Bool {
        currentRequest?.requestID == requestID
    }

    private static func identifier(for request: ContinuedProcessingRequest) -> String {
        identifierPrefix + request.requestID.uuidString
    }

    private static func isValidPresentation(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.utf8.count <= maximumUTF8Bytes else {
            return false
        }
        return !value.unicodeScalars.contains { $0.value == 0 }
    }

    private func isValidPresentation(_ value: String, maximumUTF8Bytes: Int) -> Bool {
        Self.isValidPresentation(value, maximumUTF8Bytes: maximumUTF8Bytes)
    }

    private final class TaskBox: @unchecked Sendable {
        private let stateLock = NSLock()
        private var strongTask: BGTask?
        private var admissionClosed = false
        private var frameworkCompletionDelivered = false

        private let requestID: UUID?
        private let grant: ContinuedProcessingGrant?
        private let completion: ContinuedProcessingTaskCompletion
        private let onEvent: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?

        init(
            task: BGTask,
            requestID: UUID?,
            grant: ContinuedProcessingGrant?,
            onEvent: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
        ) {
            strongTask = task
            self.requestID = requestID
            self.grant = grant
            completion = ContinuedProcessingTaskCompletion(grant: grant)
            self.onEvent = onEvent
        }

        @MainActor
        func installExpirationHandler() {
            stateLock.lock()
            let task = strongTask
            stateLock.unlock()
            task?.expirationHandler = { [weak self] in
                self?.expire()
            }
        }

        @MainActor
        func update(
            progress: ContinuedProcessingProgress,
            request: ContinuedProcessingRequest,
            title: String,
            subtitle: String
        ) {
            guard let task = admitUpdate() else { return }

            let presentation = Self.foundationProgress(for: progress, request: request)
            task.progress.totalUnitCount = presentation.total
            task.progress.completedUnitCount = presentation.completed
            task.updateTitle(title, subtitle: subtitle)
        }

        @MainActor
        func finish(success: Bool) -> ContinuedProcessingCompletionOutcome {
            closeAdmission()
            let claim = completion.claim(success ? .success : .failed)
            completeFrameworkTask(success: claim.outcome == .success)
            return claim.outcome
        }

        @MainActor
        func cancel() {
            closeAdmission()
            let claim = completion.claim(.cancelled)
            completeFrameworkTask(success: claim.outcome == .success)
        }

        @MainActor
        func dispose() {
            closeAdmission()
            let claim = completion.claim(.invalidated)
            completeFrameworkTask(success: claim.outcome == .success)
        }

        private func expire() {
            // Close admission and seal/revoke synchronously on the framework's
            // callback queue. Only the first expired claim queues an event.
            closeAdmission()
            let claim = completion.claim(.expired)
            guard claim.isFirst, claim.outcome == .expired else { return }

            guard let requestID, let onEvent else { return }
            let event = ContinuedProcessingEvent.expired(requestID: requestID)
            // Expiry sealing is synchronous above; framework completion and
            // Core notification are delivered together on MainActor. The box
            // remains retained by the identity registry until this delivery
            // releases its strong framework-task reference.
            Task { @MainActor [weak self] in
                self?.completeFrameworkTask(success: false)
                onEvent(event)
            }
        }

        private func admitUpdate() -> BGContinuedProcessingTask? {
            stateLock.lock()
            defer { stateLock.unlock() }
            guard !admissionClosed,
                  let grant,
                  grant.isValid,
                  let task = strongTask as? BGContinuedProcessingTask else {
                return nil
            }
            // Returning the strongly held task is the admission boundary. A
            // concurrent close may finish after this point, but cannot admit a
            // later update.
            return task
        }

        private func closeAdmission() {
            stateLock.lock()
            admissionClosed = true
            stateLock.unlock()
        }

        @MainActor
        private func completeFrameworkTask(success: Bool) {
            stateLock.lock()
            guard !frameworkCompletionDelivered else {
                stateLock.unlock()
                return
            }
            frameworkCompletionDelivered = true
            let task = strongTask
            stateLock.unlock()

            guard let task else { return }
            task.setTaskCompleted(success: success)
            // BGTask clears this itself after the callback, but clearing it is
            // also required to break the task/handler/box retention chain.
            task.expirationHandler = nil

            stateLock.lock()
            strongTask = nil
            stateLock.unlock()
        }

        private static func foundationProgress(
            for progress: ContinuedProcessingProgress,
            request: ContinuedProcessingRequest
        ) -> (total: Int64, completed: Int64) {
            let unitCount: Int64 = 1_000_000
            switch request.goal {
            case .finiteDistance(let goal):
                // Divide before multiplying: the validated Double range may
                // be large enough that distance * 1,000,000 would overflow.
                let ratio = progress.cumulativeAcknowledgedDistanceMeters / goal
                if ratio >= 1 {
                    return (unitCount, unitCount)
                }
                let boundedRatio = max(0, ratio)
                let units = min(
                    Int64(boundedRatio * Double(unitCount)),
                    unitCount - 1
                )
                return (unitCount, units)
            case .experimentalIndeterminate:
                // An unlimited candidate remains Foundation-indeterminate:
                // completed units are actual acknowledged writes and total is
                // never rewritten into a growing or finite value.
                return (-1, progress.acknowledgedWrites)
            }
        }
    }
}
