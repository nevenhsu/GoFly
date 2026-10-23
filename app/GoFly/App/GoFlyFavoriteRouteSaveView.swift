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
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let saved = savedOmittingCurrent {
                        GoFlyStatusBanner(tone: .success, title: goFlyString("favoriteRoutes.savedOmittingCurrent"),
                                          identifier: "favoriteRoutes.save.omittedResult")
                        Text(goFlyFavoriteRouteEndpoints(saved)).font(.body)
                    } else {
                        GoFlyFavoriteRouteFailureNotice(localErrorKey: localErrorKey ?? eligibilityError)

                        if saving {
                            ProgressView(goFlyString("favoriteRoutes.saving"))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .accessibilityIdentifier("favoriteRoutes.save.working")
                        }

                        if controller.draft.nodes.contains(where: { $0.value == .current }) {
                            Text(goFlyString(currentLocationAvailable == true
                                ? "favoriteRoutes.currentSnapshotHint" : "favoriteRoutes.currentOmittedHint"))
                                .font(.footnote)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(goFlyString("favoriteRoutes.label"))
                                .font(.footnote)
                                .foregroundStyle(GoFlyStyle.secondary)
                            HStack {
                                TextField(goFlyString("favoriteRoutes.label"), text: $label)
                                    .focused($focused)
                                    .submitLabel(.done)
                                    .onSubmit { focused = false }
                                    .disabled(saving)
                                    .accessibilityIdentifier("favoriteRoutes.save.label")
                                if !label.isEmpty {
                                    Button { label = "" } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(GoFlyStyle.secondary)
                                    .accessibilityLabel(goFlyString("search.clear"))
                                }
                            }
                            .padding(.leading, 16)
                            .frame(minHeight: 48)
                            .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: 14))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder,
                                                  lineWidth: focused ? 1.5 : 0.75)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(sourceSummary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(GoFlyStyle.primary)
                            Text(pointSummary)
                                .font(.footnote)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("favoriteRoutes.save.source")
                    }
                }
                .padding(20)
            }
            .accessibilityIdentifier("favoriteRoutes.save.content")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if savedOmittingCurrent != nil {
                        Button(goFlyString("favoriteRoutes.done"), action: onDismiss)
                            .buttonStyle(GoFlyActionStyle(primary: true))
                            .accessibilityIdentifier("favoriteRoutes.save.done")
                    } else {
                        Button(action: save) {
                            Text(goFlyString("favoriteRoutes.save"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GoFlyActionStyle(primary: true))
                        .disabled(saving || !controller.canEdit || !favorites.canMutate || eligibilityError != nil)
                        .accessibilityIdentifier("favoriteRoutes.save.confirm")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(GoFlyStyle.cardSurface)
            }
        }
        .background(GoFlyStyle.cardSurface)
        .presentationDetents([.height(380), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .task { focused = true }
        .onDisappear { saveTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Button(goFlyString("favoriteRoutes.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.save.cancel")

            Spacer()

            Text(goFlyString(savedOmittingCurrent == nil ? "favoriteRoutes.add" : "favoriteRoutes.savedTitle"))
                .font(.headline)

            Spacer()

            // Balance cancel button on the left
            Text(goFlyString("favoriteRoutes.cancel"))
                .opacity(0)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
            return source.displayFilename
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

    private var pointSummary: String {
        if let source = controller.draft.gpxSource {
            return goFlyLocalizedFormat(goFlyString("favoriteRoutes.pointCount"), source.document.pointCount)
        }
        return goFlyLocalizedFormat(goFlyString("favoriteRoutes.placeCount"), controller.draft.nodes.count)
    }

    private func save() {
        guard !saving, savedOmittingCurrent == nil, controller.canEdit, favorites.canMutate else { return }
        let draft = controller.draft
        let origin = currentRouteOrigin()
        let capturedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label
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
                if result.omittedUnavailableCurrent {
                    savedOmittingCurrent = result.record
                } else {
                    controller.setLoadedFavoriteRecordID(result.record.id)
                    onDismiss()
                }
            }
        }
    }
}

struct GoFlyFavoriteRouteLabelEditor: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    let record: FavoriteRouteRecord
    var onDismiss: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var label: String
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    init(record: FavoriteRouteRecord, onDismiss: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.record = record
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _label = State(initialValue: record.label ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GoFlyFavoriteRouteFailureNotice()

                    if saving {
                        ProgressView(goFlyString("favoriteRoutes.saving"))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyString("favoriteRoutes.label"))
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                        HStack {
                            TextField(goFlyString("favoriteRoutes.label"), text: $label)
                                .focused($focused)
                                .submitLabel(.done)
                                .onSubmit { focused = false }
                                .disabled(saving)
                                .accessibilityIdentifier("favoriteRoutes.editor.label")
                            if !label.isEmpty {
                                Button { label = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .accessibilityLabel(goFlyString("search.clear"))
                            }
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder,
                                              lineWidth: focused ? 1.5 : 0.75)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyFavoriteRouteEndpoints(record))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(GoFlyStyle.primary)
                        Text(goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
                            ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count))
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .accessibilityIdentifier("favoriteRoutes.editor.content")
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard !saving, favorites.canMutate else { return }
                    let capturedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : label
                    saving = true
                    saveTask = Task {
                        defer { saving = false }
                        if await favorites.updateLabel(record.id, label: capturedLabel) { onDismiss() }
                    }
                } label: {
                    Text(goFlyString("favoriteRoutes.save"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(saving || !favorites.canMutate || !favorites.records.contains(where: { $0.id == record.id }))
                .accessibilityIdentifier("favoriteRoutes.editor.save")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(GoFlyStyle.cardSurface)
            }
        }
        .background(GoFlyStyle.cardSurface)
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving)
        .task { focused = true }
        .onDisappear { saveTask?.cancel() }
    }

    private var header: some View {
        HStack {
            Button(goFlyString("favoriteRoutes.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.editor.cancel")

            Spacer()

            Text(goFlyString("favoriteRoutes.editLabel"))
                .font(.headline)

            Spacer()

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Text(goFlyString("favoriteRoutes.deleteSingle"))
                        .foregroundStyle(GoFlyStyle.dangerForeground)
                }
                .buttonStyle(.plain)
                .disabled(saving || !favorites.canMutate)
                .accessibilityIdentifier("favoriteRoutes.editor.delete")
            } else {
                Text(goFlyString("favoriteRoutes.cancel"))
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
