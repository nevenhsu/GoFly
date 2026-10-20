import GoFlyCore
import SwiftUI

/// Three equal-width mode tabs (plan 3). Hidden entirely in execution mode and
/// on full-screen pages; switching tabs only changes what is browsed.
struct GoFlyBottomBar: View {
    @Binding var selection: SessionMapMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionMapMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol(for: mode))
                            .font(.system(size: 20, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(goFlyString("mode.\(mode.rawValue)"))
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(selection == mode ? GoFlyStyle.primary : GoFlyStyle.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("mode.\(mode.rawValue)"))
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityIdentifier("mode.\(mode.rawValue)")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 18)
        .padding(.horizontal, 8)
        .background(GoFlyStyle.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(GoFlyStyle.border)
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
        // Chrome caps Dynamic Type the way UIKit tab bars do; the labels stay
        // legible and equal-width even at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goFlyString("mode.title"))
        .accessibilityIdentifier("map.bottomBar")
    }

    private func symbol(for mode: SessionMapMode) -> String {
        switch mode {
        case .teleport: GoFlySymbols.place
        case .route: GoFlySymbols.route
        case .joystick: GoFlySymbols.manualMovement
        }
    }
}
