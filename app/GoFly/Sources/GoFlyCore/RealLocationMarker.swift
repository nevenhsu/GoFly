/// Display-only location projection. Waiting coordinates are not a route
/// origin, a fresh GPS observation, or proof of device clear.
public struct RealLocationMarker: Equatable, Sendable {
    public enum Freshness: Equatable, Sendable {
        case fresh
        case waiting
    }

    public let observation: RealLocationObservation
    public let freshness: Freshness
}
