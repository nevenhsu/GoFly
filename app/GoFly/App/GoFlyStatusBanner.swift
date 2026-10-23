import SwiftUI

/// The single status presentation for the redesign (plan 4.11).
///
/// Severity is conveyed by icon + text + color. The banner sits at the top of a
/// sheet or execution panel, shows at most one primary action, and carries a
/// close button only when the caller allows dismissal. Repair guidance belongs
/// in `message`, not in a separate block lower on the screen.
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

    var body: some View {
        if !isDismissedLocally {
            HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tone.tint)
                .padding(.top, 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("\(goFlyString(tone.accessibilityKey)), \(title)")
                    .accessibilityIdentifier(titleIdentifier
                        ?? identifier.map { "\($0).title" } ?? "statusBanner.title")
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(messageIdentifier
                            ?? identifier.map { "\($0).message" } ?? "statusBanner.message")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(GoFlyStyle.surface, in: Capsule())
                        .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoFlyStyle.primary)
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
                        .foregroundStyle(GoFlyStyle.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("common.dismiss"))
                .accessibilityIdentifier(identifier.map { "\($0).dismiss" } ?? "statusBanner.dismiss")
                .padding(.trailing, -4)
            }
        }
        .padding(12)
        .background(isFloating ? GoFlyStyle.cardSurface : tone.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if isFloating {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(isFloating ? 0.12 : 0), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier ?? "statusBanner")
        }
    }
}
