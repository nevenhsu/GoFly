import Foundation
import Testing
import GoFlyCore

@MainActor
private final class ControlledContinuedProcessingDriver: ContinuedProcessingDriving {
    var registerResult = true
    var registerCalls = 0
    var submitFailure: ContinuedProcessingFailure?
    var submitLaunchBeforeFailure: ContinuedProcessingGrant?
    var holdSubmit = false
    var eventHandler: (@MainActor @Sendable (ContinuedProcessingEvent) -> Void)?
    var eventHandlers: [(@MainActor @Sendable (ContinuedProcessingEvent) -> Void)] = []
    var completion: ContinuedProcessingTaskCompletion?
    var forcedFinishOutcome: ContinuedProcessingCompletionOutcome?
    var submittedRequest: ContinuedProcessingRequest?
    var updates: [(UUID, ContinuedProcessingProgress, String, String)] = []
    var cancelIDs: [UUID] = []
    var finishResults: [ContinuedProcessingCompletionOutcome] = []
    private var submitContinuation: CheckedContinuation<Void, Error>?
    private var ownedRequestID: UUID?
    private var ownedGrant: ContinuedProcessingGrant?

    func register() -> Bool {
        registerCalls += 1
        return registerResult
    }

    func submit(_ request: ContinuedProcessingRequest,
                onEvent: @escaping @MainActor @Sendable (ContinuedProcessingEvent) -> Void) async throws {
        submittedRequest = request
        eventHandler = onEvent
        eventHandlers.append(onEvent)
        if holdSubmit {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                submitContinuation = continuation
            }
        }
        if let submitLaunchBeforeFailure {
            launch(submitLaunchBeforeFailure)
        }
        if let submitFailure { throw submitFailure }
    }

    func update(requestID: UUID, progress: ContinuedProcessingProgress, title: String, subtitle: String) {
        updates.append((requestID, progress, title, subtitle))
    }

    func finish(requestID: UUID, success: Bool) -> ContinuedProcessingCompletionOutcome? {
        guard ownedRequestID == requestID else { return nil }
        guard let completion else { return nil }
        let claim = completion.claim(forcedFinishOutcome ?? (success ? .success : .cancelled))
        finishResults.append(claim.outcome)
        return claim.outcome
    }

    func cancel(requestID: UUID) {
        cancelIDs.append(requestID)
        guard ownedRequestID == requestID, let completion else { return }
        let claim = completion.claim(.cancelled)
        finishResults.append(claim.outcome)
        ownedRequestID = nil
        ownedGrant = nil
        self.completion = nil
    }

    func releaseSubmit() {
        submitContinuation?.resume(returning: ())
        submitContinuation = nil
    }

    func launch(_ grant: ContinuedProcessingGrant) {
        _ = installOwned(grant)
        eventHandler?(.launched(grant))
    }

    private func installOwned(_ grant: ContinuedProcessingGrant) -> Bool {
        guard let submittedRequest,
              grant.requestID == submittedRequest.requestID,
              grant.movementID == submittedRequest.movementID,
              grant.lease == submittedRequest.lease,
              grant.isValid else { return false }
        if let ownedGrant {
            return ownedGrant === grant
        }
        ownedRequestID = submittedRequest.requestID
        ownedGrant = grant
        completion = ContinuedProcessingTaskCompletion(grant: grant)
        return true
    }

    func sealExpiryWithoutEvent() {
        _ = completion?.claim(.expired)
    }

    func emitExpiry(for requestID: UUID) {
        eventHandler?(.expired(requestID: requestID))
    }

    func emitInvalidation(for requestID: UUID) {
        eventHandler?(.invalidated(requestID: requestID))
    }
}

@MainActor
private final class RuntimeLossRecorder {
    var losses: [ContinuedProcessingRuntimeLoss] = []
}

