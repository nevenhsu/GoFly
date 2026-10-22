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
                        Divider().padding(.leading, 48)
                    }
                }
                .padding(.horizontal, 20)
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

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if selecting { selecting = false; selected.removeAll() }
                else { onDismiss() }
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
            .accessibilityIdentifier("favorites.dismiss")
            Spacer(minLength: 0)
            Text(selecting
                 ? goFlyLocalizedFormat(goFlyString("favorites.selectedCount"), selected.count)
                 : goFlyString("favorites.title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if selecting {
                Button {
                    let keys = Set(visible.map(\.key))
                    if keys.isSubset(of: selected) { selected.subtract(keys) }
                    else { selected.formUnion(keys) }
                } label: {
                    Text(goFlyString("favorites.selectAll"))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.selectAll")
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
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.select")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 10)
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
            .overlay { RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius).strokeBorder(GoFlyStyle.inputBorder, lineWidth: 0.75) }
        }
        .padding(16)
        .background(GoFlyStyle.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private func row(_ favorite: FavoritePlace) -> some View {
        HStack(spacing: 4) {
            if selecting {
                Button {
                    toggleSelection(favorite.key)
                } label: {
                    GoFlyCheckboxIcon(selected: selected.contains(favorite.key), size: 22)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("favorites.select"))
                .accessibilityIdentifier("favorites.checkbox.\(favorite.place.coordinate.displayText)")
            } else {
                GoFlyStarIcon(size: 16, filled: true)
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.secondarySurface, in: Circle())
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            Button {
                if selecting { toggleSelection(favorite.key) }
                else { onSelect(favorite.place) }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(favorite.displayTitle).font(.body)
                    if let subtitle = favoriteSubtitle(favorite) {
                        Text(subtitle)
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(goFlyString("favorites.cancel")) { favorites.clearError(); onReturn() }
                    .accessibilityIdentifier("favorites.editor.cancel")
                Spacer()
                Text(goFlyString("favorites.editLabel")).font(.headline)
                Spacer()
                Button(goFlyString("favorites.save")) {
                    if favorites.saveLabel(for: favorite.key, draft: draft) { onReturn() }
                }
                .fontWeight(.semibold)
                .disabled(!favorites.canMutate || !favorites.isFavorite(favorite.place))
                .accessibilityIdentifier("favorites.editor.save")
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let failure = favorites.error {
                        GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue), identifier: "favorites.error")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyString("favorites.label"))
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                        HStack {
                            TextField(goFlyString("favorites.label"), text: $draft)
                                .focused($focused).submitLabel(.done)
                                .onSubmit { focused = false }
                                .accessibilityIdentifier("favorites.editor.label")
                            if !draft.isEmpty {
                                Button { draft = "" } label: {
                                    Image(systemName: "xmark").frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .accessibilityLabel(goFlyString("search.clear"))
                            }
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder, lineWidth: focused ? 1.5 : 0.75) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(favorite.place.address ?? favorite.place.title).font(.subheadline)
                        Text(favorite.place.coordinate.displayText)
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .accessibilityIdentifier("favorites.editor.form")
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive, action: onDelete) {
                    HStack(spacing: 8) {
                        GoFlyTrashIcon(size: 17)
                        Text(goFlyString("favorites.delete"))
                    }
                    .foregroundStyle(GoFlyStyle.dangerForeground)
                }
                .buttonStyle(GoFlyActionStyle())
                .foregroundStyle(GoFlyStyle.dangerForeground)
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.editor.delete")
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .background(GoFlyStyle.cardSurface)
            }
        }
        .background(GoFlyStyle.cardSurface)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(338), .large])
        .presentationDragIndicator(.visible)
    }
}
