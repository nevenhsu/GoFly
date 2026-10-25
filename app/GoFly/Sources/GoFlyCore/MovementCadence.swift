import Foundation

/// How often each writer sends a point (2026-10-25). Manual joystick control
/// stays responsive at half a second; route and wander send once a second and
/// the map arrow interpolates between acknowledged points.
public enum MovementCadence {
    public static let manualSeconds = 0.5
    public static let pathSeconds = 1.0
    public static let manual: Duration = .milliseconds(500)
    public static let path: Duration = .seconds(1)
}
