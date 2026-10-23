import SwiftUI
import UIKit

/// A one-off result that needs no user decision. It disappears after about two
/// seconds; anything the person must act on belongs in `GoFlyStatusBanner`.
struct GoFlySnackbarMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?
}

struct GoFlySnackbar: View {
    let message: GoFlySnackbarMessage
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: GoFlySymbols.successFilled)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.204, green: 0.780, blue: 0.349))
                .accessibilityHidden(true)
            Text(message.text)
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.snackbarForeground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = message.actionTitle, let action = message.action {
                Button {
                    action()
                    onDismiss()
                } label: {
                    Text(actionTitle)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GoFlyStyle.snackbarForeground)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("snackbar.action")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(GoFlyStyle.snackbarSurface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
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
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    GoFlySnackbar(message: message) { self.message = nil }
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: message.id) {
                            try? await Task.sleep(for: duration)
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
                       duration: Duration = .seconds(2)) -> some View {
        modifier(GoFlySnackbarModifier(message: message, bottomPadding: bottomPadding, duration: duration))
    }
}
