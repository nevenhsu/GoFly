import SwiftUI

enum GoFlyStyle {
    static let surface = Color(uiColor: .systemBackground)
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let secondarySurface = Color(uiColor: .tertiarySystemGroupedBackground)
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let disabledForeground = Color(uiColor: .secondaryLabel)
    static let disabledSurface = Color(uiColor: .tertiarySystemFill)
    static let errorForeground = Color(uiColor: .label)
    static let errorSurface = Color(uiColor: .secondarySystemBackground)
    static let border = Color(uiColor: .separator)
    static let subtleBorder = Color(uiColor: .opaqueSeparator).opacity(0.45)
    static let cornerRadius: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let inputRadius: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 56
    static let secondaryButtonHeight: CGFloat = 48
    static let smallButtonHeight: CGFloat = 40

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
    // Figma `Toast / 系統訊息` tokens (0 · 共用元件, light / Dark).
    static let toastDangerSurface = adaptive(light: (1.000, 0.941, 0.933), dark: (0.302, 0.153, 0.165))
    static let toastWarningSurface = adaptive(light: (1.000, 0.965, 0.902), dark: (0.322, 0.243, 0.106))
    static let toastSuccessSurface = adaptive(light: (0.941, 0.980, 0.949), dark: (0.141, 0.294, 0.176))
    static let toastMessage = adaptive(light: (0.235, 0.235, 0.263), dark: (0.820, 0.820, 0.839))
    static let toastDismiss = adaptive(light: (0.549, 0.549, 0.580), dark: (0.600, 0.600, 0.620))
    static let toastActionSurface = adaptive(light: (1, 1, 1), dark: (0.173, 0.173, 0.180))
    static let toastActionBorder = adaptive(light: (0.776, 0.776, 0.784), dark: (0.282, 0.282, 0.290))
    static let snackbarSurface = adaptive(
        light: (0.110, 0.110, 0.118), dark: (0.173, 0.173, 0.180))
    static let snackbarForeground = Color.white
    /// Execution-mode instruction card: dark in both appearances, per the
    /// redesign spec (light #1C1C1E, dark #2C2C2E) with white text.
    static let instructionSurface = snackbarSurface
    static let instructionForeground = Color.white
    static let sheetCornerRadius: CGFloat = 20
    /// Alias kept for existing call sites; see `GoFlyFont`.
    static let panelTitleFont = GoFlyFont.title

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
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
                .foregroundStyle(GoFlyTextColor.secondary)
                .frame(width: 80, height: 80)
                .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(message)
                .font(GoFlyFont.body)
                .foregroundStyle(GoFlyTextColor.secondary)
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

/// Figma 0 board buttons: 56 pt black primary, 48 pt gray secondary,
/// 40 pt action-row capsules and a filled red destructive variant.
struct GoFlyActionStyle: ButtonStyle {
    var primary = false
    var compactAtAccessibilitySizes = false
    var destructive = false
    var small = false
    /// A secondary button at the 56 pt primary height (Figma D6 結束).
    var prominent = false
    /// Overrides the button height (Figma D21 delete is 48 pt).
    var fixedHeight: CGFloat? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var height: CGFloat {
        fixedHeight ?? (small ? GoFlyStyle.smallButtonHeight
            : (primary || destructive || prominent ? GoFlyStyle.primaryButtonHeight : GoFlyStyle.secondaryButtonHeight))
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? GoFlyFont.subheadlineEmphasis : GoFlyFont.bodyEmphasis)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, small ? 14 : 16)
            .foregroundStyle(foreground)
            .tint(foreground)
            .background(background, in: Capsule())
            .brightness(isEnabled && configuration.isPressed ? (primary || destructive ? 0.12 : -0.04) : 0)
            .opacity(isEnabled && configuration.isPressed ? 0.82 : 1)
            .frame(minHeight: small ? GoFlyStyle.smallButtonHeight : 44)
            .contentShape(Capsule())
    }

    private var background: Color {
        guard isEnabled else { return GoFlyStyle.disabledSurface }
        if destructive { return GoFlyStyle.danger }
        return primary ? GoFlyStyle.primary : GoFlyStyle.secondarySurface
    }

    private var foreground: Color {
        guard isEnabled else { return GoFlyTextColor.disabled }
        if destructive { return GoFlyTextColor.onDark }
        return primary ? GoFlyTextColor.inverse : GoFlyTextColor.primary
    }
}

struct GoFlyIconStyle: ButtonStyle {
    var floating = false
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: min(symbolSize, 24), weight: .semibold))
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
            .tint(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .background(isEnabled ? (floating ? GoFlyStyle.cardSurface : GoFlyStyle.secondarySurface) : GoFlyStyle.disabledSurface, in: Circle())
            .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5).allowsHitTesting(false) }
            .shadow(color: .black.opacity(floating ? 0.09 : 0), radius: 12, x: 0, y: 5)
            .contentShape(Circle())
            .opacity(isEnabled && configuration.isPressed ? 0.65 : 1)
    }
}

