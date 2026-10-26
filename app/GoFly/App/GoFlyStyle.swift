import SwiftUI

/// Shared neutral palette for text, icons, surfaces, and borders.
/// The light/dark pairs follow the iOS 04 redesign; component styles alias
/// these values instead of defining their own near-identical gray literals.
enum GoFlyGrayScale {
    static let iconButtonSurface = adaptive(light: (0.949, 0.949, 0.969), dark: (0.173, 0.173, 0.180))
    static let iconButtonBorder = adaptive(light: (0.898, 0.898, 0.918), dark: (0.220, 0.220, 0.227))
    static let routeControlSurface = adaptive(light: (1, 1, 1), dark: (0.173, 0.173, 0.180))
    static let routeControlBorder = adaptive(light: (0.780, 0.780, 0.800), dark: (0.220, 0.220, 0.227))
    static let directionInactive = Color(red: 0.780, green: 0.780, blue: 0.800)
    static let disabledSurface = adaptive(light: (0.933, 0.933, 0.941), dark: (0.173, 0.173, 0.180))
    static let secondaryLabel = adaptive(light: (0.541, 0.541, 0.557), dark: (0.596, 0.596, 0.624))
    static let messageLabel = adaptive(light: (0.235, 0.235, 0.263), dark: (0.820, 0.820, 0.839))
    static let disabledLabel = adaptive(light: (0.600, 0.600, 0.627), dark: (0.420, 0.420, 0.447))
    static let pasteSymbol = adaptive(light: (0.420, 0.420, 0.420), dark: (1, 1, 1))

    static let fieldSurface = adaptive(light: (0.949, 0.949, 0.969), dark: (0.227, 0.227, 0.235))
    static let fieldBorder = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let tabBarSurface = adaptive(light: (0.976, 0.976, 0.976), dark: (0.110, 0.110, 0.118))
    static let tabInactive = Color(red: 0.600, green: 0.600, blue: 0.600)
    static let startSecondarySurface = disabledSurface
    static let dialogMessage = adaptive(light: (0.420, 0.420, 0.451), dark: (0.820, 0.820, 0.839))
    static let checkboxOffBorder = adaptive(light: (0.780, 0.780, 0.800), dark: (0.557, 0.557, 0.576))
    static let checkboxOffFill = adaptive(light: (1, 1, 1), dark: (0.173, 0.173, 0.180))
    static let progressTrack = adaptive(light: (0.898, 0.898, 0.918), dark: (0.173, 0.173, 0.180))
    static let durationWheelSurface = adaptive(light: (0.976, 0.976, 0.984), dark: (0.141, 0.141, 0.149))
    static let durationWheelBorder = adaptive(light: (0.898, 0.898, 0.918), dark: (0.220, 0.220, 0.231))
    static let pillBorder = adaptive(light: (0.776, 0.776, 0.784), dark: (0.329, 0.329, 0.345), lightAlpha: 0.45)
    static let hairline = adaptive(light: (0.776, 0.776, 0.784), dark: (0.220, 0.220, 0.227))

    static let toastDismiss = adaptive(light: (0.549, 0.549, 0.580), dark: (0.600, 0.600, 0.620))
    static let toastActionSurface = adaptive(light: (1, 1, 1), dark: (0.173, 0.173, 0.180))
    static let toastActionBorder = adaptive(light: (0.776, 0.776, 0.784), dark: (0.282, 0.282, 0.290))
    static let snackbarSurface = adaptive(light: (0.110, 0.110, 0.118), dark: (0.173, 0.173, 0.180))
    static let snackbarActionSurface = adaptive(light: (1, 1, 1), dark: (0.227, 0.227, 0.235))
    static let snackbarActionBorder = adaptive(light: (0.776, 0.776, 0.784), dark: (1, 1, 1),
                                               lightAlpha: 0.45, darkAlpha: 0.18)
    static let snackbarBorder = adaptive(light: (1, 1, 1), dark: (1, 1, 1), lightAlpha: 0, darkAlpha: 0.12)

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat),
                                 lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let value = isDark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum GoFlyStyle {
    static let surface = Color(uiColor: .systemBackground)
    static let cardSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let secondarySurface = GoFlyGrayScale.iconButtonSurface
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let disabledForeground = GoFlyGrayScale.disabledLabel
    static let disabledSurface = GoFlyGrayScale.disabledSurface
    static let errorForeground = Color(uiColor: .label)
    static let errorSurface = Color(uiColor: .secondarySystemBackground)
    static let border = GoFlyGrayScale.hairline
    static let subtleBorder = GoFlyGrayScale.hairline.opacity(0.45)
    static let cornerRadius: CGFloat = 20
    /// Longer than a heartbeat write; see `goFlySteadyDisabled`.
    static let admissionBlipDelay: Duration = .seconds(1)
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
    static let toastMessage = GoFlyGrayScale.messageLabel
    static let toastDismiss = GoFlyGrayScale.toastDismiss
    static let toastActionSurface = GoFlyGrayScale.toastActionSurface
    static let toastActionBorder = GoFlyGrayScale.toastActionBorder
    static let snackbarSurface = GoFlyGrayScale.snackbarSurface
    static let snackbarForeground = Color.white
    /// Execution-mode instruction card: dark in both appearances, per the
    /// redesign spec (light #1C1C1E, dark #2C2C2E) with white text.
    static let instructionSurface = snackbarSurface
    static let instructionForeground = Color.white
    static let sheetCornerRadius: CGFloat = 20
    /// Alias kept for existing call sites; see `GoFlyFont`.
    static let panelTitleFont = GoFlyFont.title

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat),
                                 lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            let value = isDark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// Opaque content keeps labels readable over every map style and in Reduce Transparency.
