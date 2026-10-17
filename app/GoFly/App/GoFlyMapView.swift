import GoFlyCore
import MapKit
import SwiftUI
import UIKit

struct GoFlyMapView: View {
    @ObservedObject var service: ServiceController
    @StateObject private var location = GoFlyRealLocation()
    @State private var camera: MapCameraPosition = .automatic
    @State private var showingSettings = false
    @State private var serviceNoticeDismissed = false

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                if let position = service.realLocation {
                    Annotation(
                        goFlyString("map.realLocation"),
                        coordinate: CLLocationCoordinate2D(
                            latitude: position.latitude,
                            longitude: position.longitude
                        )
                    ) {
                        Image(systemName: "location.north.fill")
                            .foregroundStyle(GoFlyStyle.primary)
                            .overlay {
                                Image(systemName: "location.north")
                                    .foregroundStyle(GoFlyStyle.surface)
                                    .accessibilityHidden(true)
                            }
                            .font(.title2.weight(.semibold))
                            .accessibilityLabel(goFlyString("map.realLocation"))
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapControls { MapCompass() }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 8) {
                    statusCard
                    if let error = service.error, !serviceNoticeDismissed {
                        serviceFailureNotice(error)
                    }
                    if let notice = location.noticeKey {
                        locationNotice(notice)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
                Button {
                    location.requestRecenter()
                } label: {
                    Image(systemName: "location.viewfinder")
                }
                .buttonStyle(GoFlyIconStyle())
                .accessibilityLabel(goFlyString("map.recenter"))
                .accessibilityHint(goFlyString("map.recenterHint"))
                .padding(16)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingSettings) {
                ServiceSettingsView(service: service)
            }
            .onReceive(service.$error) { error in
                serviceNoticeDismissed = false
                if let error {
                    UIAccessibility.post(notification: .announcement, argument: goFlyString(error.rawValue))
                }
            }
            .onReceive(location.$observation) { observation in
                service.observeRealLocation(observation)
                guard observation != nil else { return }
                guard let accepted = service.realLocation else {
                    location.rejectedFix()
                    return
                }
                location.acceptedFix()
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: accepted.latitude, longitude: accepted.longitude
                    ),
                    latitudinalMeters: 1_000,
                    longitudinalMeters: 1_000
                ))
            }
        }
        .tint(GoFlyStyle.primary)
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(goFlyString("map.currentLocation"))
                    .font(.headline)
                Text(goFlyString(service.statusKey))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("map.positionStatus")

            Button {
                _ = service.start()
            } label: {
                if service.phase == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: service.phase == .ready ? "pause.fill" : "play.fill")
                }
            }
            .disabled(!service.canStart)
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString(
                service.nativeBusy ? service.statusKey : (service.phase == .ready ? "map.pause" : "service.start")
            ))
            .accessibilityHint(goFlyString(service.canStart ? "map.startServiceHint" : "map.noActiveTask"))
            .accessibilityIdentifier("map.serviceControl")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(goFlyString("settings.title"))
            .accessibilityIdentifier("map.settings")
        }
        .padding(16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private func locationNotice(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(goFlyString(key))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            Button {
                location.dismissNotice()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("common.dismiss"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("map.locationNotice")
    }

    private func serviceFailureNotice(_ error: DeviceServiceFailure) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .padding(.top, 12)
                .accessibilityHidden(true)
            Text(goFlyString(error.rawValue))
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .accessibilityIdentifier("map.serviceError.message")
            Button {
                serviceNoticeDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("common.dismiss"))
            .accessibilityIdentifier("map.serviceError.dismiss")
        }
        .foregroundStyle(GoFlyStyle.errorForeground)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
