import Combine
import Foundation

public enum RouteSuspensionReason: String, Equatable, Sendable {
    case sceneInactive
    case connectionUnavailable
    case backgroundUnavailable
}

@MainActor
public final class RouteExecutionController: ObservableObject {
    @Published public private(set) var draft: RouteDraft
    @Published public private(set) var picker: RoutePickerSession? {
        didSet {
            pickerCandidateSubscription?.cancel()
            pickerCandidateSubscription = picker?.candidates.objectWillChange.sink { [weak self] in
                self?.objectWillChange.send()
            }
        }
    }
    @Published public private(set) var phase: RouteExecutionPhase = .editing
    @Published public private(set) var intent: RouteExecutionIntent?
    @Published public private(set) var plannedRoute: PlannedRoute?
    @Published public private(set) var progress: RouteProgress?
    @Published public private(set) var error: RouteExecutionFailure?
    @Published public private(set) var completion: RouteCompletion?
    @Published public private(set) var suspensionReason: RouteSuspensionReason?
    @Published public private(set) var roundTripEnabled = false
    @Published public private(set) var usesPositionAxis = false
    @Published public private(set) var heading: RouteHeading = .forward
    private let planner: any RoutePlanning
    private let commands: any RouteCommanding
    private let search: any PlaceSearching
    private let clock: any RouteClock
    public private(set) var favoriteLoadAdmissionRevision: UInt64 = 0
    private var issuedFavoriteLoadAdmission: UInt64?
    private var issuedImportedLoadAdmission: UInt64?
    private let transferOwnerID = UUID()
    private var transferHold: TransferHold?
    /// IDs represent route planner/native transitions that have actually
    /// entered their async body. Completed Task handles do not block a cutline.
    private var physicalOperations: Set<UUID> = []
    private var revision: UInt64 = 0
    private var task: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var pickerCandidateSubscription: AnyCancellable?
    private var accumulatedElapsed: Duration = .zero
    private var activeStartedAt: Duration?
    private var sceneActive = true
    private var connectionAvailable = true
    private var recoveryProbePending = false
    private var pendingSuspensionReason: RouteSuspensionReason?
    private let continuationControlSubject = PassthroughSubject<MovementContinuationControlEvent, Never>()
    private let movementAcknowledgementSubject = PassthroughSubject<MovementAcknowledgement, Never>()
    private var continuationIdentity: MovementContinuationIdentity?
    private static let cadence: Duration = .milliseconds(500)

    public var continuationControlEvents: AnyPublisher<MovementContinuationControlEvent, Never> {
        continuationControlSubject.eraseToAnyPublisher()
    }
    public var movementAcknowledgements: AnyPublisher<MovementAcknowledgement, Never> {
        movementAcknowledgementSubject.eraseToAnyPublisher()
    }

    public init(draft: RouteDraft = RouteDraft(), planner: any RoutePlanning, commands: any RouteCommanding,
                search: any PlaceSearching, clock: any RouteClock = ContinuousRouteClock()) {
        self.draft = draft; self.planner = planner; self.commands = commands; self.search = search; self.clock = clock
        if let source = draft.gpxSource {
            // A persisted GPX draft is display data. Build only its existing
            // exact preview; do not plan roads or touch the command seam.
            self.plannedRoute = try? PlannedRoute(imported: source.document)
        }
        subscription = commands.routeEvents.sink { [weak self] event in self?.receive(event) }
    }
    public var canEdit: Bool { phase == .editing && transferHold == nil }
    public var canStart: Bool { canEdit && sceneActive && connectionAvailable && commands.canBeginRoute && (try? resolvedDraft(draft)) != nil }
    public var canAddNode: Bool { canEdit && draft.isManual && draft.nodes.count < RouteDraft.maximumNodeCount }
    public var canClearImportedRoute: Bool { canEdit && draft.gpxSource != nil }
    private func beginPhysicalOperation() -> UUID {
        let id = UUID(); physicalOperations.insert(id); return id
    }
    private func finishPhysicalOperation(_ id: UUID) { physicalOperations.remove(id) }

