import Foundation
import GoFlyCore

/// Figma D10 bottom panel copy: "路線已暫停 · 45%" over "剩餘 1.2 km · 預估 14 分鐘".
@MainActor
extension RouteExecutionController {
    var pausedPanelTitle: String {
        let percent = Int(((progress?.fraction ?? 0) * 100).rounded())
        return goFlyLocalizedFormat(goFlyString("route.paused.progress"), percent)
    }

    var pausedPanelSubtitle: String? {
        guard let progress else { return nil }
        let remaining = max(0, heading == .reverse
            ? progress.committedDistanceMeters
            : progress.totalDistanceMeters - progress.committedDistanceMeters)
        let minutes = Int(ceil(Double(max(0, progress.estimatedRemaining.components.seconds)) / 60))
        return goFlyLocalizedFormat(goFlyString("route.paused.remaining"), remaining / 1_000, minutes)
    }
}
