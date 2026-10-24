import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @EnvironmentObject private var favoriteRoutes: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    /// 結束 asks the owner to show the D6.a confirmation over the whole screen.
    var onRequestEnd: () -> Void = { }
    /// Called after a row was cleared or deleted, so the owner can offer the D9 undo snackbar.
    var onNodeRemoved: () -> Void = { }
    var onSettings: () -> Void = { }
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    var currentLocationAvailable: Bool? = nil
    var currentRouteOrigin: @MainActor () -> GeoCoordinate? = { nil }
    var isNarrow: Bool = false
    var onExpand: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var listContentHeight: CGFloat = 120
    @State private var showingDetails = false
    @State private var showingImports = false
    @State private var showingAllPoints = false
    @State private var showingFavoriteRoutes = false
    @State private var showingSaveFavorite = false
    @State private var visibleScrollFrame: CGRect = .zero
    @ScaledMetric(relativeTo: .footnote) private var addFontSize: CGFloat = 14

    var body: some View {
        Group {
            if isNarrow && controller.phase == .editing {
                narrowView
            } else if controller.phase == .editing {
                editingView
            } else {
                executionPanel
            }
        }
        .accessibilityHidden(showingDetails || showingImports || showingAllPoints || showingFavoriteRoutes || showingSaveFavorite)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel")
        .sheet(isPresented: $showingImports) {
            GoFlyImportedRoutesView(controller: controller, onLoaded: { showingImports = false }, onFocusPoint: { coordinate in
                showingImports = false
                onFocusPoint(coordinate)
            })
        }
        .sheet(isPresented: $showingAllPoints) {
            if let source = controller.draft.gpxSource {
                NavigationStack {
                    GoFlyGPXPointsView(document: source.document, title: source.displayFilename, onFocus: onFocusPoint)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(goFlyString("common.back")) { showingAllPoints = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingDetails) {
            GoFlySpeedSheet(
                speed: controller.draft.speed,
                canEdit: controller.canEdit,
                onSpeedChanged: { _ = controller.setSpeed($0) },
                onDismiss: { showingDetails = false }
            )
        }
        .fullScreenCover(isPresented: $showingFavoriteRoutes) {
            GoFlyFavoriteRoutesView(controller: controller) { showingFavoriteRoutes = false }
        }
        .sheet(isPresented: $showingSaveFavorite) {
            GoFlySaveFavoriteRouteView(controller: controller, currentLocationAvailable: currentLocationAvailable,
                                      currentRouteOrigin: currentRouteOrigin) { showingSaveFavorite = false }
        }
        .onChange(of: controller.canEdit) { _, canEdit in
            if !canEdit {
                showingDetails = false
                showingImports = false
                showingAllPoints = false
                showingFavoriteRoutes = false
                showingSaveFavorite = false
            }
        }
    }

    /// Figma D1/D2: header 12 pt below the sheet top, list card, add / reverse row,
    /// star + Start row, 35 pt above the tab bar. Only the list scrolls (D2: up to 4 rows).
    private var editingView: some View {
        VStack(alignment: .leading, spacing: 0) {
            editingHeader
                .padding(.bottom, 12)
            if let imported = controller.draft.gpxSource {
                importedContent(imported)
            } else {
                routeListCard
                routeActionRow
                    .padding(.top, 4)
            }
            startControl
                .padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 35)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel.content")
    }

    private var isRouteUsable: Bool {
        controller.canStart &&
        controller.error == nil &&
        controller.plannedRoute != nil &&
        (currentLocationAvailable != false || !controller.draft.nodes.contains(where: { $0.value == .current }))
    }

    private var startControl: some View {
        HStack(spacing: 12) {
            favoriteStarButton
            Button { _ = controller.start() } label: {
                HStack(spacing: 8) {
                    Image(systemName: GoFlySymbols.play)
                    Text(goFlyString("route.startShort"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(!isRouteUsable)
            .accessibilityIdentifier("route.start")
        }
    }

    private var favoriteStarButton: some View {
        Button {
            if let matching = matchingFavoriteRecord {
                Task {
                    await favoriteRoutes.delete(matching.id)
                    controller.setLoadedFavoriteRecordID(nil)
                }
            } else {
                showingSaveFavorite = true
            }
        } label: {
            GoFlyStarIcon(size: 20, filled: isFavorite)
                .foregroundStyle(GoFlyStyle.primary)
                .frame(width: GoFlyStyle.primaryButtonHeight, height: GoFlyStyle.primaryButtonHeight)
                .background(GoFlyStyle.startSecondarySurface, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(goFlyString(isFavorite ? "favoriteRoutes.remove" : "favoriteRoutes.add"))
        .accessibilityIdentifier("route.favorite.toggle")
    }

    private var matchingFavoriteRecord: FavoriteRouteRecord? {
        if let id = controller.loadedFavoriteRecordID,
           let record = favoriteRoutes.records.first(where: { $0.id == id }) {
            return record
        }
        if let gpx = controller.draft.gpxSource {
            return favoriteRoutes.records.first { record in
                record.sourceKind == .gpx &&
                record.displayFilename == gpx.displayFilename &&
                record.count == gpx.document.pointCount
            }
        } else if controller.draft.nodes.count >= 2 {
            let places = controller.draft.nodes.compactMap { node -> MapPlace? in
                if case .place(let p) = node.value { return p } else { return nil }
            }
            if places.count == controller.draft.nodes.count,
               let first = places.first, let last = places.last {
                return favoriteRoutes.records.first { record in
                    record.sourceKind == .manual &&
                    record.count == places.count &&
                    record.start == first.coordinate &&
                    record.end == last.coordinate
                }
            }
        }
        return nil
    }

    private var isFavorite: Bool {
        matchingFavoriteRecord != nil
    }

    private var executionPanel: some View {
        VStack(spacing: 14) {
            if [.planning, .preparing, .pausing, .cancelling].contains(controller.phase) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(goFlyString("route.phase.\(controller.phase.rawValue)"))
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            } else if controller.phase == .paused || controller.phase == .interrupted {
                GoFlyResumePanel(
                    title: controller.pausedPanelTitle,
                    subtitle: controller.pausedPanelSubtitle,
                    ctaTitle: goFlyString("route.resumeShort"),
                    onResume: { _ = controller.resume() },
                    isEnabled: controller.canResume,
                    identifier: "route.resumePanel"
                )
            } else if controller.phase == .unknown {
                HStack(spacing: 12) {
                    settingsButton
                    cancelButton
                }
                .padding(.bottom, 16)
            } else {
                GoFlyRouteRunningControls(
                    title: goFlyString(controller.roundTripEnabled ? "route.position" : "route.progress"),
                    fraction: controller.progress?.fraction ?? 0,
                    isRoundTrip: controller.roundTripEnabled,
                    isReversed: controller.heading == .reverse,
                    speed: controller.draft.speed.kilometersPerHour,
                    canToggleRoundTrip: controller.canSetRoundTrip,
                    canToggleDirection: controller.canToggleHeading,
                    canChangeSpeed: controller.canEdit,
                    isPaused: controller.phase == .paused,
                    canPlayback: controller.phase == .paused ? controller.canResume : controller.canPause,
                    canEnd: controller.canCancel,
                    onToggleRoundTrip: { _ = controller.setRoundTripEnabled(!controller.roundTripEnabled) },
                    onToggleDirection: { _ = controller.toggleHeading() },
                    onSpeedTap: { showingDetails = true },
                    onPlayback: {
                        if controller.phase == .paused { _ = controller.resume() } else { _ = controller.pause() }
                    },
                    onEnd: onRequestEnd
                )
            }
        }
        .padding(.horizontal, 20)
        // Figma D6: the label row starts 22 pt below the panel top; the safe area supplies the bottom 34 pt.
        .padding(.top, 22)
        .frame(maxWidth: .infinity)
        .background(GoFlyStyle.cardSurface)
        .overlay(alignment: .top) {
            Capsule().fill(GoFlyStyle.border).frame(width: 36, height: 5).padding(.top, 6)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("route.panel.content")
    }

    private var narrowView: some View {
        HStack(spacing: 8) {
            Button(action: { onExpand?() }) {
                Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(GoFlyStyle.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route.heading")

            Spacer(minLength: 8)

            headerButton(identifier: "route.favoriteRoutes",
                         label: goFlyString("favoriteRoutes.title"), enabled: controller.canEdit) {
                showingFavoriteRoutes = true
            } icon: { GoFlyStarIcon(size: 18, filled: false) }

            headerButton(identifier: "route.importedRoutes",
                         label: goFlyString("imports.title"), enabled: controller.canEdit) {
                showingImports = true
            } icon: { GoFlyRouteFolderIcon(size: 20) }
        }
        .padding(.bottom, 20)
        .padding(.horizontal, 20)
        .background(GoFlyStyle.cardSurface)
        .contentShape(Rectangle())
        .onTapGesture { onExpand?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel.narrow")
    }

    private var editingHeader: some View {
        HStack(spacing: 8) {
            Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier(controller.draft.gpxSource == nil ? "route.heading" : "route.importedSummary")
            Spacer(minLength: 8)
            headerButton(identifier: "route.favoriteRoutes",
                         label: goFlyString("favoriteRoutes.title"), enabled: controller.canEdit) {
                showingFavoriteRoutes = true
            } icon: { GoFlyStarIcon(size: 18, filled: false) }
            headerButton(identifier: "route.importedRoutes",
                         label: goFlyString("imports.title"), enabled: controller.canEdit) {
                showingImports = true
            } icon: { GoFlyRouteFolderIcon(size: 20) }
        }
        .padding(.trailing, 4)
    }

    private func importedContent(_ imported: GPXRouteSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GoFlyGPXPointList(points: imported.document.segments.flatMap { $0 }, summarized: true,
                               onFocus: onFocusPoint, onShowAll: { showingAllPoints = true })
            Button(action: { _ = controller.clearImportedRoute() }) {
                Label(goFlyString("route.clearRoute"), systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route.clearImported")
        }
    }

    /// Rows are 60 pt; the card shows at most four before the list scrolls.
    private static let visibleRows = 4
    private static let rowHeight: CGFloat = 60
    /// Everything in the editing panel except the list: header, gaps, action row, Start row and bottom inset.
    private static let panelChrome: CGFloat = 207

    private var listHeight: CGFloat {
        let cap = min(Self.rowHeight * CGFloat(Self.visibleRows), max(Self.rowHeight, maximumHeight - Self.panelChrome))
        return min(listContentHeight, cap)
    }

    private var routeListCard: some View {
        ScrollViewReader { proxy in
            ScrollView {
                GoFlyRouteNodeList(
                    draft: controller.draft, selectedID: controller.selectedNodeID,
                    isEditable: controller.canEdit, viewport: visibleScrollFrame,
                    onEdit: onEditNode,
                    onDelete: { if controller.removeNode(id: $0) { onNodeRemoved() } },
                    onMove: { _ = controller.moveNode(id: $0, toIndex: $1) },
                    onScroll: { id, anchor in
                        withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
                    }
                )
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listContentHeight = $0 }
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.nodes.card")
    }

    private var routeActionRow: some View {
        HStack(spacing: 16) {
            Button { _ = controller.openNewPicker() } label: {
                Label(goFlyString("route.addStop"), systemImage: GoFlySymbols.add)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 40, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(controller.canAddNode ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .disabled(!controller.canAddNode)
            .accessibilityIdentifier("route.addNode")
            .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount ? goFlyString("route.nodeLimit") : "")
            Spacer(minLength: 0)
            Button(action: { _ = controller.reverseNodes() }) {
                Label(goFlyString("route.exchange"), systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canEdit || controller.draft.nodes.count < 2)
            .accessibilityIdentifier("route.exchange")
        }
    }

    private func headerButton<Icon: View>(identifier: String, label: String,
                              enabled: Bool, action: @escaping () -> Void,
                              @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .frame(width: 44, height: 44)
                .background(GoFlyStyle.secondarySurface, in: Circle())
                .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var cancelButton: some View {
        Button(action: onRequestEnd) {
            Label(goFlyString("execution.end"), systemImage: GoFlySymbols.close)
        }
        .buttonStyle(GoFlyActionStyle())
        .frame(width: 120)
        .disabled(!controller.canCancel)
        .accessibilityIdentifier("route.cancel")
    }

    private var settingsButton: some View {
        Button(goFlyString("operation.settings"), action: onSettings)
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("route.settings")
    }



}

private struct GoFlyRoundTripControl: View {
    @ObservedObject var controller: RouteExecutionController

    var body: some View {
        Button {
            _ = controller.setRoundTripEnabled(!controller.roundTripEnabled)
        } label: {
            HStack(spacing: 6) {
                GoFlyRoundTripIcon(enabled: controller.roundTripEnabled, size: 14)
                Text(goFlyString("route.roundTripShort"))
                    .font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(controller.roundTripEnabled ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
            .overlay { if !controller.roundTripEnabled { Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 0.75) } }
            .contentShape(Capsule())
            .foregroundStyle(!controller.canSetRoundTrip ? GoFlyStyle.disabledForeground
                             : (controller.roundTripEnabled ? GoFlyStyle.surface : GoFlyStyle.primary))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(!controller.canSetRoundTrip)
        .accessibilityValue(controller.roundTripEnabled ? "1" : "0")
        .accessibilityHint(goFlyString("route.roundTripHint"))
        .accessibilityIdentifier("route.roundTrip")
    }
}
