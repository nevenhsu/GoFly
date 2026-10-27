import Foundation

/// Time and eligibility rules for automatic signing renewal.
/// Kept in the Mac core so the app scheduler and offline tests share one policy.
public enum MacAutoRenewPolicy {
    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let renewalThreshold: TimeInterval = 4 * 24 * 60 * 60

    public static func isCheckDue(now: Date, lastCheck: Date?) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    public static func shouldBegin(now: Date, expiresAt: Date?, enabled: Bool,
                                   installed: Bool, reachable: Bool, networkAvailable: Bool,
                                   operationInProgress: Bool) -> Bool {
        guard enabled, installed, reachable, networkAvailable, !operationInProgress,
              let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) < renewalThreshold
    }
}
