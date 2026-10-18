import GoFlyCore
import SwiftUI

@MainActor
func goFlyRouteRoleTitle(_ role: RouteNodeRole) -> String {
    switch role {
    case .start: goFlyString("route.origin")
    case .destination: goFlyString("route.destination")
    case .waypoint(let number): goFlyLocalizedFormat(goFlyString("route.waypoint"), number)
    }
}

@MainActor
func goFlyRouteEditTitle(_ role: RouteNodeRole) -> String {
    switch role {
    case .start: goFlyString("route.editOrigin")
    case .destination: goFlyString("route.editDestination")
    case .waypoint(let number): goFlyLocalizedFormat(goFlyString("route.editWaypoint"), number)
    }
}

struct GoFlyRouteNodeList: View {
    let draft: RouteDraft
    let isEditable: Bool
    let viewport: CGRect
    var onEdit: (RouteNodeID) -> Void
    var onDelete: (RouteNodeID) -> Void
    var onMove: (RouteNodeID, Int) -> Void
    var onScroll: (RouteNodeID, UnitPoint) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var gestureIsActive = false
    @State private var draggingID: RouteNodeID?
    @State private var originalOrder: [RouteNodeID] = []
    @State private var previewOrder: [RouteNodeID] = []
    @State private var rowFrames: [RouteNodeID: CGRect] = [:]
    @State private var listFrame: CGRect = .zero
    @State private var dragHeight: CGFloat = 72
    @State private var pointer = CGPoint.zero
    @State private var touchOffset: CGFloat = 0
    @State private var autoscroll: Task<Void, Never>?

