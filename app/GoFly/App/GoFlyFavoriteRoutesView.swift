import GoFlyCore
import SwiftUI

struct GoFlyFavoriteRoutesView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var onDismiss: () -> Void
    @State private var editing: FavoriteRouteRecord?
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadRequest: UUID?
    @State private var loadFailureKey: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GoFlyFavoriteRouteFailureNotice(localErrorKey: loadFailureKey)
                    if favorites.loadState == .loading {
                        ProgressView(goFlyString("favoriteRoutes.loading"))
                    } else if favorites.loadState == .ready, favorites.records.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.route, message: goFlyString("favoriteRoutes.empty"))
                            .accessibilityIdentifier("favoriteRoutes.empty")
                    }
                    if favorites.isBusy || favorites.isValidatingSelection {
                        ProgressView(goFlyString(favorites.isValidatingSelection ? "favoriteRoutes.validating" : "favoriteRoutes.working"))
                            .font(.body)
                            .accessibilityIdentifier("favoriteRoutes.working")
                    }
                    ForEach(favorites.records) { record in card(record) }
                }
                .padding(16)
            }
            .accessibilityIdentifier("favoriteRoutes.content")
            .safeAreaInset(edge: .bottom) {
                Button(goFlyString("favoriteRoutes.return")) {
                    invalidateLoad()
                    onDismiss()
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("favoriteRoutes.return")
                .padding(16)
                .background(GoFlyStyle.surface)
            }
            .background(GoFlyStyle.canvas)
            .navigationTitle(goFlyString("favoriteRoutes.title"))
            .navigationBarTitleDisplayMode(.inline)
            .goFlySnackbar($snackbar)
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
        .sheet(item: $editing) { record in
            GoFlyFavoriteRouteLabelEditor(record: record, onDismiss: { editing = nil }) {
                delete(record)
            }
        }
        .onAppear { controller.invalidateFavoriteLoadAdmission() }
        .onDisappear { invalidateLoad() }
    }

    private var canSelect: Bool {
        controller.canEdit && favorites.loadState == .ready && !favorites.isBusy
    }

    private func card(_ record: FavoriteRouteRecord) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.label ?? goFlyFavoriteRouteEndpoints(record))
                    .font(.body.weight(.semibold)).lineLimit(2)
                if record.label != nil {
                    Text(goFlyFavoriteRouteEndpoints(record))
                        .font(.footnote).foregroundStyle(GoFlyStyle.secondary).lineLimit(2)
                }
                if let failure = favorites.unavailable[record.id] {
                    Text(goFlyString(failure.localizationKey))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .accessibilityIdentifier("favoriteRoutes.unavailable.\(record.id.uuidString)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.6).exclusively(before: TapGesture())
                .onEnded { gesture in
                    switch gesture {
                    case .first: edit(record)
                    case .second: load(record)
                    }
                })
            .allowsHitTesting(canSelect && favorites.unavailable[record.id] == nil)
            .disabled(!canSelect || favorites.unavailable[record.id] != nil)
            .foregroundStyle(canSelect ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.label.map { $0 + ", " + goFlyFavoriteRouteEndpoints(record) }
                                ?? goFlyFavoriteRouteEndpoints(record))
            .accessibilityValue(goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
                ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(favorites.selectedID == record.id ? .isSelected : [])
            .accessibilityAction { load(record) }
            .accessibilityAction(named: Text(goFlyString("favoriteRoutes.editLabel"))) { edit(record) }
            .accessibilityIdentifier("favoriteRoutes.record.\(record.id.uuidString)")
            Button { edit(record) } label: {
                Image(systemName: "ellipsis")
                    .goFlyControlSymbol(size: 20, weight: .regular)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!favorites.canMutate)
            .accessibilityLabel(goFlyString("favoriteRoutes.editLabel"))
            .accessibilityIdentifier("favoriteRoutes.edit.\(record.id.uuidString)")
            .padding(.trailing, 6)
        }
        .background(favorites.selectedID == record.id ? GoFlyStyle.secondarySurface : GoFlyStyle.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(favorites.selectedID == record.id ? GoFlyStyle.primary : GoFlyStyle.border,
                              lineWidth: favorites.selectedID == record.id ? 1.5 : 0.5)
        }
    }

    private func delete(_ record: FavoriteRouteRecord) {
        invalidateLoad()
        Task {
            if await favorites.delete(record.id) {
                editing = nil
                snackbar = GoFlySnackbarMessage(text: goFlyString("favoriteRoutes.deleted"),
                    actionTitle: goFlyString("favoriteRoutes.undo"), action: {
                        invalidateLoad()
                        Task { _ = await favorites.undoDelete() }
                    })
            }
        }
    }

    private func invalidateLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadRequest = nil
        controller.invalidateFavoriteLoadAdmission()
    }

    private func load(_ record: FavoriteRouteRecord) {
        guard canSelect else { return }
        invalidateLoad()
        guard let admission = controller.beginFavoriteLoad() else { return }
        let request = UUID()
        loadRequest = request
        loadFailureKey = nil
        loadTask = Task {
            await favorites.select(record.id)
            guard !Task.isCancelled, loadRequest == request,
                  favorites.loadState == .ready, favorites.selectedID == record.id,
                  let snapshot = favorites.selectedSnapshot, snapshot.record.id == record.id,
                  controller.favoriteLoadAdmissionRevision == admission else { return }
            if controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: admission) { onDismiss() }
            else { loadFailureKey = controller.error?.localizationKey }
        }
    }

    private func edit(_ record: FavoriteRouteRecord) {
        guard favorites.canMutate else { return }
        invalidateLoad()
        loadFailureKey = nil
        editing = record
    }
}

struct GoFlyFavoriteRouteFailureNotice: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    var localErrorKey: String? = nil

    var body: some View {
        if let key {
            GoFlyStatusBanner(tone: .danger, title: goFlyString(key), identifier: "favoriteRoutes.error")
        }
    }
    private var key: String? {
        if case .blocked(let failure) = favorites.loadState { return failure.localizationKey }
        return localErrorKey ?? favorites.error?.localizationKey
    }
}

func goFlyFavoriteRouteEndpoints(_ record: FavoriteRouteRecord) -> String {
    (record.startTitle ?? record.start.displayText) + " → " + (record.endTitle ?? record.end.displayText)
}
