import SwiftUI
import GoFlyCore

/// The single status presentation for the redesign (plan 4.11), Figma
/// `Toast / 系統訊息 / danger｜warn｜success`.
///
/// Severity is conveyed by icon + text + color. The toast sits at the top of a
/// sheet or the map, shows at most one primary action, and carries a close
/// button only when the caller allows dismissal (or it floats over the map).
/// Repair guidance belongs in `message`, not in a separate block lower on the
/// screen. Height follows the content so large text sizes wrap instead of clip.
struct GoFlyStatusBanner: View {
    let tone: GoFlyStatusTone
    let title: String
    var message: String?
    var actionTitle: String?
    var onAction: (() -> Void)?
    var onDismiss: (() -> Void)?
    var identifier: String?
    var actionEnabled = true
    var actionIdentifier: String? = nil
    var titleIdentifier: String? = nil
    var messageIdentifier: String? = nil
    var isFloating = true
    @State private var isDismissedLocally = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if !isDismissedLocally {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: tone.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(tone.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(minHeight: 20, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("\(goFlyString(tone.accessibilityKey)), \(title)")
                        .accessibilityIdentifier(titleIdentifier
                            ?? identifier.map { "\($0).title" } ?? "statusBanner.title")
                    if let message {
                        Text(message)
                            .font(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.message)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(messageIdentifier
                                ?? identifier.map { "\($0).message" } ?? "statusBanner.message")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let actionTitle, let onAction {
                    Button(action: onAction) {
                        Text(actionTitle)
                            .font(GoFlyFont.subheadlineEmphasis)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 56, minHeight: 32)
                            .background(GoFlyStyle.toastActionSurface, in: Capsule())
                            .overlay { Capsule().strokeBorder(GoFlyStyle.toastActionBorder.opacity(colorScheme == .dark ? 1 : 0.45), lineWidth: 0.5) }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(actionEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
                    .disabled(!actionEnabled)
                    .accessibilityIdentifier(actionIdentifier
                        ?? identifier.map { "\($0).action" } ?? "statusBanner.action")
                }

                if onDismiss != nil || isFloating {
                    Button(action: {
                        if let onDismiss {
                            onDismiss()
                        } else {
                            isDismissedLocally = true
                        }
                    }) {
                        Image(systemName: GoFlySymbols.close)
                            .goFlyControlSymbol(size: 13, maximum: 16, weight: .semibold)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("common.dismiss"))
                    .accessibilityIdentifier(identifier.map { "\($0).dismiss" } ?? "statusBanner.dismiss")
                    .padding(.horizontal, -6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(tone.toastSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tone.tint.opacity(colorScheme == .dark ? 1 : 0.35), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(identifier ?? "statusBanner")
        }
    }
}

/// Maps an error key to its one toast button (see `IssueCatalog`). The caller
/// passes only the handlers it owns; an action without a handler shows no button.
@MainActor
func goFlyIssueButton(for key: String, retry: (() -> Void)? = nil, settings: (() -> Void)? = nil,
                      chooseFile: (() -> Void)? = nil) -> (title: String?, action: (() -> Void)?) {
    guard let issue = IssueCatalog.info(for: key).action else { return (nil, nil) }
    let handler: (() -> Void)?
    switch issue {
    case .retry: handler = retry
    case .settings: handler = settings
    case .chooseFile: handler = chooseFile
    }
    guard let handler else { return (nil, nil) }
    return (goFlyString(issue.localizationKey), handler)
}
