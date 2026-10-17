import Combine
import Foundation

/// App lifecycle boundary for real user consent, accepted movement, and system runtime.
@MainActor
public final class MovementContinuationController: ObservableObject {
    public var state: ContinuedProcessingState { runtime?.state ?? .idle }
    @Published public private(set) var noticeKey: String?
    @Published public private(set) var receipts: [ContinuedProcessingReceipt] = []

    private struct Epoch {
        let demand: MovementContinuationDemand
        let origin: Double
        var lastSequence: UInt64?
        var count: Int64 = 0
        var distance: Double = 0

        func matches(_ id: UUID, _ lease: MovementTaskLease) -> Bool {
            demand.movementID == id && demand.lease == lease
        }
        mutating func acknowledge(_ ack: MovementAcknowledgement) -> Bool {
            guard matches(ack.movementID, ack.lease) else { return true }
            if let lastSequence, ack.sequence <= lastSequence { return true }
            guard count < Int64.max else { return false }
            let next: Double
            if demand.kind == .finiteRoute {
                guard let position = ack.routePositionMeters, position.isFinite else { return false }
                next = abs(position - origin)
            } else { next = distance + ack.acknowledgedDistanceMeters }
            guard next.isFinite, next >= 0 else { return false }
            count += 1; distance = next; lastSequence = ack.sequence
            return true
        }
        var progress: ContinuedProcessingProgress? {
            ContinuedProcessingProgress(acknowledgedWrites: count, cumulativeAcknowledgedDistanceMeters: distance)
        }
    }
    private struct Candidate {
        let request: ContinuedProcessingRequest
        var epoch: Epoch
        var boundGrant: ContinuedProcessingGrant?
    }
    private let service: ServiceController
    private let route: RouteExecutionController
    private let joystick: JoystickMovementController
    private let recovery: MovementRecoveryController
    private let presentation: @MainActor @Sendable (ContinuedProcessingKind, ContinuedProcessingProgress) -> (title: String, subtitle: String)
    private var runtime: ContinuedProcessingController!
    private var subscriptions: [AnyCancellable] = []
    private var sceneActive = false
    private var pending: Epoch?
    private var candidate: Candidate?
    // Retain the physical submission until even an uncooperative callee returns.
    private var submitTask: Task<Void, Never>?
    private var submissionID: UUID?
    private var lastAcknowledgement: MovementAcknowledgement?
    private var cleanupQueued = false
    private var handlingRuntimeLoss = false

    public init(service: ServiceController, route: RouteExecutionController,
                joystick: JoystickMovementController, recovery: MovementRecoveryController,
                driver: any ContinuedProcessingDriving,
                presentation: @escaping @MainActor @Sendable (ContinuedProcessingKind, ContinuedProcessingProgress) -> (title: String, subtitle: String)) {
        self.service = service; self.route = route; self.joystick = joystick
        self.recovery = recovery; self.presentation = presentation
        runtime = ContinuedProcessingController(driver: driver,
            onRuntimeAvailable: { [weak self] in self?.launched($0) },
            onRuntimeUnavailable: { [weak self] in self?.lostRuntime($0, $1) })
        service.setMovementSceneActive(false)
        recovery.releaseForInactiveScene()
        installSubscriptions()
        // Configuration readiness, never SDK submission. Report this failure
        // once; routine UI relays must not resurrect a user-cleared notice.
        if !runtime.register() { noticeKey = failureNotice(runtime.error) }
        synchronize()
    }
    public var hasRuntime: Bool {
        guard let candidate, runtime.hasRuntime else { return false }
        return service.hasMovementContinuation(movementID: candidate.request.movementID,
            lease: candidate.request.lease, requestID: candidate.request.requestID)
    }
    public func sceneDidBecomeActive() {
        guard !sceneActive else { return }
        if let candidate, let grant = candidate.boundGrant, !grant.isValid {
            pauseForRuntimeLoss(candidate, notice: "background.expired")
        }
        sceneActive = true
        service.setMovementSceneActive(true)
        recovery.sceneDidBecomeActive()
        synchronize()
    }
    public func releaseForInactiveScene() {
        sceneActive = false
        service.setMovementSceneActive(false) // Fence before invoking any callbacks.
        let ungrantedCandidate = candidate
        let hadDemand = candidate != nil || pending != nil
        pending = nil
        let lease = hasRuntime && candidate.map({ ownerReady($0.epoch.demand) }) == true
            ? candidate?.request.lease : nil
        if lease == nil, let current = ungrantedCandidate {
            pauseForRuntimeLoss(current, notice: "background.unavailable")
        }
        recovery.releaseForInactiveScene(continuingLease: lease)
        if lease == nil { retireCurrent(reason: .ownerPausedOrEnded) }
        if lease == nil, hadDemand { noticeKey = "background.unavailable" }
        synchronize()
    }
    public func refreshPresentation() { forwardProgress(); synchronize() }

