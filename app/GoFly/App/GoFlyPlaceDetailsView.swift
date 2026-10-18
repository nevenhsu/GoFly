import GoFlyCore
import SwiftUI

/// The caller captures this place when its Pin is tapped; later candidates do
/// not change either the displayed information or the star's identity.
struct GoFlyPlaceDetailsView: View {
    let place: MapPlace
    var onDismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: GoFlySymbols.place)
                            .goFlyControlSymbol(size: 24, weight: .medium)
                            .foregroundStyle(GoFlyStyle.primary)
                            .frame(width: 48, height: 48)
                            .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                        Text(place.title)
                            .font(.title2.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("placeDetails.title")
                        GoFlyFavoriteStar(place: place, identifier: "placeDetails.favorite")
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Label(goFlyString("placeDetails.address"), systemImage: "map")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoFlyStyle.secondary)
                            Text(place.address ?? goFlyString("placeDetails.addressUnavailable"))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("placeDetails.address")
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 7) {
                            Label(goFlyString("placeDetails.coordinates"), systemImage: GoFlySymbols.coordinates)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(GoFlyStyle.secondary)
                            Text(place.coordinate.displayText)
                                .font(.body.monospacedDigit())
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("placeDetails.coordinates")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .goFlyCard()
                    GoFlyFavoriteFailureNotice()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(GoFlyStyle.canvas)
            .navigationTitle(goFlyString("search.placeDetails"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(goFlyString("common.dismiss"), action: onDismiss)
                        .accessibilityIdentifier("placeDetails.dismiss")
                }
            }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationBackground(GoFlyStyle.canvas)
    }
}
