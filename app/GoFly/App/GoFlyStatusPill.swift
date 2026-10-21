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
        HStack(spacing: 6) {
            Circle()
                .fill(tone.tint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(GoFlyStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 30)
        .background(GoFlyStyle.cardSurface, in: Capsule())
        .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .contentShape(Capsule())
    }
}
