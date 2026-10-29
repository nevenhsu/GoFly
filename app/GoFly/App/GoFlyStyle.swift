import GoFlyCore
import SwiftUI

/// Semantic color aliases used by shared controls and screens.
enum GoFlyStyle {
    static let surface = GoFlyThemeColor.surfaceCard
    static let cardSurface = GoFlyThemeColor.surfaceCard
    static let canvas = GoFlyThemeColor.canvas
    static let secondarySurface = GoFlyThemeColor.surfaceControl
    static let actionSecondarySurface = GoFlyThemeColor.actionSecondarySurface
    static let primary = GoFlyThemeColor.actionPrimarySurface
    /// User-confirmed exception to the Figma variable's near-white dark value.
    static let primaryActionText = GoFlyThemeColor.commonWhite
    static let secondary = GoFlyThemeColor.textSecondary
    static let disabledForeground = GoFlyThemeColor.textDisabled
    static let disabledSurface = GoFlyThemeColor.surfaceDisabled
    static let errorForeground = GoFlyThemeColor.textDanger
    static let errorSurface = GoFlyThemeColor.surfaceStatusDanger
    static let border = GoFlyThemeColor.lineBorder
    static let subtleBorder = GoFlyThemeColor.lineSeparator.opacity(0.45)
    static let cornerRadius: CGFloat = 20
    /// Longer than a heartbeat write; see `goFlySteadyDisabled`.
    static let admissionBlipDelay: Duration = .seconds(1)
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let inputRadius: CGFloat = 12
    static let primaryButtonHeight: CGFloat = 56
    static let secondaryButtonHeight: CGFloat = 48
    static let smallButtonHeight: CGFloat = 40

    static let danger = GoFlyThemeColor.actionDangerSurface
    static let warning = GoFlyThemeColor.iconWarning
    static let success = GoFlyThemeColor.iconSuccess
    static let dangerForeground = GoFlyThemeColor.textDanger
    static let warningForeground = GoFlyThemeColor.textWarning
    static let successForeground = GoFlyThemeColor.textSuccess
    static let toastDangerSurface = GoFlyThemeColor.surfaceStatusDanger
    static let toastWarningSurface = GoFlyThemeColor.surfaceStatusWarning
    static let toastSuccessSurface = GoFlyThemeColor.surfaceStatusSuccess
    static let toastMessage = GoFlyThemeColor.textStatusSecondary
    static let toastDismiss = GoFlyThemeColor.iconSecondary
    static let toastActionSurface = GoFlyThemeColor.surfaceControlFloating
    static let toastActionBorder = GoFlyThemeColor.lineBorder
    static let snackbarSurface = GoFlyThemeColor.commonBlack
    static let snackbarForeground = GoFlyThemeColor.commonWhite
    static let instructionSurface = snackbarSurface
    static let instructionForeground = GoFlyThemeColor.commonWhite
    static let sheetCornerRadius: CGFloat = 20
    static let panelTitleFont = GoFlyFont.title

