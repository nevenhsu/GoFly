import SwiftUI

enum GoFlyStyle {
    static let surface = Color(uiColor: .systemBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let disabledForeground = Color(uiColor: .secondaryLabel)
    static let disabledSurface = Color(uiColor: .tertiarySystemFill)
    static let errorForeground = Color(uiColor: .label)
    static let errorSurface = Color(uiColor: .secondarySystemBackground)
    static let border = Color(uiColor: .separator)
    static let cornerRadius: CGFloat = 16
}

/// Explicit English fallback also covers keys supplied by the service domain.
@MainActor
func goFlyString(_ key: String) -> String {
    let english = Bundle.main.path(forResource: "en", ofType: "lproj")
        .flatMap(Bundle.init(path:))?
        .localizedString(forKey: key, value: nil, table: nil)
    let fallback = english == key ? "GoFly" : (english ?? "GoFly")
    let selected = Bundle.main.path(forResource: GoFlyPreferences.shared.effectiveLanguage, ofType: "lproj")
        .flatMap(Bundle.init(path:))
    return selected?.localizedString(forKey: key, value: fallback, table: nil) ?? fallback
}

@MainActor
func goFlyLocalizedFormat(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: format, locale: GoFlyPreferences.shared.locale, arguments: arguments)
}

struct GoFlyActionStyle: ButtonStyle {
    var primary = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, primary ? 4 : 0)
            .foregroundStyle(foreground)
            .tint(foreground)
            .background(
                isEnabled ? (primary ? GoFlyStyle.primary : GoFlyStyle.secondarySurface) : GoFlyStyle.disabledSurface,
                in: Capsule()
            )
            .overlay {
                if !primary {
                    Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
                }
            }
            .opacity(isEnabled && configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        isEnabled ? (primary ? GoFlyStyle.surface : GoFlyStyle.primary) : GoFlyStyle.disabledForeground
    }
}

struct GoFlyIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .tint(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .background(isEnabled ? GoFlyStyle.secondarySurface : GoFlyStyle.disabledSurface, in: Circle())
            .opacity(isEnabled && configuration.isPressed ? 0.65 : 1)
    }
}
