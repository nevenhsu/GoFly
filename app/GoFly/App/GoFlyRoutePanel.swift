import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @ObservedObject var controller: RouteExecutionController
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    var onSettings: () -> Void = { }
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    var currentLocationAvailable: Bool? = nil
    var currentRouteOrigin: @MainActor () -> GeoCoordinate? = { nil }
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
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if controller.phase == .editing {
                        editingContent { id, anchor in
                            withAnimation(.linear(duration: 0.12)) { proxy.scrollTo(id, anchor: anchor) }
                        }
                    } else {
                        executionContent
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                fixedControls.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
                    .background(GoFlyStyle.surface)
            }
            .frame(height: min(contentHeight + 76, max(100, maximumHeight)))
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("route.panel.content")
        }
        .accessibilityHidden(showingDetails || showingImports || showingAllPoints || showingFavoriteRoutes || showingSaveFavorite)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel")
        .sheet(isPresented: $showingImports) {
            NavigationStack {
                GoFlyImportedRoutesView(controller: controller, onLoaded: { showingImports = false }, onFocusPoint: { coordinate in
                    showingImports = false
                    onFocusPoint(coordinate)
                })
            }
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
            GoFlyRouteDetailsView(controller: controller) { showingDetails = false }
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

    private func editingContent(scrollTo: @escaping (RouteNodeID, UnitPoint) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = controller.error {
                failure(error)
            } else if controller.draft.nodes.contains(where: { $0.value == .current }), currentLocationAvailable == false {
                failure(.currentLocationUnavailable)
            }
            HStack(spacing: 8) {
                Text(goFlyString("route.title"))
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                headerButton("folder", identifier: "route.importedRoutes",
                             label: goFlyString("imports.title"), enabled: controller.canEdit) {
                    showingImports = true
                }
                headerButton(GoFlySymbols.favorite, identifier: "route.favorite.add",
                             label: goFlyString("favoriteRoutes.add"), enabled: controller.canEdit) {
                    showingSaveFavorite = true
                }
            }

            if let imported = controller.draft.gpxSource {
                VStack(alignment: .leading, spacing: 6) {
                    Text(goFlyString("imports.loadedPath")).font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                    Text(imported.displayFilename).font(.body.weight(.semibold))
                    Text(goFlyLocalizedFormat(goFlyString("imports.metadata"),
                         goFlyString("imports.kind.\(imported.document.kind.rawValue)"), imported.document.pointCount))
                        .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("route.importedSummary")
                GoFlyGPXPointList(points: imported.document.segments.flatMap { $0 }, summarized: true,
                                   onFocus: onFocusPoint, onShowAll: { showingAllPoints = true })
                Button(goFlyString("imports.clearLoaded")) { _ = controller.clearImportedRoute() }
                    .buttonStyle(GoFlyActionStyle(small: true))
                    .disabled(!controller.canClearImportedRoute)
                    .accessibilityIdentifier("route.clearImported")
            } else {
                GoFlyRouteNodeList(
                    draft: controller.draft, isEditable: controller.canEdit, viewport: visibleScrollFrame,
                    onEdit: onEditNode,
                    onDelete: { _ = controller.removeNode(id: $0) },
                    onMove: { _ = controller.moveNode(id: $0, toIndex: $1) },
                    onScroll: scrollTo
                )
                HStack(spacing: 16) {
                    Button { _ = controller.openNewPicker() } label: {
                        Label(goFlyString(controller.draft.nodes.isEmpty ? "route.addOrigin" :
                                        (controller.draft.nodes.count == 1 ? "route.addDestination" : "route.addWaypoint")),
                              systemImage: GoFlySymbols.add)
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
                    if controller.draft.nodes.count >= 2 {
                        Button(action: exchangeEndpoints) {
                            Label(goFlyString("route.exchange"), systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!controller.canEdit)
                        .accessibilityIdentifier("route.exchange")
                    }
                }
            }

            summaryRow

            if controller.canEdit {
                Button { showingFavoriteRoutes = true } label: {
                    Label(goFlyString("favoriteRoutes.title"), systemImage: GoFlySymbols.favorite)
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .frame(minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controller.canEdit)
                .accessibilityIdentifier("route.favorite.list")
            }
        }
    }

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let route = controller.plannedRoute {
                    Text(goFlyLocalizedFormat(goFlyString("route.distance"),
                                              route.totalDistanceMeters / 1_000))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("route.summary")
                    Text(goFlyLocalizedFormat(goFlyString("route.duration"),
                         Int((route.totalDistanceMeters / controller.draft.speed.metersPerSecond / 60).rounded(.up))))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                } else {
                    Text(goFlyLocalizedFormat(goFlyString("route.speedValue"),
                                              controller.draft.speed.kilometersPerHour))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityIdentifier("route.summary")
                    Text(goFlyString("route.noRouteYet"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
            }
            Spacer(minLength: 4)
            GoFlyRoundTripControl(controller: controller)
            Button { showingDetails = true } label: {
                HStack(spacing: 4) {
                    Text(goFlyLocalizedFormat(goFlyString("route.speedValue"),
                                              controller.draft.speed.kilometersPerHour))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(GoFlyStyle.secondarySurface, in: Capsule())
                .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canEdit)
            .accessibilityLabel(goFlyString("route.details"))
            .accessibilityIdentifier("route.details")
        }
        .frame(minHeight: 44)
    }

    private func headerButton(_ symbol: String, identifier: String, label: String,
                              enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .goFlyControlSymbol(size: 17, weight: .semibold)
                .frame(width: 40, height: 40)
                .background(GoFlyStyle.secondarySurface, in: Circle())
                .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var executionContent: some View {
        if let error = controller.error { failure(error) }
        if [.planning, .preparing, .pausing, .cancelling].contains(controller.phase) {
            ProgressView(goFlyString("route.phase.\(controller.phase.rawValue)"))
                .font(.headline)
        } else if controller.phase != .running && controller.phase != .paused {
            Text(goFlyString("route.phase.\(controller.phase.rawValue)"))
                .font(.headline)
        }
        if let progress = controller.progress {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(value: progress.fraction, total: 1)
                    .accessibilityLabel(goFlyString(controller.usesPositionAxis ? "route.position" : "route.progress"))
                    .accessibilityIdentifier("route.progress")
                if controller.usesPositionAxis {
                    HStack(alignment: .top, spacing: 12) {
                        Text(goFlyString("route.axis.origin"))
                        Spacer(minLength: 8)
                        Text(goFlyString("route.axis.destination"))
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityIdentifier("route.position.endpoints")
                    Text(goFlyLocalizedFormat(goFlyString("route.positionValue"),
                         progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(GoFlyPreferences.shared.locale))))
                        .font(.subheadline.monospacedDigit())
                        .accessibilityIdentifier("route.position.value")
                } else {
                    Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
    }

    @ViewBuilder private var fixedControls: some View {
        if controller.canEdit {
            Button(goFlyString("route.start")) { _ = controller.start() }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!controller.canStart)
                .accessibilityIdentifier("route.start")
        } else {
        switch controller.phase {
        case .running, .paused:
            HStack(alignment: .center, spacing: 12) {
                roundTripControl
                if controller.roundTripEnabled {
                    Button { _ = controller.toggleHeading() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: controller.heading == .forward ? "arrow.right" : "arrow.left")
                                .goFlyControlSymbol(size: 22, weight: .regular)
                            Text(goFlyString("route.direction.\(controller.heading.rawValue)"))
                                .font(.body)
                        }
                        .frame(minWidth: 126, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(controller.canToggleHeading ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                    .disabled(!controller.canToggleHeading)
                    .accessibilityHint(goFlyString("route.direction.toggleHint"))
                    .accessibilityIdentifier("route.direction")
                }
            }
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
        case .planning, .pausing:
            cancelButton
        case .interrupted:
            settingsButton
            cancelButton
        case .unknown:
            Text(goFlyString("route.unknown.message"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
            settingsButton
        case .preparing, .cancelling, .editing:
            EmptyView()
        }
        }
    }

    private var roundTripControl: some View {
        GoFlyRoundTripControl(controller: controller)
    }

    private var cancelButton: some View {
        Button { confirmingCancellation = true } label: {
            Label(goFlyString("execution.end"), systemImage: GoFlySymbols.close)
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(!controller.canCancel)
        .accessibilityIdentifier("route.cancel")
    }

    private var settingsButton: some View {
        Button(goFlyString("operation.settings"), action: onSettings)
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("route.settings")
    }

    private func failure(_ error: RouteExecutionFailure) -> some View {
        GoFlyStatusBanner(tone: .danger, title: goFlyString(error.localizationKey), message: goFlyString("status.repairGuidance"), identifier: "route.error")
    }

    private func exchangeEndpoints() {
        let nodes = controller.draft.nodes
        guard controller.canEdit, nodes.count >= 2, let first = nodes.first, let last = nodes.last else { return }
        guard controller.moveNode(id: last.id, toIndex: 0) else { return }
        _ = controller.moveNode(id: first.id, toIndex: nodes.count - 1)
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

private struct GoFlyRouteDetailsView: View {
    @ObservedObject var controller: RouteExecutionController
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GoFlyRoundTripControl(controller: controller)
                    Text(goFlyString("route.speed")).font(.headline)
                    Text(goFlyLocalizedFormat(goFlyString("route.speedValue"), controller.draft.speed.kilometersPerHour))
                        .font(.largeTitle.weight(.bold).monospacedDigit())
                        .accessibilityIdentifier("route.speed.value")
                    Slider(value: Binding(
                        get: { Double(controller.draft.speed.kilometersPerHour) },
                        set: { value in
                            if let speed = RouteSpeed(kilometersPerHour: Int(value.rounded())) { _ = controller.setSpeed(speed) }
                        }
                    ), in: 2...100, step: 1) {
                        Text(goFlyString("route.speed"))
                    } minimumValueLabel: {
                        Text("2")
                    } maximumValueLabel: {
                        Text("100")
                    }
                    .disabled(!controller.canEdit)
                    .tint(GoFlyStyle.primary)
                    .accessibilityValue(goFlyLocalizedFormat(
                        goFlyString("route.speedValue"), controller.draft.speed.kilometersPerHour
                    ))
                    .accessibilityIdentifier("route.speed")
                }
                .padding(24)
            }
            .accessibilityIdentifier("route.details.content")
            .background(GoFlyStyle.surface)
            .navigationTitle(goFlyString("route.details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Text(goFlyString("common.back"))
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("route.details.back")
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
    }
}

private struct GoFlyRoundTripControl: View {
    @ObservedObject var controller: RouteExecutionController

    var body: some View {
        Toggle(isOn: Binding(
            get: { controller.roundTripEnabled },
            set: { _ = controller.setRoundTripEnabled($0) }
        )) {
            Label(goFlyString("route.roundTrip"),
                  systemImage: controller.roundTripEnabled ? GoFlySymbols.checked : GoFlySymbols.unchecked)
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .labelStyle(.titleAndIcon)
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(controller.roundTripEnabled ? GoFlyStyle.secondarySurface : .clear, in: Capsule())
        .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
        .contentShape(Capsule())
        .foregroundStyle(controller.canSetRoundTrip ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
        .disabled(!controller.canSetRoundTrip)
        .accessibilityValue(controller.roundTripEnabled ? "1" : "0")
        .accessibilityHint(goFlyString("route.roundTripHint"))
        .accessibilityIdentifier("route.roundTrip")
    }
}
