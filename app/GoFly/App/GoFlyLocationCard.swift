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
    var onPrimaryAction: () -> Void
    var onDismiss: () -> Void
    var onCopy: (() -> Void)? = nil
    var distanceFrom: GeoCoordinate? = nil
    var identifier: String = "locationCard"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title
            Text(place.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GoFlyStyle.primary)
                .lineLimit(1)
                .padding(.trailing, 32)
                .accessibilityIdentifier("\(identifier).title")

            Text(place.address ?? "")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(GoFlyStyle.secondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier).address")

            Text(coordinateLine)
                .font(.system(size: 12, weight: .regular).monospacedDigit())
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("\(identifier).coordinates")

            Spacer(minLength: 12)

            // Bottom action row matching B5 (Go 77pt, Favorite 86pt, Copy 86pt, height 40pt)
            HStack(spacing: 8) {
                // Primary CTA (black solid)
                Button(action: onPrimaryAction) {
                    HStack(spacing: 4) {
                        if primaryActionType == .teleport {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(resolvedPrimaryTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(primaryEnabled ? GoFlyStyle.surface : GoFlyStyle.disabledForeground)
                    .frame(minWidth: 77)
                    .frame(height: 40)
                    .padding(.horizontal, 14)
                    .background(primaryEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledSurface, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!primaryEnabled)
                .accessibilityIdentifier("\(identifier).primaryAction")

                // Favorite button
                GoFlyFavoriteStar(place: place, identifier: "\(identifier).favorite",
                                  labelTitle: goFlyString("placeDetails.favorite"))

                // Copy button
                Button {
                    UIPasteboard.general.string = place.coordinate.displayText
                    onCopy?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .medium))
                        Text(goFlyString("placeDetails.copy"))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(minWidth: 86)
                    .frame(height: 40)
                    .background(GoFlyStyle.secondarySurface, in: Capsule())
                    .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("placeDetails.copy"))
                .accessibilityIdentifier("\(identifier).copy")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 18)
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
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("\(identifier).dismiss")
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 5)
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