/// Only map overlays receive elevation; ordinary content cards remain flat.
private struct GoFlyCard: ViewModifier {
    var floating: Bool
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .goFlyShadow(floating ? .floating : nil)
    }
}

extension View {
    func goFlyCard(floating: Bool = false, radius: CGFloat = GoFlyStyle.cornerRadius) -> some View {
        modifier(GoFlyCard(floating: floating, radius: radius))
    }
}

/// Each hold heartbeat marks native work busy for a moment, which briefly
/// revokes admission. Show a disabled state only once it has lasted `delay`,
/// so controls do not flicker; the action itself still checks admission.
private struct GoFlySteadyDisabled: ViewModifier {
    let disabled: Bool
    let delay: Duration
    @State private var shownDisabled: Bool

    init(disabled: Bool, delay: Duration) {
        self.disabled = disabled
        self.delay = delay
        _shownDisabled = State(initialValue: disabled)
    }

    func body(content: Content) -> some View {
        content
            .disabled(shownDisabled)
            .task(id: disabled) {
                if disabled, !shownDisabled {
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                }
                shownDisabled = disabled
            }
    }
}

extension View {
    func goFlySteadyDisabled(_ disabled: Bool, delay: Duration = GoFlyStyle.admissionBlipDelay) -> some View {
        modifier(GoFlySteadyDisabled(disabled: disabled, delay: delay))
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
/// The solid capsule CTA of the location and place-details cards. Colours
/// follow the environment so `goFlySteadyDisabled` also steadies them.
struct GoFlyCardPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? GoFlyStyle.surface : GoFlyTextColor.disabled)
            .background(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledSurface, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

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
            .overlay {
                if isEnabled && !primary && !destructive {
                    Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5).allowsHitTesting(false)
                }
            }
            // Primary/destructive fills keep their color while pressed: a sheet drag also presses the button, and a lightened black fill reads as disabled.
            .brightness(isEnabled && configuration.isPressed && !(primary || destructive) ? -0.04 : 0)
            .opacity(isEnabled && configuration.isPressed && !(primary || destructive) ? 0.82 : 1)
            .scaleEffect(isEnabled && configuration.isPressed && (primary || destructive) ? 0.98 : 1)
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

/// Small icon + text route action (新增停靠點 / 檢視路線 / 反轉順序); gray when disabled.
struct GoFlyRouteTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GoFlyFont.subheadlineEmphasis)
            .foregroundStyle(isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
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
            .background(isEnabled
                        ? (floating ? GoFlyStyle.cardSurface : GoFlyGrayScale.iconButtonSurface)
                        : GoFlyGrayScale.disabledSurface, in: Circle())
            .overlay {
                if isEnabled {
                    Circle().strokeBorder(floating ? GoFlyStyle.subtleBorder : GoFlyGrayScale.iconButtonBorder,
                                          lineWidth: 0.5).allowsHitTesting(false)
                }
            }
            .goFlyShadow(floating ? .floating : nil)
            .contentShape(Circle())
            .opacity(isEnabled && configuration.isPressed ? 0.65 : 1)
    }
}

