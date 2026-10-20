import GoFlyCore
import SwiftUI

struct GoFlyFavoritesView: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    var candidate: MapPlace?
    var onSelect: (MapPlace) -> Void
    var onSearch: () -> Void
    var onDismiss: () -> Void
    @State private var editing: FavoritePlace?
    @State private var query = ""
    @State private var selecting = false
    @State private var selected: Set<FavoritePlaceKey> = []
    @State private var pending: [FavoritePlaceKey: Task<Void, Never>] = [:]
    @State private var snackbar: GoFlySnackbarMessage?

    private var visible: [FavoritePlace] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return favorites.favorites.filter {
            text.isEmpty || [$0.displayTitle, $0.place.title, $0.place.address ?? "", $0.place.coordinate.displayText]
                .contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    failureNotice
                    if favorites.loadState == .ready, visible.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.favorite,
                            message: goFlyString(query.isEmpty ? "favorites.empty" : "favorites.noMatches"))
                            .padding(.vertical, 24)
                            .accessibilityIdentifier("favorites.empty")
                    }
                    ForEach(visible) { favorite in
                        row(favorite)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
            .safeAreaInset(edge: .bottom) { bottomSearch }
        }
        .background(GoFlyStyle.surface)
        .goFlySnackbar($snackbar)
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
        .sheet(item: $editing) { favorite in
            GoFlyFavoriteLabelEditor(favorite: favorite, onReturn: { editing = nil }) {
                delete([favorite.key])
                if !favorites.isFavorite(favorite.place) { editing = nil }
            }
        }
    }

    /// Figma C1 uses a plain title bar: 選取 on the left, the title in the
    /// middle and a bare close glyph on the right, without a navigation bar.
    private var header: some View {
        ZStack {
            Text(goFlyString("favorites.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(goFlyString(selecting ? "favorites.cancel" : "favorites.select")) {
                    selecting.toggle()
                    selected.removeAll()
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.select")
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: GoFlySymbols.close)
                        .goFlyControlSymbol(size: 17, weight: .semibold)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("common.dismiss"))
                .accessibilityIdentifier("favorites.dismiss")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder private var failureNotice: some View {
        if let failure = failure {
            GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue),
                onDismiss: favorites.canMutate ? { favorites.clearError() } : nil,
                identifier: "favorites.error")
                .padding(.vertical, 12)
        }
    }

    private var failure: FavoritePlacesFailure? {
        if case .blocked(let failure) = favorites.loadState { return failure }
        return favorites.error
    }

    private var bottomSearch: some View {
        VStack(spacing: 12) {
            if selecting {
                Button(goFlyLocalizedFormat(goFlyString("favorites.deleteCount"), selected.count)) {
                    delete(selected)
                }
                .buttonStyle(GoFlyActionStyle())
                .foregroundStyle(GoFlyStyle.errorForeground)
                .disabled(selected.isEmpty || !favorites.canMutate)
                .accessibilityIdentifier("favorites.deleteSelected")
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(GoFlyStyle.secondary)
                TextField(goFlyString("favorites.searchSaved"), text: $query)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .accessibilityIdentifier("favorites.search")
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
        }
        .padding(16)
        .background(GoFlyStyle.surface)
    }

    private func row(_ favorite: FavoritePlace) -> some View {
        HStack(spacing: 4) {
            Button {
                if selecting { toggleSelection(favorite.key) }
                else { togglePending(favorite) }
            } label: {
                Image(systemName: selecting
                    ? (selected.contains(favorite.key) ? "checkmark.circle.fill" : "circle")
                    : (pending[favorite.key] == nil ? GoFlySymbols.favoriteSelected : GoFlySymbols.favorite))
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(!favorites.canMutate)
            .accessibilityLabel(goFlyString(selecting ? "favorites.select"
                : (pending[favorite.key] == nil ? "favorites.remove" : "favorites.cancel")))
            .accessibilityValue(goFlyString(pending[favorite.key] == nil ? "favorites.saved" : "favorites.pendingRemoval"))
            .accessibilityIdentifier("favorites.star.\(favorite.place.coordinate.displayText)")
            Button {
                if selecting { toggleSelection(favorite.key) }
                else { onSelect(favorite.place) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.displayTitle).font(.body.weight(.semibold))
                    if let subtitle = favoriteSubtitle(favorite) {
                        Text(subtitle)
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected.contains(favorite.key)
                || candidate.flatMap(FavoritePlaceKey.init(place:)) == favorite.key ? .isSelected : [])
            .accessibilityIdentifier("favorites.place.\(favorite.place.coordinate.displayText)")
            if !selecting {
                Button {
                    editing = favorite
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.editLabel"))
                .accessibilityIdentifier("favorites.edit.\(favorite.place.coordinate.displayText)")
            }
        }
        .foregroundStyle(GoFlyStyle.primary)
    }

    /// A coordinate favorite already shows its coordinate as the title; the
    /// Figma list shows one subtitle, never the same line twice.
    private func favoriteSubtitle(_ favorite: FavoritePlace) -> String? {
        if let address = favorite.place.address, !address.isEmpty { return address }
        let coordinate = favorite.place.coordinate.displayText
        return favorite.displayTitle == coordinate ? nil : coordinate
    }

    private func toggleSelection(_ key: FavoritePlaceKey) {
        if !selected.insert(key).inserted { selected.remove(key) }
    }

    private func togglePending(_ favorite: FavoritePlace) {
        if let task = pending.removeValue(forKey: favorite.key) { task.cancel(); return }
        pending[favorite.key] = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            guard !Task.isCancelled else { return }
            pending.removeValue(forKey: favorite.key)
            delete([favorite.key])
        }
    }

    private func delete(_ keys: Set<FavoritePlaceKey>) {
        let count = favorites.favorites.filter { keys.contains($0.key) }.count
        guard favorites.delete(keys) else { return }
        selected.subtract(keys)
        snackbar = GoFlySnackbarMessage(
            text: goFlyLocalizedFormat(goFlyString("favorites.deletedCount"), count),
            actionTitle: goFlyString("common.undo"), action: { _ = favorites.undoDelete() })
    }
}

private struct GoFlyFavoriteLabelEditor: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let favorite: FavoritePlace
    var onReturn: () -> Void
    var onDelete: () -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(favorite: FavoritePlace, onReturn: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.favorite = favorite
        self.onReturn = onReturn
        self.onDelete = onDelete
        _draft = State(initialValue: favorite.label ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(goFlyString("favorites.label"), text: $draft)
                        .focused($focused).submitLabel(.done)
                        .onSubmit { focused = false }
                        .accessibilityIdentifier("favorites.editor.label")
                    Text(favorite.place.title)
                    if let address = favorite.place.address { Text(address).foregroundStyle(GoFlyStyle.secondary) }
                    Text(favorite.place.coordinate.displayText).foregroundStyle(GoFlyStyle.secondary)
                }
                Section {
                    Button(role: .destructive, action: onDelete) { Text(goFlyString("favorites.delete")) }
                        .disabled(!favorites.canMutate)
                        .accessibilityIdentifier("favorites.editor.delete")
                }
                if let failure = favorites.error {
                    GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue), identifier: "favorites.error")
                }
            }
            .accessibilityIdentifier("favorites.editor.form")
            .navigationTitle(goFlyString("favorites.editLabel"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(goFlyString("favorites.cancel")) { favorites.clearError(); onReturn() }
                        .accessibilityIdentifier("favorites.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(goFlyString("favorites.save")) {
                        if favorites.saveLabel(for: favorite.key, draft: draft) { onReturn() }
                    }
                    .disabled(!favorites.canMutate || !favorites.isFavorite(favorite.place))
                    .accessibilityIdentifier("favorites.editor.save")
                }
            }
        }
        .task { focused = true }
    }
}
