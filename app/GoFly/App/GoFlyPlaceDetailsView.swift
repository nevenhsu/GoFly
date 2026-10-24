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
    var primaryTitleKey = "map.go"
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
        VStack(alignment: .leading, spacing: 6) {
            GoFlyFavoriteFailureNotice()
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: GoFlySymbols.close)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("common.dismiss"))
                .accessibilityIdentifier("placeDetails.dismiss")
            }
            Text(place.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(GoFlyStyle.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("placeDetails.title")
            if place.address != nil || place.title != place.coordinate.displayText {
                Text(place.address ?? goFlyString("placeDetails.addressUnavailable"))
                    .font(.subheadline).foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityIdentifier("placeDetails.address")
            }
            Text(coordinateLine)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(GoFlyStyle.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier("placeDetails.coordinates")
            ScrollView(.horizontal, showsIndicators: false) {
                actions.padding(.horizontal, 20).padding(.vertical, 2)
            }
            .padding(.horizontal, -20)
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var coordinateLine: String {
        guard let distance = distanceMeters else { return place.coordinate.shortDisplayText }
        let formatted: String
        if distance < 1_000 {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceMeters"), Int(distance.rounded()))
        } else {
            formatted = goFlyLocalizedFormat(goFlyString("placeDetails.distanceKilometers"),
                                             String(format: "%.1f", arguments: [distance / 1_000]))
        }
        return "\(place.coordinate.shortDisplayText) · \(formatted)"
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
                Button(action: onGo) {
                    Text(goFlyString(primaryTitleKey))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(canGo ? GoFlyStyle.primary : GoFlyStyle.disabledSurface, in: Capsule())
                        .foregroundStyle(canGo ? GoFlyStyle.surface : GoFlyStyle.disabledForeground)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canGo)
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
                        .padding(.horizontal, 14)
                        .frame(height: 40)
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
                    .padding(.horizontal, 14)
                    .frame(height: 40)
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
