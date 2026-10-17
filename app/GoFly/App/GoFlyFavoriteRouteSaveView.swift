import GoFlyCore
import SwiftUI

struct GoFlySaveFavoriteRouteView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var currentLocationAvailable: Bool?
    var currentRouteOrigin: @MainActor () -> GeoCoordinate?
    var onDismiss: () -> Void
    @State private var label = ""
    @State private var saving = false
    @State private var localErrorKey: String?
    @State private var savedOmittingCurrent: FavoriteRouteRecord?
    @State private var saveTask: Task<Void, Never>?
    @State private var visibleScrollFrame: CGRect = .zero
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let saved = savedOmittingCurrent {
                        Label(goFlyString("favoriteRoutes.savedOmittingCurrent"), systemImage: "checkmark.circle")
                            .font(.body)
                            .accessibilityIdentifier("favoriteRoutes.save.omittedResult")
                        Text(goFlyFavoriteRouteEndpoints(saved)).font(.body)
                    } else {
                        Text(sourceSummary).font(.body)
                            .accessibilityIdentifier("favoriteRoutes.save.source")
                        if controller.draft.nodes.contains(where: { $0.value == .current }) {
                            Text(goFlyString(currentLocationAvailable == true
                                ? "favoriteRoutes.currentSnapshotHint" : "favoriteRoutes.currentOmittedHint"))
                                .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                        }
                        GoFlyFavoriteRouteFailureNotice(localErrorKey: localErrorKey ?? eligibilityError)
                        if saving {
                            ProgressView(goFlyString("favoriteRoutes.saving"))
                                .accessibilityIdentifier("favoriteRoutes.save.working")
                        }
                        TextField(goFlyString("favoriteRoutes.label"), text: $label)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 8)
                            .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit { focused = false }
                            .disabled(saving)
                            .accessibilityIdentifier("favoriteRoutes.save.label")
                    }
                }
                .padding(24)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityIdentifier("favoriteRoutes.save.content")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if savedOmittingCurrent != nil {
                        Button(goFlyString("favoriteRoutes.done"), action: onDismiss)
                            .buttonStyle(GoFlyActionStyle(primary: true))
                            .accessibilityIdentifier("favoriteRoutes.save.done")
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { cancelButton; saveButton }
                            VStack(spacing: 12) { cancelButton; saveButton }
                        }
                    }
                }
                .padding(16)
                .background(GoFlyStyle.surface)
            }
            .background(GoFlyStyle.surface)
            .navigationTitle(goFlyString(savedOmittingCurrent == nil ? "favoriteRoutes.add" : "favoriteRoutes.savedTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .topLeading) { viewportMetrics }
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
        .interactiveDismissDisabled(saving)
        .task { focused = true }
        .onDisappear { saveTask?.cancel() }
    }

    private var eligibilityError: String? {
        guard controller.draft.gpxSource == nil else { return nil }
        let count = controller.draft.nodes.reduce(0) { count, node in
            switch node.value {
            case .place: count + 1
            case .current: count + (currentLocationAvailable == true ? 1 : 0)
            }
        }
        return count < 2 ? "favoriteRoutes.error.tooFewValidPlaces" : nil
    }

    private var sourceSummary: String {
        if let source = controller.draft.gpxSource {
            return source.displayFilename + " · " + String.localizedStringWithFormat(
                goFlyString("favoriteRoutes.pointCount"), source.document.pointCount)
        }
        func title(_ node: RouteNode?) -> String? {
            guard let node else { return nil }
            switch node.value {
            case .current: return goFlyString("route.currentLocation")
            case .place(let place): return place.title
            }
        }
        return [title(controller.draft.start), title(controller.draft.destination)].compactMap { $0 }.joined(separator: " → ")
    }

    private var cancelButton: some View {
        Button(action: onDismiss) {
            Text(goFlyString("favoriteRoutes.cancel")).fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(GoFlyActionStyle())
            .disabled(saving)
            .accessibilityIdentifier("favoriteRoutes.save.cancel")
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(goFlyString("favoriteRoutes.save")).fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(saving || !controller.canEdit || !favorites.canMutate || eligibilityError != nil)
            .accessibilityIdentifier("favoriteRoutes.save.confirm")
    }

    private func save() {
        guard !saving, savedOmittingCurrent == nil, controller.canEdit, favorites.canMutate else { return }
        // Capture both authoritative values synchronously in the actual tap, before any await.
        let draft = controller.draft
        let origin = currentRouteOrigin()
        let capturedLabel = label
        let candidate: FavoriteRouteSaveCandidate
        do { candidate = try FavoriteRouteSaveBuilder.build(draft: draft, currentRouteOrigin: origin) }
        catch {
            localErrorKey = (error as? FavoriteRoutesFailure)?.localizationKey ?? "favoriteRoutes.error.unavailable"
            return
        }
        localErrorKey = nil
        saving = true
        saveTask = Task {
            defer { saving = false }
            if let result = await favorites.save(candidate, label: capturedLabel) {
                focused = false
                if result.omittedUnavailableCurrent { savedOmittingCurrent = result.record }
                else { onDismiss() }
            }
        }
    }

    @ViewBuilder private var viewportMetrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                        visibleScrollFrame.width, visibleScrollFrame.height))
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("favoriteRoutes.save.viewport.metrics")
        }
        #endif
    }
}

