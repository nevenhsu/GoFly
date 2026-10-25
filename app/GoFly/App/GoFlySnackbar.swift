import SwiftUI
import UIKit

/// A one-off result. Plain messages disappear after about two seconds; one with
/// an action (undo) stays about five. Anything that blocks the person belongs in
/// `GoFlyStatusBanner`. `bottomPadding` places it above the sheet or button.
struct GoFlySnackbarMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    /// Figma `Snackbar / 2 秒自動消失` vs `Snackbar / 可復原` (about 5 seconds).
    var defaultDuration: Duration { action == nil ? .seconds(2) : .seconds(5) }
}

struct GoFlySnackbar: View {
    let message: GoFlySnackbarMessage
    var onDismiss: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: GoFlySymbols.successFilled)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(GoFlyStyle.success)
                .accessibilityHidden(true)
            Text(message.text)
                .font(GoFlyFont.subheadlineEmphasis)
                .foregroundStyle(GoFlyTextColor.onDark)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = message.actionTitle, let action = message.action {
                Button {
                    action()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                        .font(GoFlyFont.subheadlineEmphasis)
                        .lineLimit(1)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 56, minHeight: 32)
                        .background(colorScheme == .dark ? Color(white: 0.227) : Color.white, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(
                                colorScheme == .dark ? Color.white.opacity(0.18) : GoFlyStyle.toastActionBorder.opacity(0.45),
                                lineWidth: colorScheme == .dark ? 1 : 0.5)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snackbar.action")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .background(GoFlyStyle.snackbarSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if colorScheme == .dark {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.09), radius: 12, x: 0, y: 5)
        .shadow(color: .black.opacity(0.06), radius: 1.5, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("snackbar")
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: message.text)
        }
    }
}

private struct GoFlySnackbarModifier: ViewModifier {
    @Binding var message: GoFlySnackbarMessage?
    let bottomPadding: CGFloat
    let duration: Duration?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    GoFlySnackbar(message: message) { self.message = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(for: duration ?? message.defaultDuration)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.2)) { self.message = nil }
                        }
                }
            }
            .animation(.easeOut(duration: 0.2), value: message?.id)
    }
}

extension View {
    func goFlySnackbar(_ message: Binding<GoFlySnackbarMessage?>,
                       bottomPadding: CGFloat = 12,
                       duration: Duration? = nil) -> some View {
        modifier(GoFlySnackbarModifier(message: message, bottomPadding: bottomPadding, duration: duration))
    }
}
