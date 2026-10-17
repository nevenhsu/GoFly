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
                    HStack(alignment: .top, spacing: 12) {
                        Text(place.title)
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("placeDetails.title")
                        GoFlyFavoriteStar(place: place, identifier: "placeDetails.favorite")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyString("placeDetails.address")).font(.subheadline.weight(.semibold))
                        Text(place.address ?? goFlyString("placeDetails.addressUnavailable"))
                            .font(.body)
                            .accessibilityIdentifier("placeDetails.address")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyString("placeDetails.coordinates")).font(.subheadline.weight(.semibold))
                        Text(place.coordinate.displayText)
                            .font(.body)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("placeDetails.coordinates")
                    }
                    GoFlyFavoriteFailureNotice()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .background(GoFlyStyle.surface)
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
        .presentationBackground(GoFlyStyle.surface)
    }
}
