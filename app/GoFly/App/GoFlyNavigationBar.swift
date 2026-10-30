import GoFlyCore
import SwiftUI
import UIKit

/// Standard leading back button for native page navigation and modal sheet navigation.
/// Displays a chevron icon with the destination/back title in accent blue (`GoFlyTextColor.accent`).
struct GoFlyNavBackButton: View {
    let title: String
    var action: (() -> Void)? = nil
    var identifier: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if let action { action() } else { dismiss() }
        } label: {
            HStack(spacing: 6) {
                GoFlyIcon(GoFlySymbols.back, size: 18)
                Text(title)
                    .goFlyFont(GoFlyFont.body)
            }
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(GoFlyTextColor.accent)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier ?? "nav.back")
    }
}

/// Standard text action button for native page navigation and modal sheet navigation.
struct GoFlyNavActionButton: View {
    let title: String
    var isEnabled: Bool = true
    var isProminent: Bool = false
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .goFlyFont(isProminent ? GoFlyFont.headline : GoFlyFont.body)
                .foregroundStyle(isEnabled ? GoFlyTextColor.accent : GoFlyTextColor.disabled)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(identifier ?? "nav.action")
    }
}

/// Unified native navigation bar modifier for pushed pages in NavigationStack (分頁 nav).
/// - Enforces title centered (`ToolbarItem(placement: .principal)`)
/// - Unified leading back button and trailing action button
/// - Native bar background with `GoFlyStyle.canvas`
/// - Interactive edge swipe back gesture supported via `GoFlyEdgeSwipeBack`
struct GoFlyNativeNavBarModifier<Leading: View, Trailing: View>: ViewModifier {
    let title: String?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(GoFlyStyle.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    leading()
                }
                if let title {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .goFlyFont(GoFlyFont.headline)
                            .foregroundStyle(GoFlyTextColor.primary)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    trailing()
                }
            }
            .background(GoFlyEdgeSwipeBack().frame(width: 0, height: 0))
    }
}

extension View {
    /// Applies the unified native navigation bar for pushed pages (分頁 nav).
    func goFlyNativeNavBar<Leading: View, Trailing: View>(
        title: String?,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) -> some View {
        modifier(GoFlyNativeNavBarModifier(title: title, leading: leading, trailing: trailing))
    }

    /// Convenience for standard pushed pages with a back button and optional title.
    func goFlyNativeNavBar(
        title: String?,
        backTitle: String,
        onBack: (() -> Void)? = nil,
        backIdentifier: String? = nil
    ) -> some View {
        goFlyNativeNavBar(title: title) {
            GoFlyNavBackButton(title: backTitle, action: onBack, identifier: backIdentifier)
        } trailing: {
            EmptyView()
        }
    }
}

/// Unified modal sheet nav bar (sheet nav).
/// - Enforces title centered
/// - Unified leading & trailing buttons
/// - Responsive to Dynamic Type
struct GoFlySheetNavBar<Leading: View, Trailing: View>: View {
    var title: String?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    leading()
                    Spacer(minLength: 8)
                    trailing()
                }
                .frame(minHeight: 44)

                if let title {
                    Text(title)
                        .goFlyFont(GoFlyFont.headline)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 12) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
            .frame(minHeight: 44)
            .overlay {
                if let title {
                    Text(title)
                        .goFlyFont(GoFlyFont.headline)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 88)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }
}