@Suite @MainActor
struct ContinuedProcessingTests {
    private func request(kind: ContinuedProcessingKind = .finiteRoute,
                         goal: ContinuedProcessingGoal = .finiteDistance(meters: 10),
                         title: String = "Moving") -> ContinuedProcessingRequest {
        ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(), kind: kind,
                                   goal: goal, title: title, subtitle: "Acknowledged work")!
    }

    @Test func publicValuesRejectInvalidGoalsProgressAndPresentation() {
        #expect(ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
                                           kind: .finiteRoute, goal: .experimentalIndeterminate,
                                           title: "Moving", subtitle: "Work") == nil)
        #expect(ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
                                           kind: .roundTrip, goal: .finiteDistance(meters: 2),
                                           title: "Moving", subtitle: "Work") == nil)
        #expect(ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
                                           kind: .finiteRoute, goal: .finiteDistance(meters: 0),
                                           title: "Moving", subtitle: "Work") == nil)
        #expect(ContinuedProcessingProgress(acknowledgedWrites: -1,
                                            cumulativeAcknowledgedDistanceMeters: 0) == nil)
        #expect(ContinuedProcessingProgress(acknowledgedWrites: 1,
                                            cumulativeAcknowledgedDistanceMeters: .infinity) == nil)
        #expect(ContinuedProcessingRequest(movementID: UUID(), lease: MovementTaskLease(),
                                           kind: .finiteRoute, goal: .finiteDistance(meters: 2),
                                           title: "\0", subtitle: "Work") == nil)
    }

    @Test func completionClaimIsAtomicAndRetainsTheFirstEffectiveOutcome() {
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: MovementTaskLease())
        let completion = ContinuedProcessingTaskCompletion(grant: grant)
        let first = completion.claim(.success)
        let late = completion.claim(.expired)
        #expect(first.outcome == .success)
        #expect(first.isFirst)
        #expect(!late.isFirst)
        #expect(late.outcome == .success)
        #expect(!grant.isValid)

        let invalidGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: MovementTaskLease())
        invalidGrant.revoke()
        let invalidated = ContinuedProcessingTaskCompletion(grant: invalidGrant).claim(.success)
        #expect(invalidated.outcome == .invalidated)
        #expect(invalidated.isFirst)
    }

    @Test func concurrentCompletionClaimsHaveOneFirstWinner() async {
        let grant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: MovementTaskLease())
        let completion = ContinuedProcessingTaskCompletion(grant: grant)
        let claims = await withTaskGroup(of: ContinuedProcessingCompletionClaim.self,
                                         returning: [ContinuedProcessingCompletionClaim].self) { group in
            for proposed in [ContinuedProcessingCompletionOutcome.success, .expired, .cancelled, .failed] {
                group.addTask { completion.claim(proposed) }
            }
            var results: [ContinuedProcessingCompletionClaim] = []
            for await claim in group { results.append(claim) }
            return results
        }
        #expect(claims.filter(\.isFirst).count == 1)
        #expect(Set(claims.map(\.outcome)).count == 1)
        #expect(!grant.isValid)
    }

    @Test func expirySealsBeforeDelayedEventAndFiniteArrivalReturnsExpiredOnce() async {
        let driver = ControlledContinuedProcessingDriver()
        let recorder = RuntimeLossRecorder()
        let controller = ContinuedProcessingController(driver: driver,
            onRuntimeUnavailable: { recorder.losses.append($1) })
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        let grant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(grant)
        let complete = ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                   cumulativeAcknowledgedDistanceMeters: 10)!
        #expect(controller.update(requestID: current.requestID, progress: complete,
                                  title: current.title, subtitle: current.subtitle))
        driver.sealExpiryWithoutEvent()
        #expect(!controller.finishFiniteArrival(requestID: current.requestID))
        #expect(controller.state == .expired)
        #expect(controller.completionOutcome == .expired)
        #expect(recorder.losses.count == 1)
        driver.emitExpiry(for: current.requestID)
        driver.emitExpiry(for: current.requestID)
        #expect(recorder.losses.count == 1)
        #expect(driver.finishResults == [.expired])
    }

    @Test func successfulFiniteArrivalWinsAndLateExpiryIsSilent() async {
        let driver = ControlledContinuedProcessingDriver()
        let recorder = RuntimeLossRecorder()
        let controller = ContinuedProcessingController(driver: driver,
            onRuntimeUnavailable: { recorder.losses.append($1) })
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        driver.launch(ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                               lease: current.lease))
        #expect(controller.update(requestID: current.requestID,
                                  progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                       cumulativeAcknowledgedDistanceMeters: 10)!,
                                  title: current.title, subtitle: current.subtitle))
        #expect(controller.finishFiniteArrival(requestID: current.requestID))
        #expect(controller.completionOutcome == .success)
        #expect(controller.state == .finished)
        driver.emitExpiry(for: current.requestID)
        #expect(recorder.losses.isEmpty)
        #expect(driver.finishResults == [.success])
    }

    @Test func equalProgressWithChangedPresentationIsForwardedOnce() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        let grant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(grant)
        #expect(controller.update(requestID: current.requestID, progress: .zero,
                                  title: "Localized", subtitle: "Updated"))
        #expect(driver.updates.count == 1)
        #expect(controller.update(requestID: current.requestID, progress: .zero,
                                  title: "Localized", subtitle: "Updated"))
        #expect(driver.updates.count == 1)
    }

    @Test func acceptedSubmissionRetainsNewestPrelaunchProgressUntilLaunch() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        #expect(controller.state == .accepted)
        #expect(!controller.hasRuntime)
        let retained = ContinuedProcessingProgress(acknowledgedWrites: 2,
                                                  cumulativeAcknowledgedDistanceMeters: 4)!
        #expect(controller.update(requestID: current.requestID, progress: retained,
                                  title: current.title, subtitle: current.subtitle))
        #expect(driver.updates.isEmpty)
        let grant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(grant)
        #expect(controller.state == .running)
        #expect(controller.hasRuntime)
        #expect(driver.updates.map { $0.1 } == [retained])
    }

    @Test func launchBeforeSubmitReturnsRemainsRunningAfterLateAcceptance() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        driver.holdSubmit = true
        let current = request()
        let pending = Task { await controller.begin(current, isForeground: true) }
        await Task.yield()
        #expect(driver.eventHandler != nil)
        driver.launch(ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                               lease: current.lease))
        #expect(controller.state == .running)
        #expect(controller.hasRuntime)
        driver.releaseSubmit()
        #expect(await pending.value)
        #expect(controller.state == .running)
        #expect(controller.hasRuntime)
    }

    @Test func rejectedAfterLaunchClosesGrantAndCancelsOwnedWork() async {
        let driver = ControlledContinuedProcessingDriver()
        let recorder = RuntimeLossRecorder()
        let controller = ContinuedProcessingController(driver: driver,
            onRuntimeUnavailable: { recorder.losses.append($1) })
        #expect(controller.register())
        let current = request()
        let launchedGrant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                                     lease: current.lease)
        driver.submitLaunchBeforeFailure = launchedGrant
        driver.submitFailure = .submissionRejected
        #expect(!(await controller.begin(current, isForeground: true)))
        #expect(controller.state == .rejected)
        #expect(controller.error == .submissionRejected)
        #expect(!launchedGrant.isValid)
        #expect(driver.cancelIDs == [current.requestID])
        #expect(recorder.losses == [.submissionRejected])
    }

    @Test func cancellingPendingSubmitRetiresOnlyItsGenerationBeforeReplacement() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        driver.holdSubmit = true
        let first = request()
        let firstTask = Task { await controller.begin(first, isForeground: true) }
        await Task.yield()
        let oldGrant = ContinuedProcessingGrant(requestID: first.requestID, movementID: first.movementID,
                                                lease: first.lease)
        driver.launch(oldGrant)
        let oldHandler = driver.eventHandler
        firstTask.cancel()
        for _ in 0..<20 {
            await Task.yield()
            if !oldGrant.isValid { break }
        }
        #expect(!oldGrant.isValid)

        driver.holdSubmit = false
        let replacement = request()
        #expect(await controller.begin(replacement, isForeground: true))
        let replacementGrant = ContinuedProcessingGrant(requestID: replacement.requestID,
                                                         movementID: replacement.movementID,
                                                         lease: replacement.lease)
        driver.launch(replacementGrant)
        driver.cancel(requestID: first.requestID)
        #expect(replacementGrant.isValid)
        oldHandler?(.launched(oldGrant))
        #expect(replacementGrant.isValid)
        oldHandler?(.launched(replacementGrant))
        #expect(replacementGrant.isValid)
        driver.releaseSubmit()
        #expect(!(await firstTask.value))
        #expect(controller.currentRequest == replacement)
        #expect(driver.cancelIDs == [first.requestID, first.requestID])
        #expect(controller.update(requestID: replacement.requestID,
                                  progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                       cumulativeAcknowledgedDistanceMeters: 10)!,
                                  title: replacement.title, subtitle: replacement.subtitle))
        #expect(controller.finishFiniteArrival(requestID: replacement.requestID))
        #expect(controller.completionOutcome == .success)
        #expect(!replacementGrant.isValid)
    }

    @Test func launchRequiresAllIdentitiesAndPreservesCurrentGrantOnDuplicates() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))

        let wrongRequest = ContinuedProcessingGrant(requestID: UUID(), movementID: current.movementID,
                                                    lease: current.lease)
        driver.launch(wrongRequest)
        #expect(!wrongRequest.isValid)
        #expect(controller.state == .accepted)
        let wrongMovement = ContinuedProcessingGrant(requestID: current.requestID, movementID: UUID(),
                                                     lease: current.lease)
        driver.launch(wrongMovement)
        #expect(!wrongMovement.isValid)
        let wrongLease = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                                  lease: MovementTaskLease())
        driver.launch(wrongLease)
        #expect(!wrongLease.isValid)
        #expect(controller.state == .accepted)

        let valid = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(valid)
        #expect(controller.hasRuntime)
        let launchedReceipts = controller.receipts.filter { $0.event == .launched }.count
        driver.launch(valid)
        #expect(valid.isValid)
        #expect(controller.receipts.filter { $0.event == .launched }.count == launchedReceipts)

        let extra = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(extra)
        #expect(!extra.isValid)
        #expect(valid.isValid)
        #expect(controller.hasRuntime)
        #expect(driver.finish(requestID: UUID(), success: true) == nil)
        driver.cancel(requestID: UUID())
        #expect(valid.isValid)

        #expect(controller.update(requestID: current.requestID,
                                  progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                       cumulativeAcknowledgedDistanceMeters: 10)!,
                                  title: current.title, subtitle: current.subtitle))
        #expect(controller.finishFiniteArrival(requestID: current.requestID))
        #expect(controller.completionOutcome == .success)
        #expect(!valid.isValid)
        #expect(!extra.isValid)

        let closedControllerDriver = ControlledContinuedProcessingDriver()
        let closedController = ContinuedProcessingController(driver: closedControllerDriver)
        #expect(closedController.register())
        let closedRequest = request()
        #expect(await closedController.begin(closedRequest, isForeground: true))
        let closedGrant = ContinuedProcessingGrant(requestID: closedRequest.requestID,
                                                    movementID: closedRequest.movementID,
                                                    lease: closedRequest.lease)
        closedGrant.revoke()
        closedControllerDriver.launch(closedGrant)
        #expect(closedController.state == .accepted)
        #expect(!closedController.hasRuntime)
    }

    @Test func progressRequiresCurrentIdentityMonotonicValuesAndFiniteGoalBounds() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let first = request()
        #expect(await controller.begin(first, isForeground: true))
        let valid = ContinuedProcessingProgress(acknowledgedWrites: 2,
                                                cumulativeAcknowledgedDistanceMeters: 4)!
        #expect(controller.update(requestID: first.requestID, progress: valid,
                                  title: first.title, subtitle: first.subtitle))
        #expect(!controller.update(requestID: first.requestID,
                                   progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                        cumulativeAcknowledgedDistanceMeters: 4)!,
                                   title: first.title, subtitle: first.subtitle))
        #expect(!controller.update(requestID: first.requestID,
                                   progress: ContinuedProcessingProgress(acknowledgedWrites: 2,
                                                                        cumulativeAcknowledgedDistanceMeters: 3)!,
                                   title: first.title, subtitle: first.subtitle))
        #expect(!controller.update(requestID: first.requestID,
                                   progress: ContinuedProcessingProgress(acknowledgedWrites: 3,
                                                                        cumulativeAcknowledgedDistanceMeters: 11)!,
                                   title: first.title, subtitle: first.subtitle))
        #expect(!controller.update(requestID: UUID(), progress: valid,
                                   title: first.title, subtitle: first.subtitle))
        #expect(!controller.update(requestID: first.requestID, progress: valid,
                                   title: String(repeating: "x", count: 129), subtitle: first.subtitle))
        #expect(controller.progress == valid)

        let replacement = request()
        #expect(await controller.begin(replacement, isForeground: true))
        #expect(!controller.update(requestID: first.requestID, progress: valid,
                                   title: first.title, subtitle: first.subtitle))
        #expect(controller.update(requestID: replacement.requestID, progress: .zero,
                                  title: replacement.title, subtitle: replacement.subtitle))
    }

    @Test func pendingFiniteArrivalWithoutGrantCannotInventSuccess() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        let goal = ContinuedProcessingProgress(acknowledgedWrites: 1,
                                               cumulativeAcknowledgedDistanceMeters: 10)!
        #expect(controller.update(requestID: current.requestID, progress: goal,
                                  title: current.title, subtitle: current.subtitle))
        #expect(!controller.finishFiniteArrival(requestID: current.requestID))
        #expect(controller.state == .finished)
        #expect(controller.completionOutcome == nil)
        #expect(driver.finishResults.isEmpty)
        #expect(driver.cancelIDs == [current.requestID])
    }

    @Test func unlimitedModesRejectFiniteFinishWithoutRenewalOrSuccess() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        for kind in [ContinuedProcessingKind.roundTrip, .wander] {
            let current = request(kind: kind, goal: .experimentalIndeterminate)
            #expect(await controller.begin(current, isForeground: true))
            driver.finishResults.removeAll()
            let grant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                                 lease: current.lease)
            driver.launch(grant)
            #expect(controller.update(requestID: current.requestID,
                                      progress: ContinuedProcessingProgress(acknowledgedWrites: 3,
                                                                           cumulativeAcknowledgedDistanceMeters: 30)!,
                                      title: current.title, subtitle: current.subtitle))
            #expect(!controller.finishFiniteArrival(requestID: current.requestID))
            #expect(controller.state == .running)
            #expect(controller.completionOutcome == nil)
            #expect(driver.finishResults.isEmpty)
        }
    }

    @Test func registrationIsIdempotentAndForegroundRejectionPreservesCurrentWork() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        let first = request()
        #expect(!(await controller.begin(first, isForeground: true)))
        #expect(controller.state == .rejected)
        #expect(controller.error == .registrationFailed)
        #expect(controller.currentRequest == nil)

        #expect(controller.register())
        #expect(controller.register())
        #expect(driver.registerCalls == 1)
        #expect(await controller.begin(first, isForeground: true))
        let second = request()
        #expect(!(await controller.begin(second, isForeground: false)))
        #expect(controller.currentRequest == first)
        #expect(controller.state == .accepted)
        #expect(driver.cancelIDs.isEmpty)
    }

    @Test func receiptsRemainBoundedTo256OldestFirstAcrossProgressUpdates() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request(goal: .finiteDistance(meters: 1_000))
        #expect(await controller.begin(current, isForeground: true))
        driver.launch(ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                               lease: current.lease))
        for index in 1...300 {
            let progress = ContinuedProcessingProgress(acknowledgedWrites: Int64(index),
                                                       cumulativeAcknowledgedDistanceMeters: Double(index))!
            #expect(controller.update(requestID: current.requestID, progress: progress,
                                      title: current.title, subtitle: current.subtitle))
        }
        #expect(controller.receipts.count == 256)
        #expect(controller.receipts.allSatisfy { $0.requestID == current.requestID })
        #expect(controller.receipts.last?.event == .progressUpdated)
        #expect(controller.progress.acknowledgedWrites == 300)
    }

    @Test func closedRunningGrantRejectsBeforeProgressOrReceiptMutation() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        let grant = ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                             lease: current.lease)
        driver.launch(grant)
        grant.revoke()
        #expect(!controller.update(requestID: current.requestID,
                                   progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                        cumulativeAcknowledgedDistanceMeters: 1)!,
                                   title: "Changed", subtitle: "Changed"))
        #expect(controller.progress == .zero)
        #expect(driver.updates.isEmpty)
        #expect(!controller.receipts.contains { $0.event == .progressUpdated })
    }

    @Test func delayedSubmitResultCannotOverwriteExpiryOrInvalidation() async {
        let driver = ControlledContinuedProcessingDriver()
        let controller = ContinuedProcessingController(driver: driver)
        #expect(controller.register())
        driver.holdSubmit = true
        let current = request()
        let pending = Task { await controller.begin(current, isForeground: true) }
        await Task.yield()
        driver.emitExpiry(for: current.requestID)
        driver.releaseSubmit()
        #expect(!(await pending.value))
        #expect(controller.state == .expired)
        #expect(controller.error == nil)

        let secondDriver = ControlledContinuedProcessingDriver()
        let secondController = ContinuedProcessingController(driver: secondDriver)
        #expect(secondController.register())
        secondDriver.holdSubmit = true
        let second = request()
        let secondPending = Task { await secondController.begin(second, isForeground: true) }
        await Task.yield()
        secondDriver.emitInvalidation(for: second.requestID)
        secondDriver.releaseSubmit()
        #expect(!(await secondPending.value))
        #expect(secondController.state == .finished)
        #expect(secondController.error == nil)
    }

    @Test func failedFinishPublishesUnsuccessfulInvalidatedRuntimeLoss() async {
        let driver = ControlledContinuedProcessingDriver()
        let recorder = RuntimeLossRecorder()
        let controller = ContinuedProcessingController(driver: driver,
            onRuntimeUnavailable: { recorder.losses.append($1) })
        #expect(controller.register())
        let current = request()
        #expect(await controller.begin(current, isForeground: true))
        driver.launch(ContinuedProcessingGrant(requestID: current.requestID, movementID: current.movementID,
                                               lease: current.lease))
        #expect(controller.update(requestID: current.requestID,
                                  progress: ContinuedProcessingProgress(acknowledgedWrites: 1,
                                                                       cumulativeAcknowledgedDistanceMeters: 10)!,
                                  title: current.title, subtitle: current.subtitle))
        driver.forcedFinishOutcome = .failed
        #expect(!controller.finishFiniteArrival(requestID: current.requestID))
        #expect(controller.completionOutcome == ContinuedProcessingCompletionOutcome.failed)
        #expect(recorder.losses == [.invalidated])
    }

    @Test func invalidatedAndFailedClaimsStaySilentToLateExpiry() {
        let invalidated = ContinuedProcessingTaskCompletion(grant: nil)
        let firstInvalidated = invalidated.claim(.invalidated)
        let lateInvalidated = invalidated.claim(.expired)
        #expect(firstInvalidated.outcome == .invalidated)
        #expect(lateInvalidated.outcome == .invalidated)
        #expect(!lateInvalidated.isFirst)

        let failed = ContinuedProcessingTaskCompletion(grant: nil)
        let firstFailed = failed.claim(.failed)
        let lateFailed = failed.claim(.expired)
        #expect(firstFailed.outcome == .failed)
        #expect(lateFailed.outcome == .failed)
        #expect(!lateFailed.isFirst)

        let cancelledGrant = ContinuedProcessingGrant(requestID: UUID(), movementID: UUID(), lease: MovementTaskLease())
        let cancelled = ContinuedProcessingTaskCompletion(grant: cancelledGrant)
        let firstCancelled = cancelled.claim(.cancelled)
        let lateCancelled = cancelled.claim(.expired)
        #expect(firstCancelled.outcome == .cancelled)
        #expect(lateCancelled.outcome == .cancelled)
        #expect(!lateCancelled.isFirst)
        #expect(!cancelledGrant.isValid)
    }
}