/// Gray icon-button chrome that reflects the Button's enabled state.
struct GoFlyIconButtonChrome: ViewModifier {
    let diameter: CGFloat
    let showsBorder: Bool
    let enabledSurface: Color
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .frame(width: diameter, height: diameter)
            .foregroundStyle(isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
            .background(isEnabled ? enabledSurface : GoFlyGrayScale.disabledSurface,
                        in: Circle())
            .overlay {
                if isEnabled && showsBorder {
                    Circle().strokeBorder(GoFlyGrayScale.iconButtonBorder, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
    }
}

extension View {
    func goFlyIconButtonChrome(diameter: CGFloat, showsBorder: Bool = true,
                               enabledSurface: Color = GoFlyGrayScale.iconButtonSurface) -> some View {
        modifier(GoFlyIconButtonChrome(diameter: diameter, showsBorder: showsBorder,
                                       enabledSurface: enabledSurface))
    }
}

private struct GoFlyIconForeground: ViewModifier {
    let enabledColor: Color
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.foregroundStyle(isEnabled ? enabledColor : GoFlyTextColor.disabled)
    }
}

extension View {
    func goFlyIconForeground(enabledColor: Color = GoFlyTextColor.primary) -> some View {
        modifier(GoFlyIconForeground(enabledColor: enabledColor))
    }
}

// Figma `SearchField / focused｜normal` and `Progress` (0 · 共用元件).
extension GoFlyStyle {
    static let fieldSurface = GoFlyGrayScale.fieldSurface
    static let fieldBorder = GoFlyGrayScale.fieldBorder
    static let fieldFocus = adaptive(light: (0.000, 0.478, 1.000), dark: (0.039, 0.518, 1.000))
    static let tabBarSurface = GoFlyGrayScale.tabBarSurface.opacity(0.96)
    static let tabSeparator = hairline
    static let tabInactive = GoFlyGrayScale.tabInactive
    static let startSecondarySurface = GoFlyGrayScale.startSecondarySurface
    static let dialogMessage = GoFlyGrayScale.dialogMessage
    static let dialogCancelSurface = GoFlyGrayScale.fieldSurface
    static let pillSurface = adaptive(light: (1, 1, 1), dark: (0.227, 0.227, 0.235))
    static let checkboxOffBorder = GoFlyGrayScale.checkboxOffBorder
    static let checkboxOffFill = GoFlyGrayScale.checkboxOffFill
    static let progressTrack = GoFlyGrayScale.progressTrack
    /// Figma F6.a `TimePicker / Wheel` (04 · iOS Redesign).
    static let durationWheelSurface = GoFlyGrayScale.durationWheelSurface
    static let durationWheelBorder = GoFlyGrayScale.durationWheelBorder
    /// Figma `StatusPill` stroke: #C6C6C8 at 45 % (light), #545458 1 pt (dark).
    static let pillBorder = GoFlyGrayScale.pillBorder
    /// Figma `StatusPill` dots for the neutral and paused states.
    static let pillDotNeutral = Color(uiColor: .systemGray)
    static let pillDotWarning = Color(red: 1.000, green: 0.624, blue: 0.039)
    /// Opaque hairline (#C6C6C8 / #38383A): tab bar separator and small round controls.
    static let hairline = GoFlyGrayScale.hairline
    /// Figma `Snackbar / 可復原` action button.
    static let snackbarActionSurface = GoFlyGrayScale.snackbarActionSurface
    static let snackbarActionBorder = GoFlyGrayScale.snackbarActionBorder
    static let snackbarBorder = GoFlyGrayScale.snackbarBorder
}

/// Figma 04 drop shadows. `floating`: search bar, status pill, map controls, panels,
/// snackbar and instruction card. `card`: location cards. `chip`: speed chip and small icon buttons.
enum GoFlyShadow {
    case floating, card, chip
}

extension View {
    @ViewBuilder
    func goFlyShadow(_ shadow: GoFlyShadow?) -> some View {
        switch shadow {
        case .floating:
            // SwiftUI radius is half the Figma blur.
            self.shadow(color: .black.opacity(0.06), radius: 1.5, x: 0, y: 1)
                .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
        case .card:
            self.shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 8)
        case .chip:
            self.shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
        case nil:
            self
        }
    }
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
    /// 22 — duration picker wheel digits (Figma F6.a `TimePicker / Wheel`).
    static let wheel = Font.title2
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
    fileprivate static let textSecondary = GoFlyGrayScale.secondaryLabel
    fileprivate static let textMessage = GoFlyGrayScale.messageLabel
    fileprivate static let textDisabled = GoFlyGrayScale.disabledLabel
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

/// Page and sheet title row: the title stays centered on the page whatever the
/// widths of the leading and trailing controls.
/// Every sheet grabber: capsule 8 pt from the top, content starts 20 pt below it.
enum GoFlyGrabber {
    static let topInset: CGFloat = 8
    static let capsuleHeight: CGFloat = 5
    static let contentGap: CGFloat = 20
    static let rowHeight: CGFloat = topInset + capsuleHeight + contentGap
}

struct GoFlySheetHeader<Leading: View, Trailing: View>: View {
    var title: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: 44)
        .overlay {
            if let title {
                Text(title)
                    .font(GoFlyFont.headline)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 88)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

extension View {
    /// A tap outside a text field ends editing; buttons under the tap still fire.
    func goFlyDismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
