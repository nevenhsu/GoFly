import Combine
import Foundation

public protocol TunnelProbing: Sendable {
    func check() async throws
}

public enum TunnelProbeFailure: Error, Equatable, Sendable {
    case unavailable
    case timedOut
}

public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

@MainActor
public protocol LocationAuthorizing: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestAuthorization() async -> LocationAuthorization
}

public enum OnboardingStep: Equatable, Sendable {
    case welcome, location, vpn, complete
}

public enum VPNCheckState: Equatable, Sendable {
    case unknown, checking, reachable, unavailable, timedOut
}

public struct OnboardingClock: Sendable {
    public let now: @MainActor @Sendable () -> Duration
    public let sleep: @MainActor @Sendable (Duration) async throws -> Void

    public init(
        now: @escaping @MainActor @Sendable () -> Duration,
        sleep: @escaping @MainActor @Sendable (Duration) async throws -> Void
    ) {
        self.now = now
        self.sleep = sleep
    }

    public static var continuous: Self {
        let origin = ContinuousClock.now
        return Self(now: { origin.duration(to: .now) }, sleep: { try await Task.sleep(for: $0) })
    }
}

@MainActor
public final class OnboardingController: ObservableObject {
    @Published public private(set) var step: OnboardingStep = .welcome
    @Published public private(set) var vpnState: VPNCheckState = .unknown
    @Published public private(set) var isChecking = false
    @Published public private(set) var isAdvancing = false
    @Published public private(set) var isRequestingLocation = false
    @Published public private(set) var locationAuthorization: LocationAuthorization

    private let probe: any TunnelProbing
    private let location: any LocationAuthorizing
    private var navigationRevision: UInt64 = 0
    private var vpnActive = false
    private var generation: UInt64 = 0
    private var checkTask: Task<Void, Never>?
    private var pendingAdvance: (@MainActor () -> Void)?
    private var pendingRefresh = false
    private let clock: OnboardingClock
    private var cadenceTask: Task<Void, Never>?

    public init(probe: any TunnelProbing, location: any LocationAuthorizing, clock: OnboardingClock = .continuous) {
        self.probe = probe
        self.location = location
        self.locationAuthorization = location.authorization
        self.clock = clock
    }

    deinit {
        checkTask?.cancel()
        cadenceTask?.cancel()
    }

    public var canAdvanceVPN: Bool { step == .vpn && vpnActive && vpnState == .reachable && !isAdvancing }
    public func advanceWelcome() {
        guard step == .welcome else { return }
        step = .location
    }
    public func skipLocation() {
        guard step == .location else { return }
        navigationRevision &+= 1
        isRequestingLocation = false
        step = .vpn
    }
    public func allowLocation() async {
        guard step == .location, !isRequestingLocation else { return }
        isRequestingLocation = true
        let token = navigationRevision
        let result = await location.requestAuthorization()
        guard step == .location, token == navigationRevision else { return }
        locationAuthorization = result
        skipLocation()
    }
    public func goBack() {
        switch step {
        case .location:
            navigationRevision &+= 1
            isRequestingLocation = false
            step = .welcome
        case .vpn:
            setVPNActive(false)
            navigationRevision &+= 1
            locationAuthorization = location.authorization
            step = .location
        case .welcome, .complete:
            break
        }
    }
    public func setVPNActive(_ active: Bool) {
        guard active != vpnActive else { return }
        vpnActive = active
        generation &+= 1
        cadenceTask?.cancel()
        cadenceTask = nil
        if active {
            pendingRefresh = true
            drainPendingCheck()
            let token = generation
            let clock = clock
            let startedAt = clock.now()
            cadenceTask = Task { [weak self] in
                var next = startedAt + .seconds(5)
                while !Task.isCancelled {
                    do { try await clock.sleep(max(.zero, next - clock.now())) }
                    catch { return }
                    guard !Task.isCancelled, let self, self.generation == token,
                          self.vpnActive, self.step == .vpn else { return }
                    self.checkConnection()
                    repeat { next += .seconds(5) } while next <= clock.now()
                }
            }
        }
        else {
            checkTask?.cancel()
            pendingAdvance = nil
            pendingRefresh = false
            isAdvancing = false
            vpnState = .unknown
        }
    }
    public func checkConnection() {
        guard step == .vpn, vpnActive, checkTask == nil else { return }
        beginCheck(onAdvance: nil)
    }

    private func beginCheck(onAdvance: (@MainActor () -> Void)?) {
        let token = generation
        isChecking = true
        if vpnState == .unknown { vpnState = .checking }
        let probe = probe
        checkTask = Task { [weak self] in
            let result: Result<Void, any Error>
            do { try await probe.check(); result = .success(()) }
            catch { result = .failure(error) }
            guard let self else { return }
            self.checkTask = nil
            self.isChecking = false
            guard self.generation == token, self.vpnActive, self.step == .vpn else {
                self.drainPendingCheck()
                return
            }
            switch result {
            case .success:
                self.vpnState = .reachable
                if let onAdvance {
                    self.isAdvancing = false
                    self.setVPNActive(false)
                    self.step = .complete
                    onAdvance()
                    return
                }
            case .failure(is CancellationError): self.vpnState = .unknown
            case .failure(TunnelProbeFailure.timedOut): self.vpnState = .timedOut
            case .failure: self.vpnState = .unavailable
            }
            if onAdvance != nil { self.isAdvancing = false }
            self.drainPendingCheck()
        }
    }
    private func drainPendingCheck() {
        guard vpnActive, step == .vpn, checkTask == nil else { return }
        if let next = pendingAdvance {
            pendingAdvance = nil
            pendingRefresh = false
            beginCheck(onAdvance: next)
        } else if pendingRefresh {
            pendingRefresh = false
            beginCheck(onAdvance: nil)
        }
    }
    public func advanceVPN(onAdvance: @escaping @MainActor () -> Void) {
        guard canAdvanceVPN else { return }
        isAdvancing = true
        if checkTask == nil { beginCheck(onAdvance: onAdvance) }
        else { pendingAdvance = onAdvance }
    }
}
