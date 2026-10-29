import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @EnvironmentObject private var favoriteRoutes: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    @Binding var showingFavoriteRoutes: Bool
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    var onInspectRoute: () -> Void = { }
    /// Ending asks the owner to cancel the active route and return to planning.
    var onRequestEnd: () -> Void = { }
    var onSettings: () -> Void = { }
    /// A localization key for a floating error toast owned by the map screen.
    var onNotice: (String) -> Void = { _ in }
    /// 重試 on an interrupted route: repair the connection, then the route continues.
    var onRetryInterrupted: () -> Void = { }
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
    @State private var showingSaveFavorite = false
    @State private var editingFavorite: FavoriteRouteRecord?
    @State private var preparingFavoriteSave = false
    @ScaledMetric(relativeTo: .footnote) private var addFontSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var listIconSize: CGFloat = 20

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
                canEdit: controller.canSetSpeed,
                onSpeedChanged: { _ = controller.setSpeed($0) },
                onDismiss: { showingDetails = false }
            )
        }
        .sheet(isPresented: $showingSaveFavorite) {
            GoFlySaveFavoriteRouteView(controller: controller, currentLocationAvailable: currentLocationAvailable,
                                      currentRouteOrigin: currentRouteOrigin) { showingSaveFavorite = false }
        }
        .sheet(item: $editingFavorite) { record in
            GoFlyFavoriteRouteLabelEditor(record: record, onDismiss: { editingFavorite = nil }) {
                editingFavorite = nil
                Task {
                    await favoriteRoutes.delete(record.id)
                    if controller.loadedFavoriteRecordID == record.id { controller.setLoadedFavoriteRecordID(nil) }
                }
            }
        }
        .onChange(of: controller.canEdit) { _, canEdit in
            if !canEdit {
                editingFavorite = nil
                showingDetails = false
                showingImports = false
                showingAllPoints = false
                showingFavoriteRoutes = false
                showingSaveFavorite = false
            }
        }
    }

    /// Figma D1/D2: header 12 pt below the sheet top, list card, add / inspect row,
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
        .padding(.bottom, 20)
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
            .goFlySteadyDisabled(!isRouteUsable)
            .accessibilityIdentifier("route.start")
        }
    }

    private var favoriteStarButton: some View {
        Button {
            if let matching = matchingFavoriteRecord {
                editingFavorite = matching
            } else {
                if let key = GoFlySaveFavoriteRouteView.eligibilityError(
                    draft: controller.draft, currentLocationAvailable: currentLocationAvailable) {
                    onNotice(key)
                } else {
                    presentFavoriteSaveSheet()
                }
            }
        } label: {
            Group {
                if preparingFavoriteSave {
                    ProgressView()
                        .frame(width: 20, height: 20)
                } else {
                    GoFlyStarIcon(size: 20, filled: isFavorite)
                }
            }
            .goFlyIconButtonChrome(diameter: GoFlyStyle.primaryButtonHeight, showsBorder: false,
                                   enabledSurface: GoFlyStyle.startSecondarySurface)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .disabled(preparingFavoriteSave)
        .accessibilityLabel(goFlyString(preparingFavoriteSave ? "favoriteRoutes.loading" : (isFavorite ? "favoriteRoutes.editLabel" : "favoriteRoutes.add")))
        .accessibilityIdentifier("route.favorite.toggle")
    }

    private func presentFavoriteSaveSheet() {
        guard !preparingFavoriteSave else { return }
        preparingFavoriteSave = true
        Task {
            await favoriteRoutes.load()
            preparingFavoriteSave = false
            guard controller.canEdit else { return }
            if let key = GoFlySaveFavoriteRouteView.eligibilityError(
                draft: controller.draft, currentLocationAvailable: currentLocationAvailable) {
                onNotice(key)
                return
            }
            guard favoriteRoutes.canMutate else {
                onNotice(favoriteRoutes.error?.localizationKey ?? "favoriteRoutes.error.busy")
                return
            }
            showingSaveFavorite = true
        }
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
        VStack(spacing: 16) {
            if [.planning, .preparing, .pausing, .cancelling].contains(controller.phase) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(goFlyString("route.phase.\(controller.phase.rawValue)"))
                        .font(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            } else if controller.phase == .unknown {
                HStack(spacing: 12) {
                    settingsButton
                    cancelButton
                }
                .padding(.bottom, 16)
            } else {
                GoFlyRouteRunningControls(
                    title: controller.roundTripEnabled ? goFlyString("route.position")
                        : GoFlyRouteRunningControls.remainingTitle(controller.progress?.estimatedRemaining),
                    fraction: controller.progress?.fraction ?? 0,
                    isRoundTrip: controller.roundTripEnabled,
                    isReversed: controller.heading == .reverse,
                    speed: controller.draft.speed.kilometersPerHour,
                    canToggleRoundTrip: controller.canSetRoundTrip,
                    canToggleDirection: controller.canToggleHeading,
                    canChangeSpeed: controller.canSetSpeed,
                    isPaused: [.paused, .interrupted].contains(controller.phase),
                    isInterrupted: controller.phase == .interrupted,
                    canPlayback: controller.phase == .interrupted ? true : (controller.phase == .paused ? controller.canResume : controller.canPause),
                    canEnd: controller.canCancel,
                    onToggleRoundTrip: { _ = controller.setRoundTripEnabled(!controller.roundTripEnabled) },
                    onToggleDirection: { _ = controller.toggleHeading() },
                    onSpeedTap: { showingDetails = true },
                    onPlayback: {
                        if controller.phase == .interrupted { onRetryInterrupted() }
                        else if controller.phase == .paused { _ = controller.resume() } else { _ = controller.pause() }
                    },
                    onEnd: onRequestEnd
                )
            }
        }
        .padding(.horizontal, 20)
        // The label row starts 20 pt below the grabber; the safe area supplies the bottom 34 pt.
        .padding(.top, GoFlyGrabber.rowHeight)
        .frame(maxWidth: .infinity)
        .background(GoFlyStyle.cardSurface)
        .overlay(alignment: .top) {
            Capsule().fill(GoFlyStyle.border).frame(width: 36, height: GoFlyGrabber.capsuleHeight).padding(.top, GoFlyGrabber.topInset)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("route.panel.content")
    }

    private var narrowView: some View {
        HStack(spacing: 8) {
            Button(action: { onExpand?() }) {
                Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                    .font(GoFlyFont.title)
                    .lineLimit(1)
                    .foregroundStyle(GoFlyTextColor.primary)
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
                .font(GoFlyFont.title)
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
                    .font(GoFlyFont.subheadlineEmphasis)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("route.clearImported")
        }
    }

    /// Rows are 60 pt; the list scrolls once the panel reaches its 414 pt maximum.
    private static let maxPanelContent: CGFloat = 388
    private static let rowHeight: CGFloat = 60
    /// Everything in the editing panel except the list: header, gaps, action row, Start row and bottom inset.
    private static let panelChrome: CGFloat = 192

    private var listHeight: CGFloat {
        // D2: the sheet tops out at 416 pt above the tab bar (404 pt under the 12 pt grabber); only the list scrolls.
        let cap = min(Self.maxPanelContent - Self.panelChrome, max(Self.rowHeight, maximumHeight - Self.panelChrome))
        return min(listContentHeight, cap)
    }

    private var routeListCard: some View {
        ScrollViewReader { proxy in
            GoFlyRouteNodeCard(controller: controller, proxy: proxy, height: listHeight,
                               onEditNode: onEditNode,
                               onContentHeightChange: { listContentHeight = $0 })
        }
        .accessibilityIdentifier("route.nodes.card")
    }

    private var routeActionRow: some View {
        HStack(spacing: 16) {
            Button { _ = controller.addEmptyWaypoint() } label: {
                Label(goFlyString("route.addStop"), systemImage: GoFlySymbols.add)
            }
            .buttonStyle(GoFlyRouteTextButtonStyle())
            .disabled(!controller.canAddNode)
            .accessibilityIdentifier("route.addNode")
            .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount ? goFlyString("route.nodeLimit") : "")
            Spacer(minLength: 0)
            Button(action: onInspectRoute) {
                Label {
                    Text(goFlyString("route.viewList"))
                } icon: {
                    Image(GoFlySymbols.routeList)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: listIconSize, height: listIconSize)
                }
            }
            .buttonStyle(GoFlyRouteTextButtonStyle())
            .disabled(!controller.canEdit)
            .accessibilityIdentifier("route.viewList")
        }
    }

    private func headerButton<Icon: View>(identifier: String, label: String,
                              enabled: Bool, action: @escaping () -> Void,
                              @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            icon()
                .goFlyIconButtonChrome(diameter: 44)
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
            HStack(spacing: 8) {
                GoFlyRoundTripIcon(enabled: controller.roundTripEnabled, size: 14)
                Text(goFlyString("route.roundTripShort"))
                    .font(GoFlyFont.footnoteEmphasis)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(controller.roundTripEnabled ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
            .overlay { if !controller.roundTripEnabled { Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 0.75) } }
            .contentShape(Capsule())
            .foregroundStyle(!controller.canSetRoundTrip ? GoFlyTextColor.disabled
                             : (controller.roundTripEnabled ? GoFlyTextColor.inverse : GoFlyStyle.primary))
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(!controller.canSetRoundTrip)
        .accessibilityValue(controller.roundTripEnabled ? "1" : "0")
        .accessibilityHint(goFlyString("route.roundTripHint"))
        .accessibilityIdentifier("route.roundTrip")
    }
}
