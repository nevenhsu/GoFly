import SwiftUI

/// Unified Warning Toast for interruption recovery (Resume UI - B8, D4, E3).
///
/// Features:
/// - 100% solid warm amber background `#FFF6E6` (dark `#2C1E0A`) + 1 pt solid amber border `#FF9500`.
/// - Height 80 pt comfortable for 2-line description without squeezing.
/// - Left: alert triangle symbol.
/// - Center: Title (14 pt Semibold) and message (12 pt Regular).
/// - Right: White capsule "重試" button (13 pt Semibold) + ✕ dismiss button.
struct GoFlyWarningToast: View {
    let title: String
    let message: String
    var retryTitle: String = "重試"
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var retryEnabled: Bool = true
    var identifier: String = "warningToast"

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 255/255, green: 149/255, blue: 0/255))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("\(identifier).title")

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(GoFlyStyle.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(identifier).message")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                if let onRetry {
                    Button(action: onRetry) {
                        Text(retryTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(retryEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .background(Color.white, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color(red: 198/255, green: 198/255, blue: 200/255).opacity(0.45), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!retryEnabled)
                    .accessibilityIdentifier("\(identifier).retry")
                }

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(GoFlyStyle.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("common.dismiss"))
                    .accessibilityIdentifier("\(identifier).dismiss")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 80)
        .background(
            colorScheme == .dark
                ? Color(red: 44/255, green: 30/255, blue: 10/255)
                : Color(red: 255/255, green: 246/255, blue: 230/255),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 255/255, green: 149/255, blue: 0/255), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