    public func acquireTransferHold() -> TransferHold? {
        guard transferHold == nil, phase == .editing, picker == nil,
              intent == nil, continuationIdentity == nil, !recoveryProbePending,
              physicalOperations.isEmpty else { return nil }
        invalidateFavoriteLoadAdmission()
        let hold = TransferHold(ownerID: transferOwnerID, tokenID: UUID())
        transferHold = hold
        return hold
    }
    @discardableResult
    public func releaseTransferHold(_ token: TransferHold) -> Bool {
        guard transferHold == token, token.ownerID == transferOwnerID,
              physicalOperations.isEmpty, phase == .editing, picker == nil,
              intent == nil, continuationIdentity == nil else { return false }
        transferHold = nil
        return true
    }
    /// Capture before asynchronous archive validation; only this outstanding request may replace the draft.
    public func beginFavoriteLoad() -> UInt64? {
        guard canEdit, picker == nil else { return nil }
        invalidateFavoriteLoadAdmission()
        issuedFavoriteLoadAdmission = favoriteLoadAdmissionRevision
        return favoriteLoadAdmissionRevision
    }
    public func beginImportedLoad() -> UInt64? {
        guard canEdit, picker == nil else { return nil }
        invalidateFavoriteLoadAdmission()
        issuedImportedLoadAdmission = favoriteLoadAdmissionRevision
        return favoriteLoadAdmissionRevision
    }
    public func invalidateFavoriteLoadAdmission() {
        favoriteLoadAdmissionRevision &+= 1
        issuedFavoriteLoadAdmission = nil
        issuedImportedLoadAdmission = nil
    }
    @discardableResult public func loadFavoriteRoute(_ snapshot: FavoriteRouteSnapshot, expectedAdmissionRevision: UInt64) -> Bool {
        guard canEdit, picker == nil, issuedFavoriteLoadAdmission == expectedAdmissionRevision,
              favoriteLoadAdmissionRevision == expectedAdmissionRevision else { return false }
        let changed: RouteDraft
        var preview: PlannedRoute?
        switch snapshot.source {
        case .manual(let places):
            guard let manual = RouteDraft(values: places.map { .place($0) }, speed: draft.speed) else { return false }
            changed = manual
        case .gpx(let source):
            do { preview = try PlannedRoute(imported: source.document) }
            catch {
                self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? .invalidPath
                return false
            }
            changed = RouteDraft(gpx: source, speed: draft.speed)
        }
        applyDraft(changed)
        plannedRoute = preview
        return true
    }
    @discardableResult public func loadImportedRoute(_ snapshot: ImportedRouteSnapshot,
                                                     expectedAdmissionRevision: UInt64) -> Bool {
        guard canEdit, picker == nil,
              issuedImportedLoadAdmission == expectedAdmissionRevision,
              favoriteLoadAdmissionRevision == expectedAdmissionRevision else { return false }
        let preview: PlannedRoute
        do { preview = try PlannedRoute(imported: snapshot.document) }
        catch {
            self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? .invalidPath
            return false
        }
        applyDraft(RouteDraft(imported: snapshot, speed: draft.speed))
        plannedRoute = preview
        return true
    }
    @discardableResult public func clearImportedRoute() -> Bool {
        guard canClearImportedRoute else { return false }
        applyDraft(RouteDraft(speed: draft.speed))
        return true
    }
    public var canPause: Bool { transferHold == nil && phase == .running }
    public var canSetRoundTrip: Bool { transferHold == nil && [.editing, .running, .paused].contains(phase) }
    public var canToggleHeading: Bool {
        guard transferHold == nil, roundTripEnabled, phase == .running || phase == .paused, let intent, let progress else { return false }
        return heading == .forward ? progress.committedDistanceMeters > 0 : progress.committedDistanceMeters < intent.route.totalDistanceMeters
    }
    public var currentTargetCoordinate: GeoCoordinate? {
        guard let intent else { return nil }
        return heading == .forward ? intent.route.end : intent.route.start
    }
    @discardableResult public func setRoundTripEnabled(_ enabled: Bool) -> Bool {
        guard canSetRoundTrip else { return false }
        invalidateFavoriteLoadAdmission()
        roundTripEnabled = enabled
        if enabled, phase == .running || phase == .paused { usesPositionAxis = true }
        if phase == .running, let intent { requestContinuationIfEligible(for: intent) }
        return true
    }
    @discardableResult public func toggleHeading() -> Bool {
        guard canToggleHeading, let intent,
              commands.reviseRouteControl(executionID: intent.id, lease: intent.lease) != nil else { return false }
        heading = heading == .forward ? .reverse : .forward
        publishProgress(distance: progress?.committedDistanceMeters ?? 0, intent: intent)
        if phase == .running { requestContinuationIfEligible(for: intent) }
        return true
    }
    public var canResume: Bool {
        transferHold == nil && sceneActive && connectionAvailable && !recoveryProbePending && phase == .paused && commands.canBeginRoute
    }

