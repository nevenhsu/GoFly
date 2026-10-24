import Combine
import Foundation

/// Route, joystick and wander share one speed preference (Figma D7). A change
/// in either controller is reported through `onChange` for persistence and
/// mirrored to the other; a controller that was busy catches up when its phase
/// changes.
@MainActor
public final class MovementSpeedSynchronizer {
    public private(set) var speed: RouteSpeed
    private let route: RouteExecutionController
    private let joystick: JoystickMovementController
    private let onChange: @MainActor (RouteSpeed) -> Void
    private var subscriptions: [AnyCancellable] = []

    public init(route: RouteExecutionController, joystick: JoystickMovementController, initial: RouteSpeed,
                onChange: @escaping @MainActor (RouteSpeed) -> Void) {
        self.route = route
        self.joystick = joystick
        self.speed = initial
        self.onChange = onChange
        apply()
        // A speed change is adopted synchronously so the canonical `speed` is never
        // stale, and it is mirrored only to the *other* controller (the source is
        // already updating itself). Phase changes only catch up a controller that
        // was busy; they re-read the canonical speed, so no change can bounce back.
        subscriptions = [
            route.$draft.map(\.speed).removeDuplicates().dropFirst().sink { [weak self] value in
                self?.adopt(value, from: .route)
            },
            joystick.$speed.removeDuplicates().dropFirst().sink { [weak self] value in
                self?.adopt(value, from: .joystick)
            },
            route.$phase.removeDuplicates().dropFirst().sink { [weak self] _ in Task { @MainActor in self?.apply() } },
            joystick.$phase.removeDuplicates().dropFirst().sink { [weak self] _ in Task { @MainActor in self?.apply() } }
        ]
    }

    private enum Source { case route, joystick }

    private func adopt(_ value: RouteSpeed, from source: Source) {
        guard value != speed else { return }
        speed = value
        onChange(value)
        switch source {
        case .route: _ = joystick.setSpeed(value)
        case .joystick: _ = route.setSpeed(value)
        }
    }

    private func apply() {
        if route.draft.speed != speed { _ = route.setSpeed(speed) }
        if joystick.speed != speed { _ = joystick.setSpeed(speed) }
    }
}
