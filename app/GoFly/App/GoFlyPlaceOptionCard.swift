import GoFlyCore
import SwiftUI

struct GoFlyFavoriteStar: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let place: MapPlace
    var identifier: String

    var body: some View {
        Button { _ = favorites.toggle(place) } label: {
            Image(systemName: favorites.isFavorite(place) ? GoFlySymbols.favoriteSelected : GoFlySymbols.favorite)
                .goFlyControlSymbol(size: 20, weight: .semibold)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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
}

struct GoFlyPlaceOptionCard: View {
    let place: MapPlace
    var title: String? = nil
    var selected: Bool
    var selectionIdentifier: String
    var starIdentifier: String
    var onSelect: () -> Void
    var onLongPress: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 0) {
            if let onLongPress {
                titleView
                    .contentShape(Rectangle())
                    .gesture(LongPressGesture(minimumDuration: 0.6).exclusively(before: TapGesture())
                        .onEnded { gesture in
                            switch gesture {
                            case .first: onLongPress()
                            case .second: onSelect()
                            }
                        })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title ?? place.title)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityAction { onSelect() }
                    .accessibilityAction(named: Text(goFlyString("favorites.editLabel"))) { onLongPress() }
                    .accessibilityIdentifier(selectionIdentifier)
            } else {
                Button(action: onSelect) { titleView }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier(selectionIdentifier)
            }
            GoFlyFavoriteStar(place: place, identifier: starIdentifier)
                .padding(.trailing, 6)
        }
        .frame(minHeight: 56)
        .background(selected ? GoFlyStyle.secondarySurface : GoFlyStyle.surface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius)
                .strokeBorder(selected ? GoFlyStyle.primary : GoFlyStyle.subtleBorder, lineWidth: selected ? 1.5 : 0.5)
                .allowsHitTesting(false)
        }
    }

    private var titleView: some View {
        Text(title ?? place.title)
            .font(.body.weight(selected ? .semibold : .regular))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.leading, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
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
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: GoFlySymbols.warning).accessibilityHidden(true)
                Text(goFlyString(failure.rawValue))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("favorites.error")
                if favorites.canMutate {
                    Button { favorites.clearError() } label: {
                        Image(systemName: GoFlySymbols.close)
                            .goFlyControlSymbol(size: 14, maximum: 18, weight: .semibold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("common.dismiss"))
                    .accessibilityIdentifier("favorites.error.dismiss")
                }
            }
            .foregroundStyle(GoFlyStyle.errorForeground)
            .padding(12)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var failure: FavoritePlacesFailure? {
        if case .blocked(let failure) = favorites.loadState { return failure }
        return favorites.error
    }
}
