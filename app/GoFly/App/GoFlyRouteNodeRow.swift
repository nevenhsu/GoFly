import GoFlyCore
import SwiftUI

/// The place text of a route row: current location, the place name, or the
/// role's placeholder. Shared by the route panel rows and the all-locations list.
@MainActor
func goFlyRouteNodeTitle(_ value: RouteNodeValue, role: RouteNodeRole) -> String {
    switch value {
    case .current: goFlyString("route.currentLocation")
    case .place(let place): place.title
    case .empty:
        switch role {
        case .start: goFlyString("route.chooseOrigin")
        case .destination: goFlyString("route.chooseDestination")
        case .waypoint(let number): goFlyLocalizedFormat(goFlyString("route.chooseWaypoint"), number)
        }
    }
}

/// Place text with the shared placeholder color: an empty row uses the lighter
/// disabled token, never the primary text color.
struct GoFlyRouteNodeTitleText: View {
    let value: RouteNodeValue
    let role: RouteNodeRole
    var lineLimit: Int? = 1

    var body: some View {
        Text(goFlyRouteNodeTitle(value, role: role))
            .goFlyFont(GoFlyFont.body)
            .foregroundStyle(value == .empty ? GoFlyTextColor.disabled : GoFlyTextColor.primary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: lineLimit == nil)
    }
}

/// The ✕ at the right end of a route row (44 pt target).
struct GoFlyRouteNodeDeleteButton: View {
    let label: String
    let identifier: String
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GoFlyIcon(GoFlySymbols.close)
                .goFlyIconSize(size: 15)
                .goFlyIconForeground(enabledColor: GoFlyTextColor.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}
