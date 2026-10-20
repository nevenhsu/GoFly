import CoreLocation
import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyPlaceDetailsView: View {
    let place: MapPlace
    var onDismiss: () -> Void
    var embedded = false
    /// Current simulated position, used only to show the Figma distance line.
    var distanceFrom: GeoCoordinate?
    var canGo = false
    var onGo: (() -> Void)? = nil
    var onRouteStart: (() -> Void)? = nil
    var onRouteEnd: (() -> Void)? = nil

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                ScrollView { content }
                    .background(GoFlyStyle.surface)
                    .navigationTitle(goFlyString("search.placeDetails"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            GoFlyFavoriteFailureNotice()
            HStack(alignment: .top) {
                Text(place.title).font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("placeDetails.title")
                Button(action: onDismiss) { Image(systemName: GoFlySymbols.close) }
                    .buttonStyle(GoFlyIconStyle())
                    .accessibilityLabel(goFlyString("common.dismiss"))
                    .accessibilityIdentifier("placeDetails.dismiss")
            }
            Text(place.address ?? goFlyString("placeDetails.addressUnavailable"))
                .font(.subheadline).foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("placeDetails.address")
            Text(coordinateLine)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(GoFlyStyle.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("placeDetails.coordinates")
            ScrollView(.horizontal, showsIndicators: false) {
                actions
            }
        }
        .padding(16)
    }

    private var coordinateLine: String {
        guard let distance = distanceMeters else { return place.coordinate.displayText }
        let formatted: String
        if distance < 1_000 {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceMeters"), Int(distance.rounded()))
        } else {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceKilometers"),
                                             String(format: "%.1f", arguments: [distance / 1_000]))
        }
        return "\(place.coordinate.displayText) · \(formatted)"
    }

    private var distanceMeters: Double? {
        guard let distanceFrom else { return nil }
        let from = CLLocation(latitude: distanceFrom.latitude, longitude: distanceFrom.longitude)
        let to = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let value = from.distance(from: to)
        return value.isFinite ? value : nil
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let onGo {
                Button(goFlyString("map.go"), action: onGo)
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .frame(minWidth: 56).disabled(!canGo)
                    .accessibilityIdentifier("placeDetails.go")
            }
            GoFlyFavoriteStar(place: place, identifier: "placeDetails.favorite",
                              labelTitle: goFlyString("placeDetails.favorite"))
            if onRouteStart != nil || onRouteEnd != nil {
                Menu {
                    if let onRouteStart { Button(goFlyString("placeDetails.setStart"), action: onRouteStart) }
                    if let onRouteEnd { Button(goFlyString("placeDetails.setEnd"), action: onRouteEnd) }
                } label: {
                    Label(goFlyString("placeDetails.setEnd"), systemImage: GoFlySymbols.flag)
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(GoFlyStyle.secondarySurface, in: Capsule())
                        .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                        .contentShape(Capsule())
                }
                .accessibilityLabel(goFlyString("placeDetails.setEnd"))
                .accessibilityIdentifier("placeDetails.route")
            }
            Button {
                UIPasteboard.general.string = place.coordinate.displayText
            } label: {
                Label(goFlyString("placeDetails.copy"), systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(GoFlyStyle.secondarySurface, in: Capsule())
                    .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("placeDetails.copy"))
            .accessibilityIdentifier("placeDetails.copy")
        }
        .buttonStyle(.plain)
    }
}