    private func installSubscriptions() {
        subscriptions = [
            route.continuationControlEvents.sink { [weak self] in self?.control($0) },
            joystick.continuationControlEvents.sink { [weak self] in self?.control($0) },
            route.movementAcknowledgements.sink { [weak self] in self?.acknowledged($0) },
            service.movementAcknowledgements.sink { [weak self] in self?.acknowledged($0) },
            service.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            route.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            joystick.objectWillChange.sink { [weak self] _ in self?.observeDomainMutation() },
            runtime.objectWillChange.sink { [weak self] _ in self?.queueCleanup() },
            service.joystickEvents.sink { [weak self] event in
                guard case .movementBoundary(let lease) = event else { return }
                self?.movementBoundary(lease)
            }
        ]
    }
    private func control(_ event: MovementContinuationControlEvent) {
        switch event {
        case .requested(let demand): requested(demand)
        case .withdrawn(let identity, let reason):
            if pending?.matches(identity.movementID, identity.lease) == true { pending = nil }
            if let current = candidate, current.epoch.matches(identity.movementID, identity.lease) {
                let retirement: MovementContinuationRetirement
                if case .automaticDisabled(manualInputContinues: true) = reason {
                    retirement = .foregroundManualAfterAutoOff
                } else { retirement = .ownerPausedOrEnded }
                retireCurrent(reason: retirement)
            }
            if !handlingRuntimeLoss {
                switch reason {
                case .userPaused, .userCancelled, .automaticDisabled: noticeKey = nil
                case .ended: break
                }
            }
            synchronize()
        }
    }
    private func requested(_ demand: MovementContinuationDemand) {
        guard sceneActive else { return }
        if let current = candidate, current.epoch.matches(demand.movementID, demand.lease) {
            let stillBound = service.movementContinuationIsBound(
                requestID: current.request.requestID, lease: current.request.lease)
            if stillBound && current.boundGrant?.isValid != true {
                pending = nil; pauseForRuntimeLoss(current, notice: "background.expired"); return
            }
            if current.request.kind == demand.kind, current.request.goal == demand.goal,
               [.submitting, .accepted, .running].contains(runtime.state),
               current.boundGrant == nil || stillBound { return }
            // Successful explicit Resume has already retired its old binding.
            // A goal edit may retire only a still-valid concrete binding.
            if stillBound && !service.retireMovementContinuation(
                requestID: current.request.requestID, lease: current.request.lease,
                reason: .foregroundGoalChange) {
                pending = nil; pauseForRuntimeLoss(current, notice: "background.unavailable"); return
            }
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        let last = lastAcknowledgement.flatMap {
            $0.movementID == demand.movementID && $0.lease == demand.lease ? $0.sequence : nil
        }
        pending = Epoch(demand: demand, origin: route.progress?.committedDistanceMeters ?? 0, lastSequence: last)
        if demand.goal == nil { pending = nil; synchronize(); return }
        drainPending()
    }
    private func acknowledged(_ ack: MovementAcknowledgement) {
        guard service.movementAuthority.snapshot.lease == ack.lease else { return }
        if let last = lastAcknowledgement, last.movementID == ack.movementID,
           last.lease == ack.lease, ack.sequence <= last.sequence { return }
        guard ack.acknowledgedDistanceMeters.isFinite, ack.acknowledgedDistanceMeters >= 0 else {
            rejectInvalidProgress(); return
        }
        lastAcknowledgement = ack
        if let current = candidate, !current.epoch.matches(ack.movementID, ack.lease) {
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        if var epoch = pending, epoch.matches(ack.movementID, ack.lease) {
            guard epoch.acknowledge(ack) else { rejectInvalidProgress(); return }
            pending = epoch
        }
        if var current = candidate, current.epoch.matches(ack.movementID, ack.lease),
           current.boundGrant?.isValid != false {
            guard current.epoch.acknowledge(ack) else { rejectInvalidProgress(); return }
            candidate = current
            forwardProgress()
            if ack.finiteArrival, current.request.kind == .finiteRoute,
               case .finiteDistance(let goal) = current.request.goal,
               current.epoch.distance == goal,
               runtime.finishFiniteArrival(requestID: current.request.requestID) { candidate = nil }
        }
        drainPending(); synchronize()
    }
    private func drainPending() {
        guard sceneActive, submitTask == nil, let epoch = pending,
              epoch.demand.goal != nil, ownerReady(epoch.demand) else { return }
        if let current = candidate {
            // A pending prepare cannot replace the healthy previous owner.
            guard service.movementAuthority.snapshot.lease != current.request.lease else { return }
            retireCurrent(reason: .ownerPausedOrEnded)
        }
        guard let goal = epoch.demand.goal else { return }
        let text = presentation(epoch.demand.kind, epoch.progress ?? .zero)
        guard let request = ContinuedProcessingRequest(movementID: epoch.demand.movementID,
            lease: epoch.demand.lease, kind: epoch.demand.kind, goal: goal,
            title: text.title, subtitle: text.subtitle) else {
            pending = nil; noticeKey = "background.rejected"; return
        }
        pending = nil; candidate = Candidate(request: request, epoch: epoch)
        submissionID = request.requestID
        let id = request.requestID
        submitTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.sceneActive, self.candidate?.request.requestID == id,
                  self.ownerReady(epoch.demand) else {
                self.submissionReturned(id, accepted: false); return
            }
            let accepted = await self.runtime.begin(request, isForeground: true)
            self.submissionReturned(id, accepted: accepted)
        }
    }
    private func submissionReturned(_ id: UUID, accepted: Bool) {
        guard submissionID == id else { return }
        submissionID = nil; submitTask = nil
        if candidate?.request.requestID == id {
            if accepted { forwardProgress() }
            else {
                if let current = candidate, current.boundGrant != nil {
                    pauseForRuntimeLoss(current, notice: failureNotice(runtime.error))
                }
                candidate = nil; noticeKey = failureNotice(runtime.error)
            }
        }
        drainPending(); synchronize()
    }
    private func launched(_ grant: ContinuedProcessingGrant) {
        guard var current = candidate, current.request.requestID == grant.requestID,
              current.epoch.matches(grant.movementID, grant.lease), ownerReady(current.epoch.demand),
              service.bindMovementContinuation(grant) else {
            runtime.cancel(requestID: grant.requestID)
            noticeKey = "background.unavailable"; synchronize(); return
        }
        current.boundGrant = grant; candidate = current
        forwardProgress()
        if !grant.isValid { pauseForRuntimeLoss(current, notice: "background.expired") }
        synchronize()
    }
    private func lostRuntime(_ id: UUID, _ reason: ContinuedProcessingRuntimeLoss) {
        guard let current = candidate, current.request.requestID == id else { return }
        guard reason != .cancelled, reason != .superseded else { synchronize(); return }
        let key = reason == .expired ? "background.expired" :
            (reason == .submissionRejected ? failureNotice(runtime.error) : "background.unavailable")
        if current.boundGrant != nil || !sceneActive { pauseForRuntimeLoss(current, notice: key) }
        else { noticeKey = key } // Rejection without a bound grant preserves foreground work.
        synchronize()
    }
    private func pauseForRuntimeLoss(_ current: Candidate, notice: String) {
        noticeKey = notice; handlingRuntimeLoss = true
        if route.intent?.id == current.request.movementID, route.intent?.lease == current.request.lease {
            route.continuationDidBecomeUnavailable()
        } else if joystick.intent?.id == current.request.movementID, joystick.intent?.lease == current.request.lease {
            joystick.continuationDidBecomeUnavailable()
        }
        handlingRuntimeLoss = false; noticeKey = notice
    }
    private func retireCurrent(reason: MovementContinuationRetirement) {
        guard let current = candidate else { return }
        candidate = nil // Retire identity before potentially reentrant driver callbacks.
        _ = service.retireMovementContinuation(requestID: current.request.requestID,
            lease: current.request.lease, reason: reason)
        if submissionID == current.request.requestID { submitTask?.cancel() }
        _ = runtime.cancel(requestID: current.request.requestID)
    }
    private func movementBoundary(_ lease: MovementTaskLease?) {
        if lease == nil { pending = nil; noticeKey = nil }
        if let current = candidate, lease != current.request.lease { retireCurrent(reason: .ownerPausedOrEnded) }
        synchronize()
    }
    private func ownerReady(_ demand: MovementContinuationDemand) -> Bool {
        let owner = service.movementAuthority.snapshot
        guard owner.lease == demand.lease, owner.health == .confirmedHealthy,
              owner.runState == .running, service.movementConnectionAvailable,
              !service.coldRecoveryHeld else { return false }
        switch demand.kind {
        case .finiteRoute, .roundTrip:
            return route.phase == .running && route.intent?.id == demand.movementID && route.intent?.lease == demand.lease
        case .wander:
            // Service emits its first accepted ACK before the controller's
            // async return; the installed healthy owner is already real.
            return [.preparing, .moving].contains(joystick.phase) && joystick.wanderEnabled &&
                joystick.intent?.id == demand.movementID && joystick.intent?.lease == demand.lease
        }
    }
    private func forwardProgress() {
        guard let current = candidate, let progress = current.epoch.progress else { return }
        let text = presentation(current.request.kind, progress)
        _ = runtime.update(requestID: current.request.requestID, progress: progress,
            title: text.title, subtitle: text.subtitle)
    }
    private func queueCleanup() {
        guard !cleanupQueued else { return }
        cleanupQueued = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.cleanupQueued = false
            if let current = self.candidate {
                let owner = self.service.movementAuthority.snapshot
                if owner.lease != current.request.lease || owner.health != .confirmedHealthy || owner.runState != .running {
                    self.retireCurrent(reason: .ownerPausedOrEnded)
                }
            }
            if let epoch = self.pending {
                let id = epoch.demand.movementID
                if self.route.intent?.id != id && self.joystick.intent?.id != id { self.pending = nil }
            }
            // The one coalesced relay also publishes a suspended submission's
            // state and buffers real ACK progress before its launch/return.
            // It never creates consent, grants admission, or submits work.
            self.forwardProgress()
            self.synchronize()
        }
    }
    private func observeDomainMutation() {
        if !handlingRuntimeLoss, let current = candidate,
           current.boundGrant?.isValid == false,
           service.movementContinuationIsBound(requestID: current.request.requestID,
               lease: current.request.lease),
           service.movementAuthority.snapshot.health == .confirmedHealthy {
            pending = nil
            pauseForRuntimeLoss(current, notice: "background.expired")
        }
        queueCleanup()
    }
    private func rejectInvalidProgress() {
        pending = nil
        if let current = candidate { pauseForRuntimeLoss(current, notice: "background.rejected") }
        retireCurrent(reason: .ownerPausedOrEnded)
        noticeKey = "background.rejected"; synchronize()
    }
    private func failureNotice(_ failure: ContinuedProcessingFailure?) -> String {
        switch failure {
        case .registrationLimitReached: "background.registrationLimit"
        case .unsupportedSystem: "background.unsupported"
        default: "background.rejected"
        }
    }
    private func synchronize() {
        receipts = runtime.receipts
    }
}
