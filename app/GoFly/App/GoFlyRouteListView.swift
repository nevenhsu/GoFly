import GoFlyCore
import SwiftUI

/// D23 full-screen route overview. The rows show route order and role while
/// preserving the existing tap-to-select/edit behavior from the route planner.
struct GoFlyRouteListView: View {
    @ObservedObject var controller: RouteExecutionController
    var onEditNode: (RouteNodeID) -> Void
    var onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        routeCard
                        footer(using: proxy)
                            .padding(.top, 8)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GoFlyStyle.canvas)
        .goFlyPushedFullScreen()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.list")
    }

    private var header: some View {
        GoFlySheetHeader(title: goFlyString("route.list.title")) {
            Button(action: onDismiss) {
                GoFlyIconLabel(title: goFlyString("common.back"), icon: .chevronLeft)
                    .goFlyFont(GoFlyFont.body)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoFlyTextColor.accent)
            .accessibilityIdentifier("route.list.back")
        } trailing: {
            EmptyView()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var routeCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(controller.draft.nodes.enumerated()), id: \.element.id) { index, node in
                GoFlyListRow(
                    minimumHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 46,
                    separatorLeadingInset: index < controller.draft.nodes.count - 1 ? 16 : nil,
                    separatorTrailingInset: 16
                ) {
                    Button { onEditNode(node.id) } label: {
                        HStack(spacing: 24) {
                            Text("\(index + 1)")
                                .goFlyFont(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .frame(width: 24, alignment: .leading)

                            Group {
                                if dynamicTypeSize.isAccessibilitySize {
                                    VStack(alignment: .leading, spacing: 4) {
                                        locationText(node.value)
                                        roleText(node.id)
                                    }
                                } else {
                                    HStack(spacing: 8) {
                                        locationText(node.value)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        roleText(node.id)
                                            .multilineTextAlignment(.trailing)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity,
                               minHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 46,
                               alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(index + 1), \(locationTitle(node.value)), \(goFlyRouteRoleTitle(controller.draft.role(of: node.id) ?? .start))")
                    .accessibilityHint(goFlyString("route.fieldSearchHint"))
                    .accessibilityIdentifier("route.list.location.\(node.id.rawValue.uuidString)")
                }
                .id(node.id)
            }
        }
        .background(GoFlyStyle.cardSurface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.routeListCardRadius, style: .continuous)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.list.nodes")
    }

    /// Figma D23: the two planning actions sit directly below the location card.
    @ViewBuilder
    private func footer(using proxy: ScrollViewProxy) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                addWaypointButton(using: proxy)
                reverseButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        } else {
            HStack(spacing: 16) {
                addWaypointButton(using: proxy)
                Spacer(minLength: 0)
                reverseButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func addWaypointButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            addWaypoint(using: proxy)
        } label: {
            HStack(spacing: 6) {
                Text("＋")
                Text(goFlyString("route.addStop"))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(GoFlyRouteTextButtonStyle())
        .disabled(!controller.canAddNode)
        .accessibilityIdentifier("route.list.addWaypoint")
        .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount
            ? goFlyString("route.nodeLimit") : "")
    }

    private var reverseButton: some View {
        Button { _ = controller.reverseNodes() } label: {
            GoFlyIconLabel(title: goFlyString("route.exchange"), icon: GoFlySymbols.swap)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(GoFlyRouteTextButtonStyle())
        .disabled(!controller.canEdit || controller.draft.nodes.count < 2)
        .accessibilityIdentifier("route.list.reverse")
    }

    private func locationText(_ value: RouteNodeValue) -> some View {
        Text(locationTitle(value))
            .goFlyFont(GoFlyFont.body)
            .foregroundStyle(GoFlyTextColor.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func roleText(_ nodeID: RouteNodeID) -> some View {
        Text(goFlyRouteRoleTitle(controller.draft.role(of: nodeID) ?? .start))
            .goFlyFont(GoFlyFont.footnote)
            .foregroundStyle(GoFlyTextColor.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func locationTitle(_ value: RouteNodeValue) -> String {
        switch value {
        case .current: goFlyString("route.currentLocation")
        case .place(let place): place.title
        case .empty: goFlyString("route.chooseDestination")
        }
    }

    private func addWaypoint(using proxy: ScrollViewProxy) {
        let existingIDs = Set(controller.draft.nodes.map(\.id))
        guard controller.addEmptyWaypoint(),
              let newID = controller.draft.nodes.first(where: { !existingIDs.contains($0.id) })?.id else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newID, anchor: .bottom) }
        }
    }
}
