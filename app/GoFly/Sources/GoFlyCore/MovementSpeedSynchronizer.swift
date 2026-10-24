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
        subscriptions = [
            route.$draft.map(\.speed).removeDuplicates().dropFirst().sink { [weak self] value in
                Task { @MainActor in self?.adopt(value) }
            },
            joystick.$speed.removeDuplicates().dropFirst().sink { [weak self] value in
                Task { @MainActor in self?.adopt(value) }
            },
            route.$phase.removeDuplicates().sink { [weak self] _ in Task { @MainActor in self?.apply() } },
            joystick.$phase.removeDuplicates().sink { [weak self] _ in Task { @MainActor in self?.apply() } }
        ]
    }

    private func adopt(_ value: RouteSpeed) {
        guard value != speed else { return }
        speed = value
        onChange(value)
        apply()
    }

    private func apply() {
        if route.draft.speed != speed { _ = route.setSpeed(speed) }
        if joystick.speed != speed { _ = joystick.setSpeed(speed) }
    }
}
