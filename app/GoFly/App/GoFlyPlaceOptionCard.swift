import GoFlyCore
import SwiftUI

struct GoFlyFavoriteStar: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let place: MapPlace
    var identifier: String
    /// The place sheet shows the Figma labeled pill; lists and pins keep the icon.
    var labelTitle: String? = nil

    var body: some View {
        Button { _ = favorites.toggle(place) } label: {
            if let labelTitle {
                Label(labelTitle, systemImage: symbol)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(GoFlyStyle.secondarySurface, in: Capsule())
                    .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    .contentShape(Capsule())
            } else {
                Image(systemName: symbol)
                    .goFlyControlSymbol(size: 20, weight: .semibold)
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