    /// Recovery blocks a paused resume until its fresh probe settles without
    /// interrupting an already running route.
    func recoveryProbeDidStart() { recoveryProbePending = true; objectWillChange.send() }
    func recoveryProbeDidFinish() { recoveryProbePending = false; objectWillChange.send() }
    public var canCancel: Bool {
        transferHold == nil && [.planning, .preparing, .running, .pausing, .paused, .interrupted].contains(phase)
    }
    @discardableResult public func openPicker(for nodeID: RouteNodeID) -> Bool {
        guard canEdit, let node = draft.nodes.first(where: { $0.id == nodeID }) else { return false }
        invalidateFavoriteLoadAdmission()
        let candidates = CandidateController(search: search)
        if case .place(let place) = node.value { candidates.select(place) }
        picker = RoutePickerSession(id: UUID(), nodeID: nodeID, candidates: candidates,
            allowsCurrent: allowsCurrent(at: nodeID, isNew: false), initialValue: node.value,
            isNew: false, role: draft.role(of: nodeID)!)
        return true
    }
    @discardableResult public func openNewPicker() -> Bool {
        guard canAddNode else { return false }
        invalidateFavoriteLoadAdmission()
        let nodeID = RouteNodeID()
        picker = RoutePickerSession(id: UUID(), nodeID: nodeID, candidates: CandidateController(search: search),
            allowsCurrent: allowsCurrent(at: nodeID, isNew: true), initialValue: nil,
            isNew: true, role: newNodeRole)
        return true
    }
    @discardableResult public func clearPickerPlace(id: UUID) -> Bool {
        guard canEdit, var session = picker, session.id == id else { return false }
        invalidateFavoriteLoadAdmission()
        session.candidates.resetSelection()
        session.clearRevision = session.candidates.editingRevision
        picker = session
        return true
    }
    @discardableResult public func stagePickerCurrent(id: UUID) -> Bool {
        guard canEdit, let session = picker, session.id == id,
              allowsCurrent(at: session.nodeID, isNew: session.isNew) else { return false }
        invalidateFavoriteLoadAdmission()
        session.candidates.cancelPendingLookups()
        return true
    }
    @discardableResult public func removeNode(id: RouteNodeID) -> Bool {
        guard canEdit, let changed = draft.removing(nodeID: id) else { return false }
        applyDraft(changed)
        return true
    }
    @discardableResult public func moveNode(id: RouteNodeID, toIndex: Int) -> Bool {
        guard canEdit, let changed = draft.moving(nodeID: id, toIndex: toIndex) else { return false }
        applyDraft(changed)
        return true
    }
    @discardableResult public func confirmPicker(id: UUID, useCurrentLocation: Bool = false) -> Bool {
        guard canEdit, draft.isManual, let session = picker, session.id == id else { return false }
        guard session.isNew || draft.nodes.contains(where: { $0.id == session.nodeID }) else { return false }
        if !useCurrentLocation, session.clearedPlace {
            invalidateFavoriteLoadAdmission()
            if !session.isNew, !removeNode(id: session.nodeID) { return false }
            picker = nil
            return true
        }
        let value: RouteNodeValue
        if useCurrentLocation {
            guard allowsCurrent(at: session.nodeID, isNew: session.isNew) else { return false }
            value = .current
        } else {
            guard session.candidates.canGo, let place = session.candidates.candidate?.place else { return false }
            value = .place(place)
        }
        let changed = session.isNew ? draft.inserting(nodeID: session.nodeID, value: value) : draft.replacing(nodeID: session.nodeID, value: value)
        guard let changed else { return false }
        applyDraft(changed)
        picker = nil
        return true
    }
    public func cancelPicker(id: UUID) {
        guard picker?.id == id else { return }
        invalidateFavoriteLoadAdmission()
        picker = nil
    }
    private var newNodeRole: RouteNodeRole {
        if draft.nodes.isEmpty { return .start }
        return draft.nodes.count == 1 ? .destination : .waypoint(draft.nodes.count - 1)
    }
    private func allowsCurrent(at id: RouteNodeID, isNew: Bool) -> Bool {
        guard draft.isManual else { return false }
        let first = isNew ? draft.nodes.isEmpty : draft.start?.id == id
        return first && !draft.nodes.contains { $0.id != id && $0.value == .current }
    }
    private func applyDraft(_ changed: RouteDraft) {
        invalidateFavoriteLoadAdmission()
        draft = changed; plannedRoute = nil; completion = nil; error = nil
        guard draft.isManual else { picker = nil; return }
        if var session = picker {
            if session.isNew { session.role = newNodeRole }
            else if let role = draft.role(of: session.nodeID) { session.role = role }
            else { picker = nil; return }
            session.allowsCurrent = allowsCurrent(at: session.nodeID, isNew: session.isNew)
            picker = session
        }
    }
    @discardableResult public func setSpeed(_ speed: RouteSpeed) -> Bool {
        guard canEdit else { return false }
        invalidateFavoriteLoadAdmission()
        draft = draft.replacing(speed: speed)
        return true
    }
    @discardableResult public func start() -> Bool {
        guard canEdit, sceneActive else { return false }
        invalidateFavoriteLoadAdmission()
        guard commands.canBeginRoute else { return false }
        let snapshot: RouteDraft
        do { snapshot = try resolvedDraft(draft) }
        catch {
            self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? (error as? RouteExecutionFailure ?? .invalidPath)
            return false
        }
        let coordinates = snapshot.nodes.compactMap { node -> GeoCoordinate? in
            if case .place(let place) = node.value { return place.coordinate }; return nil
        }
        revision &+= 1
        let token = revision
        let admission = commands.routeAdmissionRevision
        phase = .planning; picker = nil; error = nil; completion = nil; progress = nil; intent = nil
        if snapshot.isManual { plannedRoute = nil }
        accumulatedElapsed = .zero; activeStartedAt = nil
        heading = .forward; usesPositionAxis = roundTripEnabled
        let planner = planner
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            do {
                let route: PlannedRoute
                if let imported = snapshot.gpxSource { route = try PlannedRoute(imported: imported.document) }
                else {
                    var legs: [PlannedRoute] = []
                    for index in 1..<coordinates.count {
                        let from = coordinates[index - 1], to = coordinates[index]
                        let points = try await planner.plan(from: from, to: to)
                        guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                        guard self.commands.routeAdmissionRevision == admission else { self.returnToEditing(); return }
                        legs.append(try PlannedRoute(points: points, from: from, to: to))
                    }
                    route = try PlannedRoute(legs: legs)
                }
                guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                guard self.commands.routeAdmissionRevision == admission else { self.returnToEditing(); return }
                let intent = RouteExecutionIntent(draft: snapshot, route: route)
                let continuationIdentity = MovementContinuationIdentity(movementID: intent.id, lease: intent.lease)
                self.plannedRoute = route; self.intent = intent; self.phase = .preparing
                self.requestContinuationIfEligible(for: intent)
                let outcome = await self.commands.beginRoute(intent, expectedAdmissionRevision: admission)
                guard self.revision == token, self.phase == .preparing else {
                    if self.continuationIdentity == continuationIdentity {
                        self.withdrawContinuation(.userCancelled)
                    }
                    return
                }
                switch outcome {
                case .acknowledged:
                    self.phase = .running; self.activeStartedAt = self.clock.now
                    self.publishProgress(distance: 0, intent: intent)
                    self.publishRouteAcknowledgement(sequence: 0, distance: 0, position: 0,
                        finiteArrival: false, intent: intent)
                    await self.run(intent, token: token)
                case .cancelled, .controlCancelled:
                    self.withdrawContinuation(.userCancelled)
                    self.returnToEditing()
                case .notSent(let failure):
                    self.withdrawContinuation(.ended)
                    self.phase = .interrupted; self.error = .device(failure)
                case .unconfirmed(let failure):
                    self.withdrawContinuation(.ended)
                    self.phase = .unknown; self.error = .device(failure)
                }
            } catch {
                guard let self, self.revision == token, self.phase == .planning else { return }
                self.withdrawContinuation(.ended)
                self.phase = .editing
                self.error = (error as? ImportedRouteExecutionFailure).map(RouteExecutionFailure.imported) ?? (error as? RouteExecutionFailure ?? .planningFailed)
            }
        }
        return true
    }
    private func resolvedDraft(_ source: RouteDraft) throws -> RouteDraft {
        if let imported = source.gpxSource { _ = try PlannedRoute(imported: imported.document); return source }
        guard !source.nodes.isEmpty else { throw RouteExecutionFailure.missingStart }
        guard source.nodes.count >= 2 else { throw RouteExecutionFailure.missingDestination }
        let current = source.nodes.contains { $0.value == .current } ? commands.currentRouteOrigin : nil
        guard let resolved = source.resolvingCurrent(to: current) else { throw RouteExecutionFailure.currentLocationUnavailable }
        let coordinates = resolved.nodes.compactMap { node -> GeoCoordinate? in
            if case .place(let place) = node.value { return place.coordinate }; return nil
        }
        guard zip(coordinates, coordinates.dropFirst()).allSatisfy({ $0.0 != $0.1 }) else { throw RouteExecutionFailure.invalidPath }
        return resolved
    }
    @discardableResult public func pause() -> Bool {
        let reason = pendingSuspensionReason
        if reason == nil { suspensionReason = nil }
        guard canPause, let intent else { return false }
        guard commands.pauseRoute(executionID: intent.id, lease: intent.lease) else { return false }
        withdrawContinuation(.userPaused)
        phase = .pausing
        let token = revision, running = task
        running?.cancel()
        let physicalID = beginPhysicalOperation()
        transition = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.phase == .pausing else { return }
            self.freezeElapsed()
            switch settlement {
            case .settled:
                self.phase = .paused
                self.suspensionReason = reason
                self.pendingSuspensionReason = nil
            case .requiresStop(let failure): self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    @discardableResult public func resume() -> Bool {
        guard canResume, let intent, commands.resumeRoute(executionID: intent.id, lease: intent.lease) else { return false }
        phase = .running; activeStartedAt = clock.now; suspensionReason = nil
        requestContinuationIfEligible(for: intent)
        let token = revision
        let physicalID = beginPhysicalOperation()
        task = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            await self?.run(intent, token: token)
        }
        return true
    }
    @discardableResult public func cancel() -> Bool {
        guard canCancel else { return false }
        if phase == .planning {
            revision &+= 1; task?.cancel(); returnToEditing()
            suspensionReason = pendingSuspensionReason
            pendingSuspensionReason = nil
            return true
        }
        guard let intent else { return false }
        let reason = pendingSuspensionReason
        withdrawContinuation(.userCancelled)
        phase = .cancelling
        let token = revision, running = task
        commands.endRoute(executionID: intent.id, lease: intent.lease)
        running?.cancel()
        let physicalID = beginPhysicalOperation()
        transition = Task { [weak self] in
            defer { Task { @MainActor [weak self] in self?.finishPhysicalOperation(physicalID) } }
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.intent?.id == intent.id,
                  self.phase == .cancelling || self.phase == .unknown else { return }
            switch settlement {
            case .settled:
                self.returnToEditing()
                self.suspensionReason = reason
                self.pendingSuspensionReason = nil
            case .requiresStop(let failure):
                self.freezeElapsed(); self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    public func dismissCompletion(executionID: UUID) {
        guard transferHold == nil else { return }
        if completion?.executionID == executionID { completion = nil }
    }

    public func releaseForInactiveScene(continuingLease: MovementTaskLease? = nil) {
        sceneActive = false
        guard transferHold == nil else {
            objectWillChange.send()
            return
        }
        if let intent, phase == .running, continuingLease == intent.lease {
            objectWillChange.send()
            return
        }
        releaseForUnavailable(reason: .sceneInactive)
    }

    public func sceneDidBecomeActive() {
        sceneActive = true
        guard transferHold == nil else {
            objectWillChange.send()
            return
        }
        objectWillChange.send()
    }

    public func connectionDidBecomeUnavailable() {
        connectionAvailable = false
        guard transferHold == nil else {
            objectWillChange.send()
            return
        }
        releaseForUnavailable(reason: .connectionUnavailable)
    }

    public func connectionDidBecomeAvailable() {
        connectionAvailable = true
        objectWillChange.send()
    }

    public func continuationDidBecomeUnavailable() {
        guard transferHold == nil else { return }
        releaseForUnavailable(reason: .backgroundUnavailable)
    }

    private func releaseForUnavailable(reason: RouteSuspensionReason) {
        switch phase {
        case .running:
            pendingSuspensionReason = reason
            _ = pause()
        case .planning:
            revision &+= 1
            task?.cancel()
            returnToEditing()
            suspensionReason = reason
        case .preparing:
            pendingSuspensionReason = reason
            _ = cancel()
        default:
            break
        }
    }

    private func run(_ intent: RouteExecutionIntent, token: UInt64) async {
        var sequence: UInt64 = 1
        // Resume must continue the service's next sequence, not reuse an old one.
        if let previous = nextSequence[intent.id] { sequence = previous }
        while revision == token, phase == .running {
            do { try await clock.sleep(for: Self.cadence) } catch { return }
            guard revision == token, phase == .running, !Task.isCancelled else { return }
            guard sequence < UInt64.max else {
                continuationDidBecomeUnavailable()
                return
            }
            guard let controlRevision = commands.routeControlRevision(executionID: intent.id, lease: intent.lease) else { return }
            let direction = heading == .forward ? 1.0 : -1.0
            let distance = min(intent.route.totalDistanceMeters, max(0,
                (progress?.committedDistanceMeters ?? 0) + direction * intent.speed.metersPerSecond * 0.5))
            guard let coordinate = intent.route.coordinate(at: distance) else { phase = .interrupted; error = .invalidPath; return }
            let outcome = await commands.sendRoutePoint(executionID: intent.id, lease: intent.lease,
                sequence: sequence, expectedControlRevision: controlRevision, coordinate: coordinate)
            guard revision == token, self.intent?.id == intent.id, phase == .running || phase == .pausing else { return }
            switch outcome {
            case .acknowledged:
                let previousDistance = progress?.committedDistanceMeters ?? 0
                let delta = abs(distance - previousDistance)
                let atEndpoint = distance == 0 || distance == intent.route.totalDistanceMeters
                // Commit the accepted physical axis before publishing the
                // ACK. Synchronous consumers may change RT at the endpoint;
                // they must compute a zero remaining goal from this actual
                // position while the old heading is still in force.
                publishProgress(distance: distance, intent: intent)
                publishRouteAcknowledgement(sequence: sequence, distance: delta, position: distance,
                    finiteArrival: atEndpoint && !roundTripEnabled, intent: intent)
                sequence += 1; nextSequence[intent.id] = sequence
                if atEndpoint, roundTripEnabled { heading = distance == 0 ? .forward : .reverse }
                if atEndpoint, roundTripEnabled { publishProgress(distance: distance, intent: intent) }
                if atEndpoint, !roundTripEnabled {
                    freezeElapsed()
                    withdrawContinuation(.ended)
                    self.intent = nil; phase = .editing
                    completion = RouteCompletion(executionID: intent.id, coordinate: coordinate)
                    commands.endRoute(executionID: intent.id, lease: intent.lease)
                    nextSequence.removeValue(forKey: intent.id)
                    return
                }
                if phase == .pausing { return }
            case .cancelled: return
            case .controlCancelled: continue
            case .notSent(let failure):
                if phase == .pausing { return }
                freezeElapsed(); phase = .interrupted; error = .device(failure); return
            case .unconfirmed(let failure): freezeElapsed(); phase = .unknown; error = .device(failure); return
            }
        }
    }
    private var nextSequence: [UUID: UInt64] = [:]
    private func publishProgress(distance: Double, intent: RouteExecutionIntent) {
        let elapsed = accumulatedElapsed + (activeStartedAt.map { max(.zero, clock.now - $0) } ?? .zero)
        progress = RouteProgress(committedDistanceMeters: distance, totalDistanceMeters: intent.route.totalDistanceMeters,
            activeElapsed: elapsed, estimatedRemaining: .seconds((heading == .forward ? intent.route.totalDistanceMeters - distance : distance) / intent.speed.metersPerSecond))
    }
    private func freezeElapsed() {
        if let activeStartedAt { accumulatedElapsed += max(.zero, clock.now - activeStartedAt) }
        activeStartedAt = nil
        if let progress {
            self.progress = RouteProgress(committedDistanceMeters: progress.committedDistanceMeters,
                totalDistanceMeters: progress.totalDistanceMeters, activeElapsed: accumulatedElapsed,
                estimatedRemaining: progress.estimatedRemaining)
        }
    }
    private func returnToEditing() {
        freezeElapsed(); phase = .editing
        if let id = intent?.id { nextSequence.removeValue(forKey: id) }
        intent = nil
    }

    private func requestContinuationIfEligible(for intent: RouteExecutionIntent) {
        guard sceneActive else { return }
        let current = progress?.committedDistanceMeters ?? 0
        let remaining = heading == .forward
            ? max(0, intent.route.totalDistanceMeters - current)
            : max(0, current)
        let kind: ContinuedProcessingKind = roundTripEnabled ? .roundTrip : .finiteRoute
        let goal: ContinuedProcessingGoal? = roundTripEnabled
            ? .experimentalIndeterminate
            : (remaining > 0 && remaining.isFinite ? .finiteDistance(meters: remaining) : nil)
        continuationIdentity = MovementContinuationIdentity(movementID: intent.id, lease: intent.lease)
        continuationControlSubject.send(.requested(MovementContinuationDemand(
            movementID: intent.id, lease: intent.lease, kind: kind, goal: goal)))
    }

    private func withdrawContinuation(_ reason: MovementContinuationWithdrawalReason) {
        guard let identity = continuationIdentity else { return }
        continuationIdentity = nil
        continuationControlSubject.send(.withdrawn(identity, reason))
    }

    private func publishRouteAcknowledgement(sequence: UInt64, distance: Double, position: Double,
                                             finiteArrival: Bool, intent: RouteExecutionIntent) {
        guard distance.isFinite, distance >= 0, position.isFinite, position >= 0 else { return }
        movementAcknowledgementSubject.send(MovementAcknowledgement(
            movementID: intent.id, lease: intent.lease, sequence: sequence, source: .route,
            acknowledgedDistanceMeters: distance, routePositionMeters: position,
            finiteArrival: finiteArrival))
    }

    private func receive(_ event: RouteCommandEvent) {
        switch event {
        case .availabilityChanged: objectWillChange.send()
        case .ended(let id):
            guard intent?.id == id, phase != .cancelling else { return }
            withdrawContinuation(.ended)
            revision &+= 1; task?.cancel(); transition?.cancel(); returnToEditing(); error = nil
            nextSequence.removeValue(forKey: id)
        case .interrupted(let id, let failure):
            guard intent?.id == id, phase == .running else { return }
            freezeElapsed(); phase = .interrupted; error = .device(failure); task?.cancel()
        case .unknown(let id, let failure):
            guard intent?.id == id else { return }
            withdrawContinuation(.ended)
            freezeElapsed(); phase = .unknown; error = .device(failure); task?.cancel()
        }
    }
}
