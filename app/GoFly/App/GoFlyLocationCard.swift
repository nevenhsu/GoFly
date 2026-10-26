import CoreLocation
import GoFlyCore
import SwiftUI
import UIKit

public enum LocationCardPrimaryAction: Equatable, Sendable {
    case confirm
    case teleport
    case custom(String)

    public var titleKey: String {
        switch self {
        case .confirm: return "common.confirm" // "確認"
        case .teleport: return "map.go" // "Go"
        case .custom(let str): return str
        }
    }
}

/// Floating location details card (D4, D2a, E5)
///
/// Features:
/// - Minimum height 188 pt, corner radius 16 pt, double-layer soft shadow.
/// - Sits above narrowest bottom panel at y = 573, 16 pt above TabBar.
/// - Primary CTA button: solid black capsule with text "確認" (D4) or "Go".
/// - Secondary buttons: Favorite star button and Copy coordinates button.
/// - Dismiss (✕) button in top right.
struct GoFlyLocationCard: View {
    let place: MapPlace
    var primaryActionType: LocationCardPrimaryAction = .confirm
    var primaryActionTitle: String? = nil
    var primaryEnabled: Bool = true
    /// Nil hides the primary button (place details opened without a Go action).
    var onPrimaryAction: (() -> Void)?
    var onRouteStart: (() -> Void)? = nil
    var onRouteEnd: (() -> Void)? = nil
    var onDismiss: () -> Void
    var onCopy: (() -> Void)? = nil
    var distanceFrom: GeoCoordinate? = nil
    var identifier: String = "locationCard"

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            Text(place.title)
                .font(GoFlyFont.title)
                .foregroundStyle(GoFlyTextColor.primary)
                .lineLimit(1)
                .padding(.trailing, 32)
                .accessibilityIdentifier("\(identifier).title")

            Text(place.address ?? "")
                .font(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).address")

            Text(coordinateLine)
                .font(GoFlyFont.caption.monospacedDigit())
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityIdentifier("\(identifier).coordinates")

            Spacer(minLength: 12)

            // Bottom action row matching B5 (Go 77pt, Favorite 86pt, Copy 86pt, height 40pt)
            HStack(spacing: 8) {
                // Primary CTA (black solid)
                if let onPrimaryAction {
                Button(action: onPrimaryAction) {
                    HStack(spacing: 4) {
                        if primaryActionType == .teleport {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(resolvedPrimaryTitle)
                            .font(GoFlyFont.subheadlineEmphasis)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 77)
                    .frame(height: 40)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(GoFlyCardPrimaryStyle())
                .goFlySteadyDisabled(!primaryEnabled)
                .accessibilityIdentifier("\(identifier).primaryAction")
                }

                Spacer(minLength: 0)

                if onRouteStart != nil || onRouteEnd != nil {
                    Menu {
                        if let onRouteStart { Button(goFlyString("placeDetails.setStart"), action: onRouteStart) }
                        if let onRouteEnd { Button(goFlyString("placeDetails.setEnd"), action: onRouteEnd) }
                    } label: {
                        Image(systemName: GoFlySymbols.flag)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 40, height: 40)
                            .background(GoFlyStyle.secondarySurface, in: Circle())
                            .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(goFlyString("placeDetails.setEnd"))
                    .accessibilityIdentifier("\(identifier).route")
                }

                // Favorite button
                GoFlyFavoriteStar(place: place, identifier: "\(identifier).favorite", isCardAction: true)

                GoFlyCopyIconButton(coordinate: place.coordinate, identifier: "\(identifier).copy", onCopy: onCopy)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(height: 188)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
        }
        // Dismiss (✕) button pinned to top-right corner matching Figma B5 (24x24 at x:323, y:14)
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 16)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("\(identifier).dismiss")
        }
        .goFlyShadow(.card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var resolvedPrimaryTitle: String {
        if let primaryActionTitle { return primaryActionTitle }
        switch primaryActionType {
        case .confirm: return goFlyString("common.confirm")
        case .teleport: return goFlyString("map.go")
        case .custom(let str): return str
        }
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
}

/// Icon-only copy-coordinates button shared by the location card and the collapsed position summary.
struct GoFlyCopyIconButton: View {
    let coordinate: GeoCoordinate
    var identifier: String
    var onCopy: (() -> Void)? = nil

    var body: some View {
        Button {
            UIPasteboard.general.string = coordinate.displayText
            onCopy?()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 40)
                .background(GoFlyStyle.secondarySurface, in: Circle())
                .overlay { Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goFlyString("placeDetails.copy"))
        .accessibilityIdentifier(identifier)
    }
}
