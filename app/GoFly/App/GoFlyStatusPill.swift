import SwiftUI

/// Compact current-state pill under the floating search bar (plan 3).
/// Tapping expands the details in the active sheet; the color always matches
/// the banner tone of the same state.
struct GoFlyStatusPill: View {
    let text: String
    let tone: GoFlyStatusTone
    var action: (() -> Void)?
    var identifier: String = "map.statusPill"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let action {
            Button(action: action) { label }
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
        HStack(spacing: 8) {
            Circle()
                .fill(tone.pillDot)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .font(GoFlyFont.footnoteEmphasis)
                .foregroundStyle(GoFlyTextColor.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(GoFlyStyle.pillSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(GoFlyStyle.pillBorder, lineWidth: colorScheme == .dark ? 1 : 0.5)
                .allowsHitTesting(false)
        }
        .goFlyShadow(.floating)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
