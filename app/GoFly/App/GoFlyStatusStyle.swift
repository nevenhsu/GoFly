import SwiftUI
import GoFlyCore

/// Shared severity vocabulary for the status pill, banners and snackbar.
/// Color is never the only signal: every tone also carries a symbol and a
/// localized accessibility label.
enum GoFlyStatusTone: String, CaseIterable, Sendable {
    case neutral
    case active
    case danger
    case warning
    case success

    static var warn: GoFlyStatusTone { .warning }

    var tint: Color {
        switch self {
        case .neutral: GoFlyStyle.secondary
        case .active: GoFlyStyle.primary
        case .danger: GoFlyStyle.danger
        case .warning: GoFlyStyle.warning
        case .success: GoFlyStyle.success
        }
    }

    var foreground: Color {
        switch self {
        case .neutral, .active: GoFlyStyle.primary
        case .danger: GoFlyStyle.dangerForeground
        case .warning: GoFlyStyle.warningForeground
        case .success: GoFlyStyle.successForeground
        }
    }

    var symbol: String {
        switch self {
        case .neutral: GoFlySymbols.waiting
        case .active: GoFlySymbols.location
        case .danger: GoFlySymbols.dangerFilled
        case .warning: GoFlySymbols.warningFilled
        case .success: GoFlySymbols.successFilled
        }
    }

    /// Spoken severity, so VoiceOver does not depend on the color.
    var accessibilityKey: String { "status.tone.\(rawValue)" }

    /// Figma `StatusPill` dot: gray #8E8E93, green, orange #FF9F0A, red (system green/red adapt in dark).
    var pillDot: Color {
        switch self {
        case .neutral, .active: Color(red: 0.557, green: 0.557, blue: 0.576)
        case .warning: Color(red: 1.0, green: 0.624, blue: 0.039)
        case .danger: GoFlyStyle.danger
        case .success: GoFlyStyle.success
        }
    }

    var surface: Color { tint.opacity(0.12) }
    var border: Color { tint.opacity(0.35) }

    /// Toast fill from the Figma `Toast / 系統訊息` variants.
    var toastSurface: Color {
        switch self {
        case .danger: GoFlyStyle.toastDangerSurface
        case .warning: GoFlyStyle.toastWarningSurface
        case .success: GoFlyStyle.toastSuccessSurface
        case .neutral, .active: GoFlyStyle.cardSurface
        }
    }
}

/// One display state for the map and Settings service pill.
typealias GoFlySessionStatus = SessionDisplayStatus

extension SessionDisplayStatus {
    var tone: GoFlyStatusTone {
        switch self {
        case .started, .stopped: .neutral
        case .simulating: .success
        case .paused: .warning
        case .error: .danger
        }
    }
}
