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
                .goFlyDismissesKeyboardOnTap()
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
                            .font(GoFlyFont.body)
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
            .scrollDismissesKeyboard(.immediately)
            .goFlyDismissesKeyboardOnTap()
            .accessibilityIdentifier("favoriteRoutes.content")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GoFlyFavoritesBottomBar(
                    placeholder: goFlyString("favoriteRoutes.searchSaved"), query: $query,
                    searchIdentifier: "favoriteRoutes.search",
                    deleteTitle: selecting ? goFlyLocalizedFormat(goFlyString("favorites.deleteCount"), selected.count) : nil,
                    deleteEnabled: !selected.isEmpty && favorites.canMutate,
                    deleteIdentifier: "favoriteRoutes.deleteSelected",
                    onDelete: { delete(selected) })
            }
        }
        .background(GoFlyStyle.surface)
        .goFlySnackbar($snackbar, bottomPadding: GoFlyFavoritesBottomBar.snackbarOffset)
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
        GoFlySheetHeader(title: selecting
                         ? goFlyLocalizedFormat(goFlyString("favorites.selectedCount"), selected.count)
                         : goFlyString("favoriteRoutes.title")) {
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
                        Label(goFlyString("mode.route"), systemImage: "chevron.backward")
                            .labelStyle(.titleAndIcon)
                    }
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favoriteRoutes.dismiss")
        } trailing: {
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
                // Same editor as ⋯ (2026-10-26).
                Button { edit(record) } label: {
                    GoFlyStarIcon(size: 16, filled: true)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .frame(width: 36, height: 36)
                        .background(GoFlyStyle.secondarySurface, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityLabel(goFlyString("favoriteRoutes.editLabel"))
                .accessibilityIdentifier("favoriteRoutes.star.\(record.id.uuidString)")
            }

            Button {
                if selecting { toggleSelection(record.id) }
                else { load(record) }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(record.label ?? goFlyFavoriteRouteEndpoints(record))
                        .font(GoFlyFont.body)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .lineLimit(1)
                    Text(goFlyFavoriteRouteSubtitle(record))
                        .font(GoFlyFont.footnote)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .lineLimit(1)
                    if let failure = favorites.unavailable[record.id] {
                        Text(goFlyString(failure.localizationKey))
                            .font(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.danger)
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
                        .foregroundStyle(GoFlyTextColor.secondary)
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
                selecting = false
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
            let button = goFlyIssueButton(for: key, retry: { Task { await favorites.load() } })
            GoFlyStatusBanner(tone: .danger, title: goFlyString(key), actionTitle: button.title,
                              onAction: button.action, identifier: "favoriteRoutes.error")
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

/// D19 subtitle: endpoints (when a label is the title) joined with the point count.
@MainActor
func goFlyFavoriteRouteSubtitle(_ record: FavoriteRouteRecord) -> String {
    let count = goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
        ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count)
    guard record.label != nil else { return count }
    return goFlyFavoriteRouteEndpoints(record) + "・" + count
}
