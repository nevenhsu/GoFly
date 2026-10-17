import GoFlyCore
import MapKit
import SwiftUI

struct GoFlyCameraIntent: Equatable {
    let id = UUID()
    let coordinate: GeoCoordinate
    var routeCoordinates: [GeoCoordinate]? = nil

    init(coordinate: GeoCoordinate) { self.coordinate = coordinate }
    init(route: PlannedRoute) {
        coordinate = route.start
        routeCoordinates = route.points
    }
}

struct GoFlyMapProjection: Equatable {
    let candidatePoint: CGPoint?
    let viewport: CGRect
    #if DEBUG && targetEnvironment(simulator)
    private(set) var routePointCount = 0
    private(set) var routeIsVisible = false
    #endif

    @MainActor init(candidatePoint: CGPoint?, viewport: CGRect, map: MKMapView) {
        self.candidatePoint = candidatePoint
        self.viewport = viewport
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            let lines = map.overlays.compactMap { $0 as? MKPolyline }
            routePointCount = lines.reduce(0) { $0 + $1.pointCount }
            if !lines.isEmpty {
                let bounds = lines.reduce(MKMapRect.null) { $0.union($1.boundingMapRect) }
                let corners = [MKMapPoint(x: bounds.minX, y: bounds.minY),
                               MKMapPoint(x: bounds.maxX, y: bounds.minY),
                               MKMapPoint(x: bounds.minX, y: bounds.maxY),
                               MKMapPoint(x: bounds.maxX, y: bounds.maxY)]
                    .map { map.convert($0.coordinate, toPointTo: map) }
                let minimumX = corners.map(\.x).min()!, maximumX = corners.map(\.x).max()!
                let minimumY = corners.map(\.y).min()!, maximumY = corners.map(\.y).max()!
                let screenBounds = CGRect(x: minimumX, y: minimumY,
                                          width: maximumX - minimumX, height: maximumY - minimumY)
                    .insetBy(dx: -0.5, dy: -0.5)
                routeIsVisible = viewport.insetBy(dx: -2, dy: -2).contains(screenBounds)
            }
        }
        #endif
    }
}

