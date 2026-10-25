import SwiftUI

/// Figma D6.a: a centered confirmation over a 35% scrim. The scrim blocks the map
/// and panel underneath, and VoiceOver focus stays inside the dialog.
struct GoFlyEndRouteDialog: View {
    var onCancel: () -> Void
    var onConfirm: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .accessibilityHidden(true)
            VStack(spacing: 0) {
                Text(goFlyString("route.cancelConfirmation.title"))
                    .font(GoFlyFont.headline)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("route.end.dialog.title")
                Text(goFlyString("route.cancelConfirmation.message"))
                    .font(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.message)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .accessibilityIdentifier("route.end.dialog.message")
                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text(goFlyString("route.cancelConfirmation.return"))
                            .font(GoFlyFont.bodyEmphasis)
                            .foregroundStyle(GoFlyTextColor.primary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(GoFlyStyle.dialogCancelSurface, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("route.end.dialog.cancel")
                    Button(action: onConfirm) {
                        Text(goFlyString("route.cancelConfirmation.confirm"))
                            .font(GoFlyFont.bodyEmphasis)
                            .foregroundStyle(GoFlyTextColor.onDark)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(GoFlyStyle.danger, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("route.end.dialog.confirm")
                }
                .padding(.top, 16)
            }
            .padding(20)
            .frame(maxWidth: 320)
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.18), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("route.end.dialog")
        }
        .transition(.opacity)
    }
}
