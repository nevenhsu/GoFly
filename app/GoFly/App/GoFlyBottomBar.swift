import GoFlyCore
import SwiftUI

/// Three equal-width mode tabs (plan 3). Hidden entirely in execution mode and
/// on full-screen pages; switching tabs only changes what is browsed.
struct GoFlyBottomBar: View {
    @Binding var selection: SessionMapMode
    var bottomInset: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionMapMode.allCases, id: \.self) { mode in
                Button {
                    selection = mode
                } label: {
                    VStack(spacing: 3) {
                        GoFlyTabIcon(mode: mode, selected: selection == mode, size: 22)
                        Text(goFlyString("mode.\(mode.rawValue)"))
                            .font(.caption2.weight(selection == mode ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .foregroundStyle(selection == mode ? GoFlyStyle.primary : GoFlyStyle.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("mode.\(mode.rawValue)"))
                .accessibilityAddTraits(selection == mode ? .isSelected : [])
                .accessibilityIdentifier("mode.\(mode.rawValue)")
            }
        }
        .padding(.bottom, bottomInset)
        .overlay(alignment: .top) { Divider() }
        .background(GoFlyStyle.cardSurface.ignoresSafeArea(edges: .bottom))
        // Chrome caps Dynamic Type the way UIKit tab bars do; the labels stay
        // legible and equal-width even at accessibility sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goFlyString("mode.title"))
        .accessibilityIdentifier("map.bottomBar")
    }

    private func symbol(for mode: SessionMapMode) -> String {
        switch mode {
        case .teleport: "mappin.circle"
        case .route: GoFlySymbols.route
        case .joystick: GoFlySymbols.joystick
        }
    }
}
