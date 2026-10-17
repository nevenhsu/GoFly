import GoFlyCore
import SwiftUI

struct GoFlyRoutePanel: View {
    @ObservedObject var controller: RouteExecutionController
    var maximumHeight: CGFloat
    var onEditNode: (RouteNodeID) -> Void
    var onSettings: () -> Void = { }
    var currentLocationAvailable: Bool? = nil
    var currentRouteOrigin: @MainActor () -> GeoCoordinate? = { nil }
    @State private var contentHeight: CGFloat = 240
    @State private var showingDetails = false
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
            .frame(height: min(contentHeight, max(100, maximumHeight)))
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityIdentifier("route.panel.content")
        }
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius).strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .overlay(alignment: .topLeading) { nodeMetrics }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("route.panel")
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

    @ViewBuilder private var nodeMetrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            VStack {
                Text(controller.draft.nodes.map { $0.id.rawValue.uuidString }.joined(separator: ","))
                    .accessibilityIdentifier("route.nodes.order")
                Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                            visibleScrollFrame.width, visibleScrollFrame.height))
                    .accessibilityIdentifier("route.nodes.viewport")
            }
            .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
        }
        #endif
    }

    private func editingContent(scrollTo: @escaping (RouteNodeID, UnitPoint) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(goFlyString("route.title")).font(.headline)
                Spacer(minLength: 12)
                Button { showingSaveFavorite = true } label: {
                    Image(systemName: "star")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controller.canEdit)
                .accessibilityLabel(goFlyString("favoriteRoutes.add"))
                .accessibilityIdentifier("route.favorite.add")
                Button { showingDetails = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controller.canEdit)
                .accessibilityLabel(goFlyString("route.details"))
                .accessibilityIdentifier("route.details")
            }
            if let imported = controller.draft.gpxSource {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("imports.loadedPath")).font(.headline)
                    Text(imported.displayFilename).font(.body)
                    Text(String.localizedStringWithFormat(goFlyString("imports.metadata"),
                         goFlyString("imports.kind.\(imported.document.kind.rawValue)"), imported.document.pointCount))
                        .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("route.importedSummary")
                Button(goFlyString("imports.clearLoaded")) { _ = controller.clearImportedRoute() }
                    .buttonStyle(GoFlyActionStyle())
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
                Button { _ = controller.openNewPicker() } label: {
                    Text(goFlyString(controller.draft.nodes.isEmpty ? "route.addOrigin" :
                                    (controller.draft.nodes.count == 1 ? "route.addDestination" : "route.addWaypoint")))
                        .font(.system(size: addFontSize))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.canAddNode ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                .disabled(!controller.canAddNode)
                .accessibilityIdentifier("route.addNode")
                .accessibilityHint(controller.draft.nodes.count == RouteDraft.maximumNodeCount ? goFlyString("route.nodeLimit") : "")
            }
            Button { showingFavoriteRoutes = true } label: {
                Label(goFlyString("favoriteRoutes.title"), systemImage: "star")
            }
            .buttonStyle(GoFlyActionStyle())
            .disabled(!controller.canEdit)
            .accessibilityIdentifier("route.favorite.list")
            if let error = controller.error {
                failure(error)
            } else if controller.draft.nodes.contains(where: { $0.value == .current }), currentLocationAvailable == false {
                failure(.currentLocationUnavailable)
            }
            Button(goFlyString("route.start")) { _ = controller.start() }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!controller.canStart)
                .accessibilityIdentifier("route.start")
        }
    }

    @ViewBuilder private var executionContent: some View {
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
                    Text(String.localizedStringWithFormat(goFlyString("route.positionValue"),
                         progress.fraction.formatted(.percent.precision(.fractionLength(0)))))
                        .font(.subheadline.monospacedDigit())
                        .accessibilityIdentifier("route.position.value")
                } else {
                    Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.subheadline.monospacedDigit())
                }
            }
        }
        if let error = controller.error { failure(error) }
        switch controller.phase {
        case .running, .paused:
            HStack(alignment: .center, spacing: 12) {
                roundTripControl
                if controller.roundTripEnabled {
                    Button { _ = controller.toggleHeading() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: controller.heading == .forward ? "arrow.right" : "arrow.left")
                                .font(.system(size: 22))
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

    private var roundTripControl: some View {
        GoFlyRoundTripControl(controller: controller)
    }

    private var cancelButton: some View {
        Button(goFlyString("route.cancel")) {
            if controller.phase == .paused { confirmingCancellation = true }
            else { _ = controller.cancel() }
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
        Label(goFlyString(error.localizationKey), systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(GoFlyStyle.errorForeground)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("route.error")
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
    @State private var visibleScrollFrame: CGRect = .zero

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    NavigationLink {
                        GoFlyImportedRoutesView(controller: controller, onLoaded: onDismiss)
                    } label: {
                        HStack {
                            Text(goFlyString("imports.title"))
                            Spacer(minLength: 12)
                            Image(systemName: "chevron.right")
                        }
                    }
                    .buttonStyle(GoFlyActionStyle())
                    .disabled(!controller.canEdit)
                    .accessibilityIdentifier("route.importedRoutes")
                    GoFlyRoundTripControl(controller: controller)
                    Text(goFlyString("route.speed")).font(.headline)
                    Text(String.localizedStringWithFormat(goFlyString("route.speedValue"), controller.draft.speed.kilometersPerHour))
                        .font(.title2.monospacedDigit())
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
                    .accessibilityValue(String.localizedStringWithFormat(
                        goFlyString("route.speedValue"), controller.draft.speed.kilometersPerHour
                    ))
                    .accessibilityIdentifier("route.speed")
                }
                .padding(24)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityIdentifier("route.details.content")
            .background(GoFlyStyle.surface)
            .overlay(alignment: .topLeading) {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
                    Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                                visibleScrollFrame.width, visibleScrollFrame.height))
                        .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("route.details.viewportMetrics")
                }
                #endif
            }
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
                  systemImage: controller.roundTripEnabled ? "checkmark.square.fill" : "square")
                .font(.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(controller.canSetRoundTrip ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
        .disabled(!controller.canSetRoundTrip)
        .accessibilityValue(controller.roundTripEnabled ? "1" : "0")
        .accessibilityHint(goFlyString("route.roundTripHint"))
        .accessibilityIdentifier("route.roundTrip")
    }
}
