import Foundation

/// A map notice the person can dismiss until it occurs again.
public enum DismissibleNotice: CaseIterable, Hashable, Sendable {
    case serviceError, joystickError, routeError, recovery, continuation
}

/// What the person dismissed among the map's error and status notices, plus
/// the one notice the map raises itself. Each source decides whether its
/// notice exists; this only records whether the person put it away.
public struct NoticeState: Equatable, Sendable {
    private var dismissed: Set<DismissibleNotice> = []
    /// The unconfirmed position the person returned from or dismissed.
    private var returnedFromUnconfirmedID: UUID?
    /// A favorite route save failure, until dismissed or the draft changes.
    public private(set) var favoriteRouteKey: String?

    public init() {}

    public func isDismissed(_ notice: DismissibleNotice) -> Bool { dismissed.contains(notice) }
    public mutating func dismiss(_ notice: DismissibleNotice) { dismissed.insert(notice) }
    /// A new occurrence shows the notice again.
    public mutating func reopen(_ notice: DismissibleNotice) { dismissed.remove(notice) }
    /// Reopens `notice` when its source reports a new value rather than clearing it.
    public mutating func reopen<Value>(_ notice: DismissibleNotice, ifPresent value: Value?) {
        if value != nil { reopen(notice) }
    }

    /// The unconfirmed-position notice shows until the person leaves that same position.
    public func showsUnconfirmed(_ id: UUID?) -> Bool { returnedFromUnconfirmedID != id }
    public mutating func leaveUnconfirmed(_ id: UUID?) { returnedFromUnconfirmedID = id }

    public mutating func showFavoriteRouteFailure(_ key: String?) { favoriteRouteKey = key }
    public mutating func clearFavoriteRouteFailure() { favoriteRouteKey = nil }
}
