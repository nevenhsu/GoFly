import GoFlyCore
import SwiftUI

/// Full-screen route inspection. The rows intentionally reuse the planning
/// panel's list so selection, search, clearing and reordering stay identical.
struct GoFlyRouteListView: View {
    @ObservedObject var controller: RouteExecutionController
    var onEditNode: (RouteNodeID) -> Void
    var onDismiss: () -> Void

    @State private var contentHeight: CGFloat = 120
    @State private var footerHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            header

            // The card grows with its rows and only scrolls once it fills the page.
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        GoFlyRouteNodeCard(controller: controller, proxy: proxy,
                                           height: min(contentHeight, max(60, geometry.size.height - footerHeight)),
                                           onEditNode: onEditNode,
                                           onContentHeightChange: { contentHeight = $0 })
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("route.list.nodes")

                        footer(using: proxy)
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { footerHeight = $0 }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .background(GoFlyStyle.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.list")
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onDismiss) {
                    Label(goFlyString("common.back"), systemImage: GoFlySymbols.back)
                        .font(GoFlyFont.body)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoFlyTextColor.primary)
                .accessibilityIdentifier("route.list.back")
                Spacer(minLength: 0)
                Color.clear.frame(width: 64, height: 44)
            }

            Text(goFlyString("route.list.title"))
                .font(GoFlyFont.headline)
                .foregroundStyle(GoFlyTextColor.primary)
                .accessibilityIdentifier("route.list.title")
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    /// Same small text buttons as the planning panel's action row: add on the left, reverse on the right.
    private func footer(using proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 16) {
            Button {
                addWaypoint(using: proxy)
            } label: {
                Label(goFlyString("route.addStop"), systemImage: GoFlySymbols.add)
            }
            .buttonStyle(GoFlyRouteTextButtonStyle())
            .disabled(!controller.canAddNode)
            .accessibilityIdentifier("route.list.addWaypoint")
            .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount
                ? goFlyString("route.nodeLimit") : "")

            Spacer(minLength: 0)

            Button {
                _ = controller.reverseNodes()
            } label: {
                Label(goFlyString("route.exchange"), systemImage: GoFlySymbols.swap)
            }
            .buttonStyle(GoFlyRouteTextButtonStyle())
            .disabled(!controller.canEdit || controller.draft.nodes.count < 2)
            .accessibilityIdentifier("route.list.reverse")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
