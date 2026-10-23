import GoFlyCore
import SwiftUI

struct GoFlyFavoriteRoutesView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var onDismiss: () -> Void

    @State private var editing: FavoriteRouteRecord?
    @State private var query = ""
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadRequest: UUID?
    @State private var loadFailureKey: String?

    private var visible: [FavoriteRouteRecord] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.records.filter {
            text.isEmpty || [
                $0.label ?? "",
                $0.startTitle ?? "",
                $0.endTitle ?? "",
                $0.displayFilename ?? "",
                $0.start.displayText,
                $0.end.displayText
            ].contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    GoFlyFavoriteRouteFailureNotice(localErrorKey: loadFailureKey)
                    if favorites.loadState == .loading {
                        ProgressView(goFlyString("favoriteRoutes.loading"))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if favorites.loadState == .ready, visible.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.route,
                                        message: goFlyString(query.isEmpty ? "favoriteRoutes.empty" : "favoriteRoutes.noMatches"))
                            .padding(.vertical, 24)
                            .accessibilityIdentifier("favoriteRoutes.empty")
                    }
                    if favorites.isBusy || favorites.isValidatingSelection {
                        ProgressView(goFlyString(favorites.isValidatingSelection ? "favoriteRoutes.validating" : "favoriteRoutes.working"))
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("favoriteRoutes.working")
                    }
                    ForEach(visible) { record in
                        row(record)
                        Divider().padding(.leading, 48)
                    }
                }
                .padding(.horizontal, 20)
            }
            .accessibilityIdentifier("favoriteRoutes.content")
            .safeAreaInset(edge: .bottom) { bottomSearch }
        }
        .background(GoFlyStyle.surface)
        .goFlySnackbar($snackbar)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .sheet(item: $editing) { record in
            GoFlyFavoriteRouteLabelEditor(record: record, onDismiss: { editing = nil }) {
                delete(Set([record.id]))
                editing = nil
            }
        }
        .onAppear { controller.invalidateFavoriteLoadAdmission() }
        .onDisappear { invalidateLoad() }
    }

    private var canSelect: Bool {
        controller.canEdit && favorites.loadState == .ready && !favorites.isBusy
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if selecting { selecting = false; selected.removeAll() }
                else {
                    invalidateLoad()
                    onDismiss()
                }
            } label: {
                Group {
                    if selecting {
                        Text(goFlyString("favorites.cancel"))
                    } else {
                        Label(goFlyString("common.back"), systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.dismiss")

            Spacer(minLength: 0)

            Text(selecting
                 ? goFlyLocalizedFormat(goFlyString("favorites.selectedCount"), selected.count)
                 : goFlyString("favoriteRoutes.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            if selecting {
                Button {
                    let ids = Set(visible.map(\.id))
                    if ids.isSubset(of: selected) { selected.subtract(ids) }
                    else { selected.formUnion(ids) }
                } label: {
                    Text(goFlyString("favorites.selectAll"))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favoriteRoutes.selectAll")
            } else {
                Button {
                    selecting = true
                    selected.removeAll()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 21))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.select"))
                .disabled(!favorites.canMutate || favorites.records.isEmpty)
                .accessibilityIdentifier("favoriteRoutes.select")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func row(_ record: FavoriteRouteRecord) -> some View {
        HStack(spacing: 4) {
            if selecting {
                Button {
                    toggleSelection(record.id)
                } label: {
                    GoFlyCheckboxIcon(selected: selected.contains(record.id), size: 22)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.select"))
                .accessibilityIdentifier("favoriteRoutes.checkbox.\(record.id.uuidString)")
            } else {
                GoFlyStarIcon(size: 16, filled: true)
                    .foregroundStyle(GoFlyStyle.primary)
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.secondarySurface, in: Circle())
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }

            Button {
                if selecting { toggleSelection(record.id) }
                else { load(record) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.label ?? goFlyFavoriteRouteEndpoints(record))
                        .font(.body.weight(.medium))
                        .foregroundStyle(GoFlyStyle.primary)
                        .lineLimit(1)
                    if record.label != nil {
                        Text(goFlyFavoriteRouteEndpoints(record))
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .lineLimit(1)
                    }
                    Text(goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
                        ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                    if let failure = favorites.unavailable[record.id] {
                        Text(goFlyString(failure.localizationKey))
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.errorForeground)
                            .accessibilityIdentifier("favoriteRoutes.unavailable.\(record.id.uuidString)")
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(canSelect && favorites.unavailable[record.id] == nil)
            .disabled(!canSelect || favorites.unavailable[record.id] != nil)
            .accessibilityIdentifier("favoriteRoutes.record.\(record.id.uuidString)")

            if !selecting {
                Button { edit(record) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20))
                        .foregroundStyle(GoFlyStyle.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityLabel(goFlyString("favoriteRoutes.editLabel"))
                .accessibilityIdentifier("favoriteRoutes.edit.\(record.id.uuidString)")
                .padding(.trailing, 4)
            }
        }
        .background(favorites.selectedID == record.id ? GoFlyStyle.secondarySurface : .clear)
    }

    private var bottomSearch: some View {
        VStack(spacing: 12) {
            if selecting {
                Button {
                    delete(selected)
                } label: {
                    HStack(spacing: 8) {
                        GoFlyTrashIcon(size: 17)
                        Text(goFlyLocalizedFormat(goFlyString("favorites.deleteCount"), selected.count))
                    }
                }
                .buttonStyle(GoFlyActionStyle(destructive: true))
                .disabled(selected.isEmpty || !favorites.canMutate)
                .accessibilityIdentifier("favoriteRoutes.deleteSelected")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(GoFlyStyle.secondary)
                TextField(goFlyString("favoriteRoutes.searchSaved"), text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .accessibilityIdentifier("favoriteRoutes.search")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("search.clear"))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 52)
            .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius))
            .overlay { RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius).strokeBorder(GoFlyStyle.inputBorder, lineWidth: 0.75) }
        }
        .padding(16)
        .background(GoFlyStyle.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func toggleSelection(_ id: UUID) {
        if !selected.insert(id).inserted { selected.remove(id) }
    }

    private func delete(_ ids: Set<UUID>) {
        invalidateLoad()
        let count = ids.count
        Task {
            if await favorites.delete(ids) {
                if let loadedID = controller.loadedFavoriteRecordID, ids.contains(loadedID) {
                    controller.setLoadedFavoriteRecordID(nil)
                }
                selected.subtract(ids)
                if selected.isEmpty { selecting = false }
                snackbar = GoFlySnackbarMessage(
                    text: goFlyLocalizedFormat(goFlyString("favoriteRoutes.deletedCount"), count),
                    actionTitle: goFlyString("common.undo"),
                    action: {
                        invalidateLoad()
                        Task { _ = await favorites.undoDelete() }
                    }
                )
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
            if controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: admission) {
                controller.setLoadedFavoriteRecordID(record.id)
                onDismiss()
            } else {
                loadFailureKey = controller.error?.localizationKey
            }
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
                .padding(.vertical, 8)
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
