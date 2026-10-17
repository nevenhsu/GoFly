import GoFlyCore
import MapKit
import SwiftUI

/// A document preview. Separate overlays preserve gaps, and singleton segments
/// remain visible as samples rather than becoming invented connecting lines.
struct GoFlyGPXPreview: View {
    let document: GPXDocument

    var body: some View {
        GPXDocumentMap(document: document)
            .frame(minHeight: 200, idealHeight: 240, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(goFlyString("imports.preview"))
            .accessibilityValue(goFlyLocalizedFormat(goFlyString("imports.preview.summary"),
                                                                document.pointCount, document.segments.count))
            .accessibilityIdentifier("imports.preview")
            .overlay(alignment: .topLeading) {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
                    VStack {
                        Text(document.pointCount, format: .number).accessibilityIdentifier("imports.preview.points")
                        Text(document.segments.count, format: .number).accessibilityIdentifier("imports.preview.segments")
                    }
                    .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                }
                #endif
            }
    }
}

private struct GPXDocumentMap: UIViewRepresentable {
    let document: GPXDocument
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> GPXPreviewMapView {
        let map = GPXPreviewMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.showsCompass = false
        map.isPitchEnabled = false
        map.selectableMapFeatures = []
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "gpx.sample")
        let coordinator = context.coordinator
        map.onLayout = { [weak map, weak coordinator] in
            guard let map, let coordinator else { return }
            coordinator.fitIfNeeded(map)
        }
        return map
    }
    func updateUIView(_ map: GPXPreviewMapView, context: Context) {
        context.coordinator.update(document, on: map)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        private var document: GPXDocument?
        private var bounds: MKMapRect?
        private var fittedSize = CGSize.zero
        private var needsFit = false

        func update(_ document: GPXDocument, on map: MKMapView) {
            guard self.document != document else { fitIfNeeded(map); return }
            self.document = document
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            for segment in document.segments {
                let coordinates = segment.map(\.clLocationCoordinate)
                if coordinates.count == 1, let coordinate = coordinates.first {
                    let sample = MKPointAnnotation()
                    sample.coordinate = coordinate
                    map.addAnnotation(sample)
                } else if coordinates.count > 1 {
                    map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count), level: .aboveRoads)
                }
            }
            let coordinates = document.segments.flatMap { $0 }.map(\.clLocationCoordinate)
            let outline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            bounds = outline.boundingMapRect
            needsFit = true
            fitIfNeeded(map)
        }
        func fitIfNeeded(_ map: MKMapView) {
            guard let bounds, map.bounds.width > 0, map.bounds.height > 0,
                  needsFit || fittedSize != map.bounds.size else { return }
            let latitude = document?.segments.first?.first?.latitude ?? 0
            let minimum = MKMapPointsPerMeterAtLatitude(min(85, max(-85, latitude))) * 100
            let rect = bounds.insetBy(dx: -max(0, minimum - bounds.width) / 2,
                                     dy: -max(0, minimum - bounds.height) / 2)
            needsFit = false
            fittedSize = map.bounds.size
            map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16), animated: false)
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .label
            renderer.lineWidth = 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "gpx.sample", for: annotation)
            if let marker = view as? MKMarkerAnnotationView {
                marker.markerTintColor = .label
                marker.glyphTintColor = .systemBackground
                marker.glyphImage = UIImage(systemName: "mappin")
                marker.clusteringIdentifier = "gpx.samples"
                marker.canShowCallout = false
            }
            return view
        }
    }
}

private final class GPXPreviewMapView: MKMapView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
