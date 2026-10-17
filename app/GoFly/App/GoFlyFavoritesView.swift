import GoFlyCore
import SwiftUI

struct GoFlyFavoritesView: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    var candidate: MapPlace?
    var onSelect: (MapPlace) -> Void
    var onSearch: () -> Void
    var onDismiss: () -> Void
    @State private var editing: FavoritePlace?

    var body: some View {
        NavigationStack {
            if let editing {
                GoFlyFavoriteLabelEditor(favorite: editing) { self.editing = nil }
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        GoFlyFavoriteFailureNotice()
                        if favorites.loadState == .ready, favorites.favorites.isEmpty {
                            Text(goFlyString("favorites.empty"))
                                .font(.body)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .accessibilityIdentifier("favorites.empty")
                        }
                        ForEach(favorites.favorites) { favorite in
                            GoFlyPlaceOptionCard(
                                place: favorite.place, title: favorite.displayTitle,
                                selected: candidate.flatMap(FavoritePlaceKey.init(place:)) == favorite.key,
                                selectionIdentifier: "favorites.place.\(favorite.place.coordinate.displayText)",
                                starIdentifier: "favorites.star.\(favorite.place.coordinate.displayText)",
                                onSelect: { onSelect(favorite.place) },
                                onLongPress: { editing = favorite }
                            )
                        }
                        Button(goFlyString("favorites.search"), action: onSearch)
                            .buttonStyle(GoFlyActionStyle())
                            .accessibilityIdentifier("favorites.search")
                    }
                    .padding(16)
                }
                .navigationTitle(goFlyString("favorites.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(goFlyString("common.dismiss"), action: onDismiss)
                            .accessibilityIdentifier("favorites.dismiss")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
    }
}

private struct GoFlyFavoriteLabelEditor: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let favorite: FavoritePlace
    var onReturn: () -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(favorite: FavoritePlace, onReturn: @escaping () -> Void) {
        self.favorite = favorite
        self.onReturn = onReturn
        _draft = State(initialValue: favorite.label ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Text(goFlyString("favorites.editLabel"))
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GoFlyFavoriteStar(place: favorite.place, identifier: "favorites.editor.star")
                }
                Text(favorite.place.title).font(.body)
                TextField(goFlyString("favorites.label"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .accessibilityIdentifier("favorites.editor.label")
                if !favorites.isFavorite(favorite.place) {
                    Text(goFlyString("favorites.removed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .accessibilityIdentifier("favorites.editor.removed")
                }
                GoFlyFavoriteFailureNotice()
            }
            .padding(24)
        }
        .accessibilityIdentifier("favorites.editor.form")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(goFlyString("favorites.save")) {
                    if favorites.saveLabel(for: favorite.key, draft: draft) { onReturn() }
                }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!favorites.canMutate || !favorites.isFavorite(favorite.place))
                .accessibilityIdentifier("favorites.editor.save")
                Button(goFlyString("favorites.cancel")) {
                    favorites.clearError()
                    onReturn()
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("favorites.editor.cancel")
            }
            .padding(16)
            .background(GoFlyStyle.surface)
        }
        .background(GoFlyStyle.surface)
        .task { focused = true }
    }
}
