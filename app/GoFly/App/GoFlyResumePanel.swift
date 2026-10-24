import SwiftUI

/// 76 pt narrowest bottom panel for task interruption recovery (Resume UI - B8, D4, E3).
///
/// Features:
/// - Maximum map and location visibility (76 pt visible height).
/// - Shows interrupted state title on the left.
/// - Single primary "Resume" action button on the right (e.g., "恢復瞬移", "繼續路線", "恢復漫步").
struct GoFlyResumePanel: View {
    let title: String
    var subtitle: String? = nil
    let ctaTitle: String
    let onResume: () -> Void
    var isEnabled: Bool = true
    /// Panel height below the grabber: 64 inside a sheet (12 pt grabber), 88 when the panel owns the bottom (D10).
    var contentHeight: CGFloat = 76
    var identifier: String = "resumePanel"

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .lineLimit(1)
                    .accessibilityIdentifier("\(identifier).title")
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("\(identifier).subtitle")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onResume) {
                Text(ctaTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEnabled ? GoFlyStyle.surface : GoFlyStyle.disabledForeground)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledSurface, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityIdentifier("\(identifier).action")
        }
        .padding(.horizontal, 20)
        .frame(height: contentHeight - 12)
        .frame(height: contentHeight, alignment: .top)
        .background(GoFlyStyle.cardSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}
