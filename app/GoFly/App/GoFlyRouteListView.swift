import GoFlyCore
import SwiftUI

/// Full-screen route inspection. The rows intentionally reuse the planning
/// panel's list so selection, search, clearing and reordering stay identical.
struct GoFlyRouteListView: View {
    @ObservedObject var controller: RouteExecutionController
    var onEditNode: (RouteNodeID) -> Void
    var onDismiss: () -> Void

    @State private var visibleScrollFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView {
                        GoFlyRouteNodeList(
                            draft: controller.draft,
                            selectedID: controller.selectedNodeID,
                            isEditable: controller.canEdit,
                            viewport: visibleScrollFrame,
                            onEdit: onEditNode,
                            onDelete: { _ = controller.removeNode(id: $0) },
                            onMove: { _ = controller.moveNode(id: $0, toIndex: $1) },
                            onScroll: { id, anchor in
                                withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
                    .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("route.list.nodes")

                    footer(using: proxy)
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
                .foregroundStyle(GoFlyStyle.primary)
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

    private func footer(using proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 12) {
            Button {
                addWaypoint(using: proxy)
            } label: {
                Label(goFlyString("route.addStop"), systemImage: GoFlySymbols.add)
                    .lineLimit(1)
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(!controller.canAddNode)
            .accessibilityIdentifier("route.list.addWaypoint")
            .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount
                ? goFlyString("route.nodeLimit") : "")

            Button(action: onDismiss) {
                Label(goFlyString("route.closeInspection"), systemImage: GoFlySymbols.close)
                    .lineLimit(1)
            }
            .buttonStyle(GoFlyActionStyle())
            .accessibilityIdentifier("route.list.close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
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
