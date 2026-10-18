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
    let wanderTargetPoint: CGPoint?
    let viewport: CGRect
    let cameraHeadingDegrees: Double
    #if DEBUG && targetEnvironment(simulator)
    private(set) var routePointCount = 0
    private(set) var routeIsVisible = false
    private(set) var mapInstanceID = ""
    private(set) var mapUserInterfaceStyle = UIUserInterfaceStyle.unspecified.rawValue
    private(set) var cameraStateToken = 0
    #endif

    @MainActor init(candidatePoint: CGPoint?, wanderTargetPoint: CGPoint? = nil, viewport: CGRect, map: MKMapView) {
        self.candidatePoint = candidatePoint
        self.wanderTargetPoint = wanderTargetPoint
        self.viewport = viewport
        self.cameraHeadingDegrees = map.camera.heading
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            mapInstanceID = String(describing: ObjectIdentifier(map))
            mapUserInterfaceStyle = map.traitCollection.userInterfaceStyle.rawValue
            var cameraHasher = Hasher()
            cameraHasher.combine(map.camera.centerCoordinate.latitude)
            cameraHasher.combine(map.camera.centerCoordinate.longitude)
            cameraHasher.combine(map.camera.altitude)
            cameraHasher.combine(map.camera.pitch)
            cameraHasher.combine(map.camera.heading)
            cameraStateToken = cameraHasher.finalize()
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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    var marker: PositionMarker?
    var candidate: TeleportCandidate?
    var viewport: CGRect
    var cameraIntent: GoFlyCameraIntent?
    var route: PlannedRoute? = nil
    var wanderTarget: MapPlace? = nil
    var markerBearingDegrees: Double? = nil
    var adjustsFocusForViewportChanges = true
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
        map.onTraitChange = { [weak map, weak coordinator] in
            guard let map, let coordinator else { return }
            coordinator.refreshAppearance(on: map)
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyColorScheme(colorScheme, on: map)
        coordinator.applyAnnotationLocale(locale, on: map)
        coordinator.updateMarker(on: map)
        coordinator.updateRoute(on: map)
        coordinator.refreshAppearance(on: map)
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
        private var routeRenderer: MKPolylineRenderer?
        private var annotationLocaleIdentifier = ""

        init(_ parent: GoFlyMapCanvas) { self.parent = parent }

        func applyColorScheme(_ colorScheme: ColorScheme?, on map: MKMapView) {
            let style: UIUserInterfaceStyle
            switch colorScheme {
            case .light: style = .light
            case .dark: style = .dark
            default: style = .unspecified
            }
            if map.overrideUserInterfaceStyle != style {
                map.overrideUserInterfaceStyle = style
            }
        }

        func refreshAppearance(on map: MKMapView) {
            updateMarkerAppearance(on: map)
            routeRenderer?.strokeColor = .label
            routeRenderer?.setNeedsDisplay()
        }

        func applyAnnotationLocale(_ locale: Locale, on map: MKMapView) {
            guard annotationLocaleIdentifier != locale.identifier else { return }
            annotationLocaleIdentifier = locale.identifier
            updateMarkerAppearance(on: map)
        }

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
            updateMarkerAppearance(on: map)
        }

        private func updateMarkerAppearance(on map: MKMapView) {
            guard let marker = parent.marker, let annotation = positionAnnotation,
                  let view = map.view(for: annotation) as? GoFlyPositionArrowView else { return }
            view.apply(marker, bearingDegrees: parent.markerBearingDegrees, cameraHeadingDegrees: map.camera.heading)
        }

        func updateRoute(on map: MKMapView) {
            let points = parent.route?.points ?? []
            guard points != routePoints else { return }
            routePoints = points
            if let routeOverlay { map.removeOverlay(routeOverlay) }
            routeOverlay = nil
            routeRenderer = nil
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
                  intent.id != appliedIntent || (parent.adjustsFocusForViewportChanges
                    && (visible != appliedViewport || map.bounds != appliedBounds
                        || map.safeAreaInsets != appliedSafeArea)) else { return }
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
            let target = parent.wanderTarget.map { map.convert($0.coordinate.clLocationCoordinate, toPointTo: map) }
            let snapshot = GoFlyMapProjection(candidatePoint: point, wanderTargetPoint: target,
                                             viewport: parent.viewport, map: map)
            Task { @MainActor [weak self] in
                guard let self, self.publication == revision else { return }
                self.parent.onProjection(snapshot)
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            correctFocusIfNeeded(on: mapView)
            updateMarkerAppearance(on: mapView)
            publishProjection(on: mapView)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if mapView.gestureRecognizers?.contains(where: { $0.state == .began || $0.state == .changed }) == true {
                correctionsRemaining = 0
            }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            updateMarkerAppearance(on: mapView)
            publishProjection(on: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard annotation is PositionAnnotation, let marker = parent.marker else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "position") as? GoFlyPositionArrowView
                ?? GoFlyPositionArrowView(annotation: annotation, reuseIdentifier: "position")
            view.annotation = annotation
            view.apply(marker, bearingDegrees: parent.markerBearingDegrees, cameraHeadingDegrees: mapView.camera.heading)
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .label
            renderer.lineWidth = 4
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if let routeOverlay, routeOverlay === line {
                routeRenderer = renderer
            }
            return renderer
        }
    }
}

private final class LayoutMapView: MKMapView {
    var onLayout: (() -> Void)?
    var onTraitChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerTraitChanges()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerTraitChanges()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    private func registerTraitChanges() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LayoutMapView, previousTraitCollection) in
            guard previousTraitCollection.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
            view.onTraitChange?()
        }
    }
}

private final class PositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}


extension GeoCoordinate {
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