    private var order: [RouteNodeID] { draft.nodes.map(\.id) }
    private var visibleOrder: [RouteNodeID] { draggingID == nil ? order : previewOrder }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleOrder.enumerated()), id: \.element) { index, id in
                if let node = draft.nodes.first(where: { $0.id == id }) {
                    row(node)
                        .opacity(draggingID == id ? 0 : 1)
                        .frame(height: draggingID == id ? dragHeight : nil)
                        .overlay {
                            if draggingID == id {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(GoFlyStyle.surface)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(GoFlyStyle.primary, lineWidth: 2)
                                    }
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityHidden(draggingID == id)
                    .id(id)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { rowFrames[id] = $0 }
                    if index < visibleOrder.count - 1 { Divider().padding(.horizontal, 12) }
                }
            }
        }
        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { listFrame = $0 }
        .overlay(alignment: .topLeading) {
            if let id = draggingID, let node = draft.nodes.first(where: { $0.id == id }) {
                row(node)
                    .frame(width: listFrame.width, height: dragHeight)
                    .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    .scaleEffect(1.02)
                    .position(x: listFrame.width / 2, y: pointer.y - touchOffset - listFrame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topLeading) { metrics }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.nodes.list")
        .onChange(of: rowFrames) { _, _ in updateProjection() }
        .onChange(of: gestureIsActive) { _, active in if !active { cancelDrag() } }
        .onChange(of: draft.nodes) { _, _ in cancelDrag() }
        .onChange(of: isEditable) { _, editable in if !editable { cancelDrag() } }
        .onChange(of: dynamicTypeSize) { _, _ in cancelDrag() }
        .onChange(of: viewport.width) { _, _ in cancelDrag() }
        .onDisappear { cancelDrag() }
    }

    private func row(_ node: RouteNode) -> some View {
        let role = draft.role(of: node.id) ?? .start
        return HStack(spacing: 0) {
            Image(systemName: GoFlySymbols.reorder)
                .goFlyControlSymbol(size: 18, weight: .semibold)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: node.id))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(goFlyLocalizedFormat(goFlyString("route.reorderNode"), goFlyRouteRoleTitle(role), title(node.value)))
                .accessibilityHint(goFlyString("route.dragHint"))
                .accessibilityAction(named: Text(goFlyString("route.moveUp"))) { move(node.id, by: -1) }
                .accessibilityAction(named: Text(goFlyString("route.moveDown"))) { move(node.id, by: 1) }
                .accessibilityAction(named: Text(goFlyLocalizedFormat(goFlyString("route.deleteNode"), goFlyRouteRoleTitle(role)))) {
                    if isEditable { onDelete(node.id) }
                }
                .accessibilityIdentifier("route.handle.\(node.id.rawValue.uuidString)")
            Button { if isEditable { onEdit(node.id) } } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyRouteRoleTitle(role)).font(.caption.weight(.medium)).foregroundStyle(GoFlyStyle.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    Text(title(node.value)).font(.body.weight(.semibold))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEditable || draggingID != nil)
            .accessibilityLabel(goFlyRouteEditTitle(role))
            .accessibilityValue(title(node.value))
            .accessibilityIdentifier(editIdentifier(role))
            Button { if isEditable { onDelete(node.id) } } label: {
                Image(systemName: GoFlySymbols.delete)
                    .goFlyControlSymbol(size: 18, weight: .regular)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEditable || draggingID != nil)
            .accessibilityLabel(goFlyLocalizedFormat(goFlyString("route.deleteNode"), goFlyRouteRoleTitle(role)))
            .accessibilityIdentifier("route.delete.\(node.id.rawValue.uuidString)")
        }
        .frame(minHeight: 72)
        .foregroundStyle(isEditable ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.row.\(node.id.rawValue.uuidString)")
    }

    private func dragGesture(for id: RouteNodeID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($gestureIsActive) { value, state, _ in
                if case .second(true, _) = value { state = true }
            }
            .onChanged { value in
                guard isEditable, case .second(true, let drag) = value, let drag else { return }
                if draggingID == nil { beginDrag(id, at: drag.startLocation) }
                guard draggingID == id else { return }
                pointer = drag.location
                updateProjection()
            }
            .onEnded { _ in finishDrag() }
    }

    private func beginDrag(_ id: RouteNodeID, at point: CGPoint) {
        guard let frame = rowFrames[id], isEditable else { return }
        originalOrder = order
        previewOrder = order
        dragHeight = frame.height
        touchOffset = point.y - frame.midY
        pointer = point
        draggingID = id
        autoscroll?.cancel()
        autoscroll = Task { @MainActor in
            while !Task.isCancelled, draggingID != nil {
                updateProjection()
                scrollAtEdge()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func updateProjection() {
        guard let id = draggingID, originalOrder == order else { return }
        let center = pointer.y - touchOffset
        let remaining = previewOrder.filter { $0 != id }
        let target = remaining.filter { other in rowFrames[other].map { $0.midY < center } ?? false }.count
        var next = remaining
        next.insert(id, at: min(target, next.count))
        if next != previewOrder { previewOrder = next }
    }

    private func scrollAtEdge() {
        guard viewport.height > 0, let id = draggingID else { return }
        let remaining = previewOrder.filter { $0 != id }
        let visible = remaining.indices.filter { index in
            rowFrames[remaining[index]].map { $0.intersects(viewport.insetBy(dx: 0, dy: 1)) } ?? false
        }
        if pointer.y > viewport.maxY - 40, let last = visible.last {
            if last + 1 < remaining.count { onScroll(remaining[last + 1], .bottom) }
            else if let frame = rowFrames[id], frame.maxY > viewport.maxY { onScroll(id, .bottom) }
        } else if pointer.y < viewport.minY + 40, let first = visible.first {
            if first > 0 { onScroll(remaining[first - 1], .top) }
            else if let frame = rowFrames[id], frame.minY < viewport.minY { onScroll(id, .top) }
        }
    }

    private func finishDrag() {
        guard let id = draggingID else { return }
        let target = previewOrder.firstIndex(of: id)
        let canCommit = isEditable && originalOrder == order && viewport.contains(pointer)
        cancelDrag()
        if canCommit, let target { onMove(id, target) }
    }

    private func cancelDrag() {
        autoscroll?.cancel()
        autoscroll = nil
        draggingID = nil
        originalOrder = []
        previewOrder = []
    }

    private func move(_ id: RouteNodeID, by offset: Int) {
        guard isEditable, draggingID == nil, let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return }
        onMove(id, index + offset)
    }

    private func title(_ value: RouteNodeValue) -> String {
        switch value { case .current: goFlyString("route.currentLocation"); case .place(let place): place.title }
    }
    private func editIdentifier(_ role: RouteNodeRole) -> String {
        switch role { case .start: "route.node.start"; case .destination: "route.node.destination"; case .waypoint(let n): "route.node.waypoint.\(n)" }
    }

    @ViewBuilder private var metrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            VStack {
                Text(draggingID?.rawValue.uuidString ?? "none").accessibilityIdentifier("route.nodes.dragging")
            }
            .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
        }
        #endif
    }
}