struct GoFlyFavoriteRouteLabelEditor: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    let record: FavoriteRouteRecord
    var onDismiss: () -> Void
    @State private var label: String
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var visibleScrollFrame: CGRect = .zero
    @FocusState private var focused: Bool

    init(record: FavoriteRouteRecord, onDismiss: @escaping () -> Void) {
        self.record = record
        self.onDismiss = onDismiss
        _label = State(initialValue: record.label ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(goFlyFavoriteRouteEndpoints(record)).font(.body)
                    GoFlyFavoriteRouteFailureNotice()
                    if saving { ProgressView(goFlyString("favoriteRoutes.saving")) }
                    TextField(goFlyString("favoriteRoutes.label"), text: $label)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(GoFlyStyle.border, lineWidth: 0.5) }
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { focused = false }
                        .disabled(saving)
                        .accessibilityIdentifier("favoriteRoutes.editor.label")
                }
                .padding(24)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityIdentifier("favoriteRoutes.editor.content")
            .safeAreaInset(edge: .bottom) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { cancelButton; saveButton }
                    VStack(spacing: 12) { cancelButton; saveButton }
                }
                .padding(16)
                .background(GoFlyStyle.surface)
            }
            .background(GoFlyStyle.surface)
            .navigationTitle(goFlyString("favoriteRoutes.editLabel"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .topLeading) { viewportMetrics }
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
        .interactiveDismissDisabled(saving)
        .task { focused = true }
        .onDisappear { saveTask?.cancel() }
    }

    private var cancelButton: some View {
        Button(action: onDismiss) {
            Text(goFlyString("favoriteRoutes.cancel")).fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(GoFlyActionStyle())
            .disabled(saving)
            .accessibilityIdentifier("favoriteRoutes.editor.cancel")
    }
    private var saveButton: some View {
        Button {
            guard !saving, favorites.canMutate else { return }
            let capturedLabel = label
            saving = true
            saveTask = Task {
                defer { saving = false }
                if await favorites.updateLabel(record.id, label: capturedLabel) { onDismiss() }
            }
        } label: {
            Text(goFlyString("favoriteRoutes.save")).fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(GoFlyActionStyle(primary: true))
        .disabled(saving || !favorites.canMutate || !favorites.records.contains(where: { $0.id == record.id }))
        .accessibilityIdentifier("favoriteRoutes.editor.save")
    }

    @ViewBuilder private var viewportMetrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                        visibleScrollFrame.width, visibleScrollFrame.height))
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("favoriteRoutes.editor.viewport.metrics")
        }
        #endif
    }
}
