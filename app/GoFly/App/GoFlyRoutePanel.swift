import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @EnvironmentObject private var favoriteRoutes: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    var onSettings: () -> Void = { }
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    var currentLocationAvailable: Bool? = nil
    var currentRouteOrigin: @MainActor () -> GeoCoordinate? = { nil }
    var isNarrow: Bool = false
    var onExpand: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 240
    @State private var showingDetails = false
    @State private var showingImports = false
    @State private var showingAllPoints = false
    @State private var showingFavoriteRoutes = false
    @State private var showingSaveFavorite = false
    @State private var confirmingCancellation = false
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
        .sheet(isPresented: $showingFavoriteRoutes) {
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
        .confirmationDialog(goFlyString("route.cancelConfirmation.title"),
                            isPresented: $confirmingCancellation, titleVisibility: .visible) {
            Button(goFlyString("route.cancelConfirmation.confirm"), role: .destructive) { _ = controller.cancel() }
            Button(goFlyString("route.cancelConfirmation.return"), role: .cancel) { }
        } message: {
            Text(goFlyString("route.cancelConfirmation.message"))
        }
    }

    private var editingView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editingContent { id, anchor in
                        withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                startControl.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
                    .background(GoFlyStyle.cardSurface)
            }
            .frame(height: min(contentHeight + 76, max(100, maximumHeight)))
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route.panel.content")
        }
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
                .frame(width: 50, height: 50)
                .background(GoFlyStyle.secondarySurface, in: Circle())
                .overlay {
                    Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                }
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
            } else if controller.phase == .paused || controller.phase == .interrupted {
                GoFlyResumePanel(
                    title: goFlyString("background.routePaused"),
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
            } else {
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(goFlyString(controller.roundTripEnabled ? "route.position" : "route.progress"))
                            .font(.subheadline)
                            .foregroundStyle(GoFlyStyle.secondary)
                        Spacer(minLength: 8)
                        Text(controller.progress?.fraction ?? 0, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("route.position.value")
                    }
                    ProgressView(value: min(max(controller.progress?.fraction ?? 0, 0), 1), total: 1)
                        .progressViewStyle(GoFlyProgressStyle())
                        .accessibilityLabel(goFlyString(controller.roundTripEnabled ? "route.position" : "route.progress"))
                        .accessibilityIdentifier("route.progress")

                    if controller.roundTripEnabled {
                        HStack {
                            Text(goFlyString("route.axis.origin"))
                                .font(.caption2)
                                .foregroundStyle(GoFlyStyle.secondary)
                            Spacer()
                            Text(goFlyString("route.axis.destination"))
                                .font(.caption2)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }
                    }
                }

                GoFlyRouteControlRow(
                    isRoundTrip: controller.roundTripEnabled,
                    isReversed: controller.heading == .reverse,
                    speed: controller.draft.speed.kilometersPerHour,
                    canToggleRoundTrip: controller.canSetRoundTrip,
                    canToggleDirection: controller.canToggleHeading,
                    canChangeSpeed: controller.canEdit,
                    onToggleRoundTrip: { _ = controller.setRoundTripEnabled(!controller.roundTripEnabled) },
                    onToggleDirection: { _ = controller.toggleHeading() },
                    onSpeedTap: { showingDetails = true }
                )
                .padding(.bottom, 8)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        cancelButton
                        playbackButton
                    }
                    VStack(spacing: 12) {
                        cancelButton
                        playbackButton
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(GoFlyStyle.cardSurface)
        .accessibilityIdentifier("route.panel.content")
    }

    private var narrowView: some View {
        HStack(spacing: 8) {
            Button(action: { onExpand?() }) {
                Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                    .font(.title3.weight(.bold))
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
        .padding(.horizontal, 20)
        .frame(height: 76)
        .background(GoFlyStyle.cardSurface)
        .contentShape(Rectangle())
        .onTapGesture { onExpand?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel.narrow")
    }

    private func editingContent(scrollTo: @escaping (RouteNodeID, UnitPoint) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(controller.draft.gpxSource?.displayFilename ?? goFlyString("route.planTitle"))
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
                .accessibilityElement(children: .combine)
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

            if let imported = controller.draft.gpxSource {
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
            } else {
                GoFlyRouteNodeList(
                    draft: controller.draft, selectedID: controller.selectedNodeID,
                    isEditable: controller.canEdit, viewport: visibleScrollFrame,
                    onEdit: onEditNode,
                    onDelete: { _ = controller.removeNode(id: $0) },
                    onMove: { _ = controller.moveNode(id: $0, toIndex: $1) },
                    onScroll: scrollTo
                )
                HStack(spacing: 16) {
                    Button { _ = controller.openNewPicker() } label: {
                        Label(goFlyString("route.addStop"), systemImage: GoFlySymbols.add)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44, alignment: .leading)
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
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!controller.canEdit || controller.draft.nodes.count < 2)
                    .accessibilityIdentifier("route.exchange")
                }
            }
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
        Button { confirmingCancellation = true } label: {
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


    private var playbackButton: some View {
        Button(goFlyString(controller.phase == .paused ? "route.resume" : "route.pause")) {
            if controller.phase == .paused { _ = controller.resume() }
            else { _ = controller.pause() }
        }
        .buttonStyle(GoFlyActionStyle(primary: true))
        .disabled(controller.phase == .paused ? !controller.canResume : !controller.canPause)
        .accessibilityIdentifier(controller.phase == .paused ? "route.resume" : "route.pause")
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
