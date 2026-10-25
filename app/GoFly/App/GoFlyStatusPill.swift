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
                .strokeBorder(Color(red: 198/255, green: 198/255, blue: 200/255).opacity(0.45), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}
