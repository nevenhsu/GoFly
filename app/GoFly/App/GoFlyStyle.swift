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
    static let subtleBorder = Color(uiColor: .opaqueSeparator).opacity(0.45)
    static let inputSurface = Color(uiColor: .systemGray5)
    static let inputBorder = Color(uiColor: .systemGray)
    static let cornerRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14

    // 2026-10-20 Google Maps redesign: status colors are semantic and always
    // paired with an icon and text, never color alone.
    static let danger = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)
    static let success = Color(uiColor: .systemGreen)
    static let dangerForeground = adaptive(
        light: (0.843, 0.000, 0.082), dark: (1.000, 0.412, 0.380))
    static let warningForeground = adaptive(
        light: (0.788, 0.204, 0.000), dark: (1.000, 0.702, 0.251))
    static let successForeground = adaptive(
        light: (0.141, 0.541, 0.239), dark: (0.188, 0.820, 0.345))
    static let snackbarSurface = adaptive(
        light: (0.110, 0.110, 0.118), dark: (0.173, 0.173, 0.180))
    static let snackbarForeground = Color.white
    /// Execution-mode instruction card: dark in both appearances, per the
    /// redesign spec (light #1C1C1E, dark #2C2C2E) with white text.
    static let instructionSurface = snackbarSurface
    static let instructionForeground = Color.white
    static let sheetCornerRadius: CGFloat = 20

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }
}

/// Opaque content keeps labels readable over every map style and in Reduce Transparency.
/// Only map overlays receive elevation; ordinary content cards remain flat.
private struct GoFlyCard: ViewModifier {
    var floating: Bool
    var radius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(floating ? (colorScheme == .dark ? 0.28 : 0.09) : 0),
                    radius: 16, x: 0, y: 5)
    }
}

extension View {
    func goFlyCard(floating: Bool = false, radius: CGFloat = GoFlyStyle.cornerRadius) -> some View {
        modifier(GoFlyCard(floating: floating, radius: radius))
    }
}

struct GoFlyEmptyState: View {
    var symbol: String
    var message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(GoFlyStyle.secondary)
                .frame(width: 80, height: 80)
                .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(message)
                .font(.body)
                .foregroundStyle(GoFlyStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
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
    var compactAtAccessibilitySizes = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 16)
            .padding(.vertical, compactAtAccessibilitySizes && dynamicTypeSize.isAccessibilitySize ? 0 : (primary ? 6 : 2))
            .foregroundStyle(foreground)
            .tint(foreground)
            .background(
                isEnabled ? (primary ? GoFlyStyle.primary : GoFlyStyle.secondarySurface) : GoFlyStyle.disabledSurface,
                in: Capsule()
            )
            .overlay {
                if !primary {
                    Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                }
            }
            .brightness(isEnabled && configuration.isPressed ? (primary ? 0.12 : -0.04) : 0)
            .opacity(isEnabled && configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        isEnabled ? (primary ? GoFlyStyle.surface : GoFlyStyle.primary) : GoFlyStyle.disabledForeground
    }
}

struct GoFlyIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: min(symbolSize, 24), weight: .semibold))
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .tint(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .background(isEnabled ? GoFlyStyle.secondarySurface : GoFlyStyle.disabledSurface, in: Circle())
            .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5).allowsHitTesting(false) }
            .contentShape(Circle())
            .opacity(isEnabled && configuration.isPressed ? 0.65 : 1)
    }
}