    // Component-specific roles alias the semantic token table above.
    static let iconButtonSurface = GoFlyThemeColor.surfaceControlFloating
    static let iconButtonBorder = GoFlyThemeColor.lineSeparator
    static let routeControlSurface = GoFlyThemeColor.surfaceControlFloating
    static let routeControlBorder = GoFlyThemeColor.lineSeparator
    static let directionInactive = GoFlyThemeColor.iconSecondary
    static let pasteSymbol = GoFlyThemeColor.iconInputDefault
    static let fieldSurface = GoFlyThemeColor.surfaceInput
    static let fieldBorder = GoFlyThemeColor.lineInputDefault
    static let fieldFocus = GoFlyThemeColor.iconAccent
    static let overlayPanelSurface = GoFlyThemeColor.surfaceOverlaySheet
    static let tabBarSurface = overlayPanelSurface
    static let tabSeparator = GoFlyThemeColor.lineSeparator
    static let tabInactive = GoFlyThemeColor.iconSecondary
    static let startSecondarySurface = GoFlyThemeColor.surfaceDisabled
    static let dialogMessage = GoFlyThemeColor.textStatusSecondary
    static let dialogCancelSurface = GoFlyThemeColor.surfaceControl
    static let pillSurface = GoFlyThemeColor.surfaceControlFloating
    static let checkboxOffBorder = GoFlyThemeColor.lineBorder
    static let checkboxOffFill = GoFlyThemeColor.surfaceCard
    static let progressTrack = GoFlyThemeColor.lineSeparator
    static let durationWheelSurface = GoFlyThemeColor.surfaceControl
    static let durationWheelBorder = GoFlyThemeColor.lineSeparator
    static let pillBorder = GoFlyThemeColor.lineBorder
    static let pillDotNeutral = GoFlyThemeColor.iconSecondary
    static let pillDotWarning = GoFlyThemeColor.iconWarning
    static let hairline = GoFlyThemeColor.lineSeparator
    static let snackbarActionSurface = GoFlyThemeColor.surfaceControlFloating
    static let snackbarActionBorder = GoFlyThemeColor.lineSeparator
    static let snackbarBorder = GoFlyThemeColor.commonWhite.opacity(0.12)
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
            .foregroundStyle(isEnabled ? GoFlyStyle.primaryActionText : GoFlyTextColor.disabled)
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
            // Primary/destructive fills keep their token color while pressed: a sheet drag also presses the button, and a lightened fill reads as disabled.
            .brightness(isEnabled && configuration.isPressed && !(primary || destructive) ? -0.04 : 0)
            .opacity(isEnabled && configuration.isPressed && !(primary || destructive) ? 0.82 : 1)
            .scaleEffect(isEnabled && configuration.isPressed && (primary || destructive) ? 0.98 : 1)
            .frame(minHeight: small ? GoFlyStyle.smallButtonHeight : 44)
            .contentShape(Capsule())
    }

    private var background: Color {
        guard isEnabled else { return GoFlyStyle.disabledSurface }
        if destructive { return GoFlyStyle.danger }
        return primary ? GoFlyStyle.primary : GoFlyStyle.actionSecondarySurface
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
                        ? (floating ? GoFlyStyle.cardSurface : GoFlyStyle.iconButtonSurface)
                        : GoFlyStyle.disabledSurface, in: Circle())
            .overlay {
                if isEnabled {
                    Circle().strokeBorder(floating ? GoFlyStyle.subtleBorder : GoFlyStyle.iconButtonBorder,
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
            .background(isEnabled ? enabledSurface : GoFlyStyle.disabledSurface,
                        in: Circle())
            .overlay {
                if isEnabled && showsBorder {
                    Circle().strokeBorder(GoFlyStyle.iconButtonBorder, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
    }
}

extension View {
    func goFlyIconButtonChrome(diameter: CGFloat, showsBorder: Bool = true,
                               enabledSurface: Color = GoFlyStyle.iconButtonSurface) -> some View {
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

// Search, status, and surface roles alias Figma 04 semantic tokens.
/// Figma 04 drop shadows. `floating`: search bar, status pill, map controls, panels,
/// snackbar and instruction card. `card`: location cards. `chip`: speed chip and small icon buttons.
enum GoFlyShadow {
    case floating, toast, card, chip
}

extension View {
    @ViewBuilder
    func goFlyShadow(_ shadow: GoFlyShadow?) -> some View {
        switch shadow {
        case .floating:
            // SwiftUI radius is half the Figma blur.
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 1.5, x: 0, y: 1)
                .shadow(color: GoFlyThemeColor.commonBlack.opacity(0.09), radius: 12, x: 0, y: 5)
        case .toast:
            // Figma toast shadow: black 18%, y=4, blur=16 (SwiftUI radius is half the blur).
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.18), radius: 8, x: 0, y: 4)
        case .card:
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.14), radius: 12, x: 0, y: 8)
        case .chip:
            self.shadow(color: GoFlyThemeColor.commonBlack.opacity(0.06), radius: 2, x: 0, y: 1)
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
    /// 14 semibold — Figma `Theme/button/small`, including the R04 help link.
    static let buttonSmall = Font.system(size: 14, weight: .semibold)
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
/// Text and text-like icons use semantic Figma tokens; action foreground uses
/// pure common white per the confirmed Dark primary-button rule.
enum GoFlyTextColor {
    static let primary = GoFlyThemeColor.textPrimary
    static let secondary = GoFlyThemeColor.textSecondary
    static let message = GoFlyThemeColor.textStatusSecondary
    static let disabled = GoFlyThemeColor.textDisabled
    static let inverse = GoFlyThemeColor.commonWhite
    static let onDark = GoFlyThemeColor.commonWhite
    static let danger = GoFlyThemeColor.textDanger
    static let warning = GoFlyThemeColor.textWarning
    static let success = GoFlyThemeColor.textSuccess
    static let accent = GoFlyThemeColor.textAccent
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