// Figma `SearchField / focused｜normal` and `Progress` (0 · 共用元件).
extension GoFlyStyle {
    static let fieldSurface = adaptive(light: (0.949, 0.949, 0.969), dark: (0.227, 0.227, 0.235))
    static let fieldBorder = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let fieldFocus = adaptive(light: (0.000, 0.478, 1.000), dark: (0.039, 0.518, 1.000))
    static let tabBarSurface = adaptive(light: (0.976, 0.976, 0.976), dark: (0.110, 0.110, 0.118)).opacity(0.96)
    static let tabSeparator = adaptive(light: (0.776, 0.776, 0.784), dark: (0.220, 0.220, 0.227))
    static let tabInactive = Color(red: 0.600, green: 0.600, blue: 0.600)
    static let startSecondarySurface = adaptive(light: (0.933, 0.933, 0.941), dark: (0.173, 0.173, 0.180))
    static let dialogMessage = adaptive(light: (0.420, 0.420, 0.451), dark: (0.820, 0.820, 0.839))
    static let dialogCancelSurface = adaptive(light: (0.949, 0.949, 0.969), dark: (0.227, 0.227, 0.235))
    static let pillSurface = adaptive(light: (1, 1, 1), dark: (0.227, 0.227, 0.235))
    static let checkboxOffBorder = adaptive(light: (0.780, 0.780, 0.800), dark: (0.557, 0.557, 0.576))
    static let checkboxOffFill = adaptive(light: (1, 1, 1), dark: (0.173, 0.173, 0.180))
    static let progressTrack = adaptive(light: (0.898, 0.898, 0.918), dark: (0.173, 0.173, 0.180))
}

private struct GoFlySearchFieldBackground: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background(GoFlyStyle.fieldSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isFocused ? GoFlyStyle.fieldFocus : GoFlyStyle.fieldBorder,
                                  lineWidth: isFocused ? 1.5 : 0.75)
            }
    }
}

extension View {
    /// `SearchField` surface: `#F2F2F7` fill, 14 pt radius, 1.5 pt blue border when
    /// focused (also the selected route row), 0.75 pt gray otherwise.
    func goFlySearchField(isFocused: Bool) -> some View {
        modifier(GoFlySearchFieldBackground(isFocused: isFocused))
    }
}

/// Figma `Progress`: 6 pt capsule, black value on a `#E5E5EA` track (inverted in dark).
struct GoFlyProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = min(max(configuration.fractionCompleted ?? 0, 0), 1)
        Capsule()
            .fill(GoFlyStyle.progressTrack)
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(GoFlyStyle.primary)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityElement()
            .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}


/// The app's one type scale (docs/IOS-TYPOGRAPHY.md). Every text uses one of these tokens: iOS text styles, so
/// Dynamic Type still applies, and only two weights (regular, semibold).
enum GoFlyFont {
    /// 28 — onboarding and setup hero titles.
    static let display = Font.title.weight(.semibold)
    /// 20 — panel, card and navigation-card titles.
    static let title = Font.title3.weight(.semibold)
    /// 17 semibold — page titles, dialog titles, section titles.
    static let headline = Font.headline
    /// 17 — list rows and text fields.
    static let body = Font.body
    /// 17 semibold — primary buttons.
    static let bodyEmphasis = Font.body.weight(.semibold)
    /// 15 — secondary text.
    static let subheadline = Font.subheadline
    /// 15 semibold — compact buttons, toast titles, chips.
    static let subheadlineEmphasis = Font.subheadline.weight(.semibold)
    /// 13 — subtitles, toast messages, captions.
    static let footnote = Font.footnote
    /// 13 semibold — status pill, small chips.
    static let footnoteEmphasis = Font.footnote.weight(.semibold)
    /// 12 — role labels and axis labels.
    static let caption = Font.caption
    /// 12 semibold.
    static let captionEmphasis = Font.caption.weight(.semibold)
    /// 10 semibold, fixed — tab labels and compass letters.
    static let micro = Font.system(size: 10, weight: .semibold)
    /// 36 semibold, fixed — the speed readout.
    static let metric = Font.system(size: 36, weight: .semibold)
}


// MARK: - Text colors (docs/IOS-TYPOGRAPHY.md)
extension GoFlyStyle {
    fileprivate static let textSecondary = adaptive(light: (0.541, 0.541, 0.557), dark: (0.596, 0.596, 0.624))
    fileprivate static let textMessage = adaptive(light: (0.235, 0.235, 0.263), dark: (0.820, 0.820, 0.839))
    fileprivate static let textDisabled = adaptive(light: (0.600, 0.600, 0.627), dark: (0.420, 0.420, 0.447))
}

/// The app's one text color set. Text and text-like icons use these roles, never raw colors.
enum GoFlyTextColor {
    /// Titles, list text, primary labels (#000 / #FFF).
    static let primary = Color.primary
    /// Subtitles, captions, placeholders, inactive tab labels (#8A8A8E / #98989F).
    static let secondary = GoFlyStyle.textSecondary
    /// Text that explains a title inside a toast or dialog (#3C3C43 / #D1D1D6).
    static let message = GoFlyStyle.textMessage
    /// Disabled controls and unavailable rows.
    static let disabled = GoFlyStyle.textDisabled
    /// Text on a primary (black / white) fill: the page background color.
    static let inverse = GoFlyStyle.surface
    /// Text on fixed dark surfaces (snackbar, navigation card) and on danger fills.
    static let onDark = Color.white
    /// Error, warning and success wording.
    static let danger = GoFlyStyle.dangerForeground
    static let warning = GoFlyStyle.warningForeground
    static let success = GoFlyStyle.successForeground
}
