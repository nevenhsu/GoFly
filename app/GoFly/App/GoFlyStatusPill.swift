import SwiftUI

/// Compact current-state pill under the floating search bar (plan 3).
/// Tapping expands the details in the active sheet; the color always matches
/// the banner tone of the same state.
struct GoFlyStatusPill: View {
    let text: String
    let tone: GoFlyStatusTone
    var action: (() -> Void)?
    var identifier: String = "map.statusPill"

    var body: some View {
        if let action {
            Button(action: action) {
                // Keep the Figma capsule at 30 pt while giving the button
                // the required 44 pt accessibility hit target. A flexible
                // clear layer here expands to the full map height inside a
                // ZStack, which also corrupts the top inset used by Toasts.
                label
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(goFlyString("map.statusPill.hint"))
            .accessibilityIdentifier(identifier)
        } else {
            label
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.pillDot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .goFlyFont(GoFlyFont.footnoteEmphasis)
                .foregroundStyle(GoFlyTextColor.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 30)
        .background(GoFlyStyle.pillSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(GoFlyStyle.pillBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .goFlyShadow(tone.pillUsesFloatingShadow ? .floating : nil)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
