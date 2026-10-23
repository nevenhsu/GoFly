import GoFlyCore
import SwiftUI

struct GoFlyFavoriteStar: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let place: MapPlace
    var identifier: String
    /// The place sheet shows the Figma labeled pill; lists and pins keep the icon.
    var labelTitle: String? = nil
    @State private var showingEditor = false

    var body: some View {
        Button { showingEditor = true } label: {
            if let labelTitle {
                HStack(spacing: 6) {
                    GoFlyStarIcon(size: 16, filled: favorites.isFavorite(place))
                    Text(labelTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(GoFlyStyle.secondarySurface, in: Capsule())
                .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Capsule())
            } else {
                GoFlyStarIcon(size: 18, filled: favorites.isFavorite(place))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(favorites.canMutate ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
        .disabled(!favorites.canMutate)
        .accessibilityLabel(goFlyString(favorites.canMutate
            ? (favorites.isFavorite(place) ? "favorites.remove" : "favorites.add") : "favorites.title"))
        .accessibilityValue(goFlyString(favorites.canMutate
            ? (favorites.isFavorite(place) ? "favorites.saved" : "favorites.notSaved") : "favorites.unavailable"))
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $showingEditor) {
            GoFlyFavoriteEditorSheet(place: place, initialLabel: favorites.favorite(for: place)?.label, onDismiss: { showingEditor = false })
        }
    }

    private var symbol: String {
        favorites.isFavorite(place) ? GoFlySymbols.favoriteSelected : GoFlySymbols.favorite
    }
}

struct GoFlyFavoriteFailureNotice: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    var maximumHeight: CGFloat? = nil
    @State private var contentHeight: CGFloat = 64

    var body: some View {
        if let failure {
            if let maximumHeight {
                ScrollView {
                    notice(failure)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                }
                .frame(height: min(contentHeight, maximumHeight))
            } else {
                notice(failure)
            }
        }
    }

    private func notice(_ failure: FavoritePlacesFailure) -> some View {
        GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue),
            onDismiss: favorites.canMutate ? { favorites.clearError() } : nil,
            identifier: "favorites.error")
    }

    private var failure: FavoritePlacesFailure? {
        if case .blocked(let failure) = favorites.loadState { return failure }
        return favorites.error
    }
}
