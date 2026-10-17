import Combine
import Foundation

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
    private let planner: any RoutePlanning
    private let commands: any RouteCommanding
    private let search: any PlaceSearching
    private let clock: any RouteClock
    private var revision: UInt64 = 0
    private var task: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var subscription: AnyCancellable?
    private var pickerCandidateSubscription: AnyCancellable?
    private var accumulatedElapsed: Duration = .zero
    private var activeStartedAt: Duration?
    private static let cadence: Duration = .milliseconds(500)

    public init(draft: RouteDraft = RouteDraft(), planner: any RoutePlanning, commands: any RouteCommanding,
                search: any PlaceSearching, clock: any RouteClock = ContinuousRouteClock()) {
        self.draft = draft; self.planner = planner; self.commands = commands; self.search = search; self.clock = clock
        subscription = commands.routeEvents.sink { [weak self] event in self?.receive(event) }
    }
    public var canEdit: Bool { phase == .editing }
    public var canStart: Bool {
        guard canEdit, commands.canBeginRoute, case .place = draft.destination.value else { return false }
        switch draft.start.value {
        case .place: return true
        case .current: return commands.currentRouteOrigin != nil
        case nil: return false
        }
    }
    public var canPause: Bool { phase == .running }
    public var canResume: Bool { phase == .paused }
    public var canCancel: Bool {
        [.planning, .preparing, .running, .pausing, .paused, .interrupted].contains(phase)
    }
    @discardableResult public func openPicker(for nodeID: RouteNodeID) -> Bool {
        guard canEdit, let node = draft.nodes.first(where: { $0.id == nodeID }) else { return false }
        let candidates = CandidateController(search: search)
        if case .place(let place) = node.value { candidates.select(place) }
        picker = RoutePickerSession(id: UUID(), nodeID: nodeID, candidates: candidates,
                                    allowsCurrent: nodeID == draft.start.id, initialValue: node.value)
        return true
    }
    @discardableResult public func confirmPicker(id: UUID, useCurrentLocation: Bool = false) -> Bool {
        guard canEdit, let session = picker, session.id == id else { return false }
        let value: RouteNodeValue
        if useCurrentLocation {
            guard session.allowsCurrent else { return false }
            value = .current
        } else {
            guard session.candidates.canGo, let place = session.candidates.candidate?.place else { return false }
            value = .place(place)
        }
        guard let changed = draft.replacing(nodeID: session.nodeID, value: value) else { return false }
        draft = changed
        picker = nil; plannedRoute = nil; completion = nil; error = nil
        return true
    }
    public func cancelPicker(id: UUID) { if picker?.id == id { picker = nil } }
    @discardableResult public func setSpeed(_ speed: RouteSpeed) -> Bool {
        guard canEdit else { return false }
        draft = draft.replacing(speed: speed)
        return true
    }
    @discardableResult public func start() -> Bool {
        guard canEdit, commands.canBeginRoute else { return false }
        let snapshot = draft
        let from: GeoCoordinate
        switch snapshot.start.value {
        case .place(let place): from = place.coordinate
        case .current:
            guard let current = commands.currentRouteOrigin else { error = .currentLocationUnavailable; return false }
            from = current
        case nil: error = .missingStart; return false
        }
        guard case .place(let destination) = snapshot.destination.value else { error = .missingDestination; return false }
        revision &+= 1
        let token = revision
        let admission = commands.routeAdmissionRevision
        phase = .planning; picker = nil; error = nil; completion = nil; progress = nil; intent = nil
        accumulatedElapsed = .zero; activeStartedAt = nil
        let planner = planner
        task = Task { [weak self] in
            do {
                let points = try await planner.plan(from: from, to: destination.coordinate)
                guard let self, self.revision == token, self.phase == .planning, !Task.isCancelled else { return }
                let route = try PlannedRoute(points: points, from: from, to: destination.coordinate)
                let intent = RouteExecutionIntent(draft: snapshot, route: route)
                self.plannedRoute = route; self.intent = intent; self.phase = .preparing
                let outcome = await self.commands.beginRoute(intent, expectedAdmissionRevision: admission)
                guard self.revision == token, self.phase == .preparing else { return }
                switch outcome {
                case .acknowledged:
                    self.phase = .running; self.activeStartedAt = self.clock.now
                    self.publishProgress(distance: 0, intent: intent)
                    await self.run(intent, token: token)
                case .cancelled: self.returnToEditing()
                case .notSent(let failure): self.phase = .interrupted; self.error = .device(failure)
                case .unconfirmed(let failure): self.phase = .unknown; self.error = .device(failure)
                }
            } catch {
                guard let self, self.revision == token, self.phase == .planning else { return }
                self.phase = .editing
                self.error = error as? RouteExecutionFailure ?? .planningFailed
            }
        }
        return true
    }
    @discardableResult public func pause() -> Bool {
        guard canPause, let intent, commands.pauseRoute(executionID: intent.id, lease: intent.lease) else { return false }
        phase = .pausing
        let token = revision, running = task
        running?.cancel()
        transition = Task { [weak self] in
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.phase == .pausing else { return }
            self.freezeElapsed()
            switch settlement {
            case .settled: self.phase = .paused
            case .requiresStop(let failure): self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    @discardableResult public func resume() -> Bool {
        guard canResume, let intent, commands.resumeRoute(executionID: intent.id, lease: intent.lease) else { return false }
        phase = .running; activeStartedAt = clock.now
        let token = revision
        task = Task { [weak self] in await self?.run(intent, token: token) }
        return true
    }
    @discardableResult public func cancel() -> Bool {
        guard canCancel else { return false }
        if phase == .planning {
            revision &+= 1; task?.cancel(); returnToEditing(); return true
        }
        guard let intent else { return false }
        phase = .cancelling
        let token = revision, running = task
        commands.endRoute(executionID: intent.id, lease: intent.lease)
        running?.cancel()
        transition = Task { [weak self] in
            guard let self else { return }
            let settlement = await self.commands.waitForRouteIdle(executionID: intent.id, lease: intent.lease)
            await running?.value
            guard self.revision == token, self.intent?.id == intent.id,
                  self.phase == .cancelling || self.phase == .unknown else { return }
            switch settlement {
            case .settled: self.returnToEditing()
            case .requiresStop(let failure):
                self.freezeElapsed(); self.phase = .unknown; self.error = .device(failure)
            }
        }
        return true
    }
    public func dismissCompletion(executionID: UUID) { if completion?.executionID == executionID { completion = nil } }

    private func run(_ intent: RouteExecutionIntent, token: UInt64) async {
        var sequence: UInt64 = 1
        // Resume must continue the service's next sequence, not reuse an old one.
        if let previous = nextSequence[intent.id] { sequence = previous }
        while revision == token, phase == .running {
            do { try await clock.sleep(for: Self.cadence) } catch { return }
            guard revision == token, phase == .running, !Task.isCancelled else { return }
            let distance = min(intent.route.totalDistanceMeters,
                (progress?.committedDistanceMeters ?? 0) + intent.speed.metersPerSecond * 0.5)
            guard let coordinate = intent.route.coordinate(at: distance) else { phase = .interrupted; error = .invalidPath; return }
            let outcome = await commands.sendRoutePoint(executionID: intent.id, lease: intent.lease,
                sequence: sequence, coordinate: coordinate)
            guard revision == token, self.intent?.id == intent.id, phase == .running || phase == .pausing else { return }
            switch outcome {
            case .acknowledged:
                sequence &+= 1; nextSequence[intent.id] = sequence
                publishProgress(distance: distance, intent: intent)
                if distance >= intent.route.totalDistanceMeters {
                    freezeElapsed()
                    self.intent = nil; phase = .editing
                    completion = RouteCompletion(executionID: intent.id, coordinate: intent.route.end)
                    commands.endRoute(executionID: intent.id, lease: intent.lease)
                    nextSequence.removeValue(forKey: intent.id)
                    return
                }
                if phase == .pausing { return }
            case .cancelled: return
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
            activeElapsed: elapsed, estimatedRemaining: .seconds((intent.route.totalDistanceMeters - distance) / intent.speed.metersPerSecond))
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
    private func receive(_ event: RouteCommandEvent) {
        switch event {
        case .availabilityChanged: objectWillChange.send()
        case .ended(let id):
            guard intent?.id == id, phase != .cancelling else { return }
            revision &+= 1; task?.cancel(); transition?.cancel(); returnToEditing(); error = nil
            nextSequence.removeValue(forKey: id)
        case .interrupted(let id, let failure):
            guard intent?.id == id, phase == .running else { return }
            freezeElapsed(); phase = .interrupted; error = .device(failure); task?.cancel()
        case .unknown(let id, let failure):
            guard intent?.id == id else { return }
            freezeElapsed(); phase = .unknown; error = .device(failure); task?.cancel()
        }
    }
}
