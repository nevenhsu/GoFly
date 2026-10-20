import SwiftUI

/// Shared severity vocabulary for the status pill, banners and snackbar.
/// Color is never the only signal: every tone also carries a symbol and a
/// localized accessibility label.
enum GoFlyStatusTone: String, CaseIterable, Sendable {
    case neutral
    case active
    case danger
    case warning
    case success

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

    var surface: Color { tint.opacity(0.12) }
    var border: Color { tint.opacity(0.35) }
}