struct GoFlyMapCanvas: UIViewRepresentable {
    var marker: PositionMarker?
    var candidate: TeleportCandidate?
    var viewport: CGRect
    var cameraIntent: GoFlyCameraIntent?
    var route: PlannedRoute? = nil
    var onMapTap: (GeoCoordinate) -> Void
    var onProjection: (GoFlyMapProjection) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = LayoutMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.showsCompass = false
        map.selectableMapFeatures = []
        map.isPitchEnabled = false
        map.layoutMargins = .zero
        map.insetsLayoutMarginsFromSafeArea = false
        map.accessibilityIdentifier = "map.canvas"
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mapTapped(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .visible
        compass.accessibilityIdentifier = "map.compass"
        map.addSubview(compass)
        context.coordinator.compass = compass
        let coordinator = context.coordinator
        map.onLayout = { [weak map, weak coordinator] in
            guard let map, let coordinator else { return }
            coordinator.applyCameraIfNeeded(on: map)
            coordinator.correctFocusIfNeeded(on: map)
            coordinator.publishProjection(on: map)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.updateMarker(on: map)
        coordinator.updateRoute(on: map)
        coordinator.compass?.frame = CGRect(x: max(0, map.bounds.width - 60), y: max(0, viewport.minY + 12), width: 44, height: 44)
        coordinator.applyCameraIfNeeded(on: map)
        coordinator.publishProjection(on: map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: GoFlyMapCanvas
        var compass: MKCompassButton?
        private var positionAnnotation: PositionAnnotation?
        private var appliedIntent: UUID?
        private var appliedViewport = CGRect.zero
        private var appliedBounds = CGRect.zero
        private var appliedSafeArea = UIEdgeInsets.zero
        private var correctionsRemaining = 0
        private var hasFocused = false
        private var publication: UInt64 = 0
        private var routePoints: [GeoCoordinate] = []
        private var routeOverlay: MKPolyline?

        init(_ parent: GoFlyMapCanvas) { self.parent = parent }

        @objc func mapTapped(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            guard parent.viewport.contains(point) else { return }
            let coordinate = map.convert(point, toCoordinateFrom: map)
            guard let valid = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return }
            parent.onMapTap(valid)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view, current !== gestureRecognizer.view {
                if current is UIControl || current is MKAnnotationView { return false }
                view = current.superview
            }
            return true
        }

        func updateMarker(on map: MKMapView) {
            guard let marker = parent.marker else {
                if let positionAnnotation { map.removeAnnotation(positionAnnotation) }
                positionAnnotation = nil
                return
            }
            if let annotation = positionAnnotation {
                annotation.coordinate = marker.coordinate.clLocationCoordinate
            } else {
                let annotation = PositionAnnotation(marker.coordinate.clLocationCoordinate)
                positionAnnotation = annotation
                map.addAnnotation(annotation)
            }
            if let annotation = positionAnnotation, let view = map.view(for: annotation) as? PositionAnnotationView {
                view.apply(marker)
            }
        }

        func updateRoute(on map: MKMapView) {
            let points = parent.route?.points ?? []
            guard points != routePoints else { return }
            routePoints = points
            if let routeOverlay { map.removeOverlay(routeOverlay) }
            routeOverlay = nil
            guard points.count > 1 else { return }
            let coordinates = points.map(\.clLocationCoordinate)
            let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
            routeOverlay = overlay
            map.addOverlay(overlay, level: .aboveRoads)
        }

        func applyCameraIfNeeded(on map: MKMapView) {
            guard let intent = parent.cameraIntent,
                  map.bounds.width > 0, map.bounds.height > 0 else { return }
            let visible = parent.viewport.intersection(map.bounds)
            guard visible.width > 1, visible.height > 1,
                  intent.id != appliedIntent || visible != appliedViewport
                    || map.bounds != appliedBounds || map.safeAreaInsets != appliedSafeArea else { return }
            appliedIntent = intent.id
            appliedViewport = visible
            appliedBounds = map.bounds
            appliedSafeArea = map.safeAreaInsets
            correctionsRemaining = 2
            let padding = UIEdgeInsets(
                top: visible.minY, left: visible.minX,
                bottom: map.bounds.maxY - visible.maxY, right: map.bounds.maxX - visible.maxX
            )
            if let routeCoordinates = intent.routeCoordinates, routeCoordinates.count > 1 {
                let coordinates = routeCoordinates.map(\.clLocationCoordinate)
                let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                let minimumSize = MKMapPointsPerMeterAtLatitude(min(85, max(-85, intent.coordinate.latitude))) * 100
                let bounds = polyline.boundingMapRect
                let routeRect = bounds.insetBy(dx: -max(0, minimumSize - bounds.width) / 2,
                                              dy: -max(0, minimumSize - bounds.height) / 2)
                correctionsRemaining = 0
                hasFocused = true
                let routePadding = UIEdgeInsets(top: padding.top + 16, left: padding.left + 16,
                                                bottom: padding.bottom + 16, right: padding.right + 16)
                map.setVisibleMapRect(routeRect, edgePadding: routePadding, animated: false)
                return
            }
            let point = MKMapPoint(intent.coordinate.clLocationCoordinate)
            let currentScale = map.visibleMapRect.width / map.bounds.width
            // Only the display's Mercator zoom scale is bounded near the poles;
            // the selected coordinate and device command remain unchanged.
            let scaleLatitude = min(85, max(-85, intent.coordinate.latitude))
            let initialScale = MKMapPointsPerMeterAtLatitude(scaleLatitude) * 1_000 / visible.width
            let scale = hasFocused && currentScale.isFinite && currentScale > 0 ? currentScale : initialScale
            let width = max(1, visible.width * scale)
            let height = max(1, visible.height * scale)
            let rect = MKMapRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
            hasFocused = true
            map.setVisibleMapRect(rect, edgePadding: padding, animated: false)
            correctFocusIfNeeded(on: map)
        }

        func correctFocusIfNeeded(on map: MKMapView) {
            guard correctionsRemaining > 0, let intent = parent.cameraIntent,
                  intent.id == appliedIntent else { return }
            let target = map.convert(intent.coordinate.clLocationCoordinate, toPointTo: map)
            let delta = CGPoint(x: target.x - appliedViewport.midX, y: target.y - appliedViewport.midY)
            guard abs(delta.x) > 0.5 || abs(delta.y) > 0.5 else {
                correctionsRemaining = 0
                return
            }
            correctionsRemaining -= 1
            let center = map.convert(map.centerCoordinate, toPointTo: map)
            let adjusted = map.convert(CGPoint(x: center.x + delta.x, y: center.y + delta.y), toCoordinateFrom: map)
            map.setCenter(adjusted, animated: false)
        }

        func publishProjection(on map: MKMapView) {
            publication &+= 1
            let revision = publication
            let point = parent.candidate.map { map.convert($0.place.coordinate.clLocationCoordinate, toPointTo: map) }
            let snapshot = GoFlyMapProjection(candidatePoint: point, viewport: parent.viewport, map: map)
            Task { @MainActor [weak self] in
                guard let self, self.publication == revision else { return }
                self.parent.onProjection(snapshot)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            correctFocusIfNeeded(on: mapView)
            publishProjection(on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if mapView.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
                correctionsRemaining = 0
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            publishProjection(on: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is PositionAnnotation, let marker = parent.marker else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "position") as? PositionAnnotationView
                ?? PositionAnnotationView(annotation: annotation, reuseIdentifier: "position")
            view.annotation = annotation
            view.apply(marker)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .label
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}

private final class LayoutMapView: MKMapView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class PositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

private final class PositionAnnotationView: MKAnnotationView {
    private let fill = UIImageView(image: UIImage(systemName: "location.north.fill"))
    private let edge = UIImageView(image: UIImage(systemName: "location.north"))

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        let configuration = UIImage.SymbolConfiguration(textStyle: .title2)
            .applying(UIImage.SymbolConfiguration(weight: .semibold))
        for image in [fill, edge] {
            image.preferredSymbolConfiguration = configuration
            image.contentMode = .scaleAspectFit
            image.frame = bounds
            image.isAccessibilityElement = false
            addSubview(image)
        }
        fill.tintColor = .label
        edge.tintColor = .systemBackground
        isAccessibilityElement = true
        accessibilityIdentifier = "map.positionMarker"
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ marker: PositionMarker) {
        alpha = marker.freshness == .waiting ? 0.5 : 1
        let key: String
        switch (marker.source, marker.freshness) {
        case (.gps, .fresh): key = "map.realLocation"
        case (.gps, .waiting): key = "map.realLocationWaiting"
        case (.simulation, .fresh): key = "map.simulatedLocation"
        case (.simulation, .waiting): key = "map.simulatedLocationWaiting"
        }
        accessibilityLabel = goFlyString(key)
        accessibilityValue = marker.coordinate.displayText
    }
}

extension GeoCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
