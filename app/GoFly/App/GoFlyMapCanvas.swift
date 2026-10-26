import GoFlyCore
import MapKit
import QuartzCore
import SwiftUI

struct GoFlyCameraIntent: Equatable {
    let id = UUID()
    let coordinate: GeoCoordinate
    var routeCoordinates: [GeoCoordinate]? = nil
    var ensureVisibleOnly = false
    var headingDegrees: Double? = nil
    /// Return to the default distance (about 1 km across the visible map).
    /// Otherwise a point intent only pans and keeps the person's zoom.
    var resetsZoom = false
    /// Pan only, placing the coordinate at this fraction of the map height
    /// from the top (e.g. 1/3 keeps it clear of a tall bottom panel).
    var verticalFraction: CGFloat? = nil

    init(coordinate: GeoCoordinate, ensureVisibleOnly: Bool = false, headingDegrees: Double? = nil,
         resetsZoom: Bool = false, verticalFraction: CGFloat? = nil) {
        self.coordinate = coordinate
        self.ensureVisibleOnly = ensureVisibleOnly
        self.headingDegrees = headingDegrees
        self.resetsZoom = resetsZoom
        self.verticalFraction = verticalFraction
    }
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
    let centerCoordinate: GeoCoordinate?
    let searchRegionLatitudeDelta: Double
    let searchRegionLongitudeDelta: Double

    var searchRegion: MKCoordinateRegion? {
        guard let centerCoordinate else { return nil }
        return MKCoordinateRegion(
            center: centerCoordinate.clLocationCoordinate,
            span: MKCoordinateSpan(
                latitudeDelta: searchRegionLatitudeDelta,
                longitudeDelta: searchRegionLongitudeDelta
            )
        )
    }

    @MainActor init(candidatePoint: CGPoint?, wanderTargetPoint: CGPoint? = nil, viewport: CGRect, map: MKMapView) {
        self.candidatePoint = candidatePoint
        self.wanderTargetPoint = wanderTargetPoint
        self.viewport = viewport
        self.cameraHeadingDegrees = map.camera.heading
        self.centerCoordinate = GeoCoordinate(latitude: map.centerCoordinate.latitude,
                                              longitude: map.centerCoordinate.longitude)
        self.searchRegionLatitudeDelta = map.region.span.latitudeDelta
        self.searchRegionLongitudeDelta = map.region.span.longitudeDelta
    }
}

struct GoFlyMapCanvas: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var marker: PositionMarker?
    var candidate: TeleportCandidate?
    var viewport: CGRect
    var cameraIntent: GoFlyCameraIntent?
    var route: PlannedRoute? = nil
    /// Numbered intermediate stops; when nil, 1/3 and 2/3 of long routes are marked.
    var routeWaypoints: [GeoCoordinate]? = nil
    var wanderTarget: MapPlace? = nil
    var markerBearingDegrees: Double? = nil
    var markerRoute: PlannedRoute? = nil
    var markerRouteDistance: Double? = nil
    var adjustsFocusForViewportChanges = true
    /// Keeps the Apple Maps logo and Legal link above the bottom panel, tab bar and cards.
    var attributionBottomInset: CGFloat = 0
    /// When set, tapping the route's destination node opens its card instead
    /// of passing the tap to the map.
    var onDestinationTap: (() -> Void)? = nil
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
        let margins = UIEdgeInsets(top: 0, left: 8, bottom: attributionBottomInset, right: 8)
        if map.layoutMargins != margins { map.layoutMargins = margins }
        coordinator.applyColorScheme(colorScheme, on: map)
        coordinator.applyAnnotationLocale(locale, on: map)
        coordinator.updateMarker(on: map)
        coordinator.updateRoute(on: map)
        coordinator.refreshAppearance(on: map)
        coordinator.applyCameraIfNeeded(on: map)
        coordinator.publishProjection(on: map)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: GoFlyMapCanvas
        private var positionAnnotation: PositionAnnotation?
        private var coordinateDisplayLink: CADisplayLink?
        private var displayedRouteDistance: Double?
        private var coordinateAnimationRoute: PlannedRoute?
        private var coordinateAnimationRouteStart: Double?
        private var coordinateAnimationRouteEnd: Double?
        private var coordinateAnimationStart: GeoCoordinate?
        private var coordinateAnimationTarget: GeoCoordinate?
        private var coordinateAnimationStartedAt: CFTimeInterval = 0
        private var coordinateAnimationDuration: CFTimeInterval = 0.45
        private var lastAcknowledgedUpdateAt: CFTimeInterval?
        private var lastMarker: PositionMarker?
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
        private var appliedRouteColor: CGColor?
        private var routeWaypointsApplied: [GeoCoordinate]?
        private var routeNodeAnnotations: [RouteNodeAnnotation] = []
        private var appliedNodeDark: Bool?
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
            // Runs on every SwiftUI update; redraw nodes only when the appearance flips.
            let dark = map.traitCollection.userInterfaceStyle == .dark
            if appliedNodeDark != dark {
                appliedNodeDark = dark
                for node in routeNodeAnnotations { map.view(for: node)?.image = node.kind.image(dark: dark) }
            }
            let color = UIColor.label.resolvedColor(with: map.traitCollection).cgColor
            if appliedRouteColor != color {
                appliedRouteColor = color
                routeRenderer?.strokeColor = UIColor(cgColor: color)
                routeRenderer?.setNeedsDisplay()
            }
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
            if let onDestinationTap = parent.onDestinationTap,
               let node = routeNodeAnnotations.last(where: { if case .destination = $0.kind { true } else { false } }),
               let view = map.view(for: node) {
                // At least a 44 pt hit target around the 22 pt node.
                let frame = view.frame.insetBy(dx: min(0, (view.frame.width - 44) / 2),
                                               dy: min(0, (view.frame.height - 44) / 2))
                if frame.contains(point) { onDestinationTap(); return }
            }
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
                stopCoordinateAnimation()
                if let positionAnnotation { map.removeAnnotation(positionAnnotation) }
                positionAnnotation = nil
                lastMarker = nil
                return
            }
            if let annotation = positionAnnotation {
                let shouldAnimate = !parent.reduceMotion && lastMarker?.source == .simulation && lastMarker?.freshness == .fresh
                    && marker.source == .simulation && marker.freshness == .fresh
                lastMarker = marker
                if shouldAnimate {
                    animateCoordinate(marker.coordinate, on: annotation)
                } else {
                    stopCoordinateAnimation()
                    annotation.coordinate = marker.coordinate.clLocationCoordinate
                    displayedRouteDistance = parent.markerRouteDistance
                }
            } else {
                lastMarker = marker
                let annotation = PositionAnnotation(marker.coordinate.clLocationCoordinate)
                positionAnnotation = annotation
                displayedRouteDistance = parent.markerRouteDistance
                map.addAnnotation(annotation)
            }
            updateMarkerAppearance(on: map)
        }

        private func animateCoordinate(_ target: GeoCoordinate, on annotation: PositionAnnotation) {
            let current = GeoCoordinate(latitude: annotation.coordinate.latitude,
                                        longitude: annotation.coordinate.longitude)
            guard let current else { return }
            if let animationTarget = coordinateAnimationTarget, animationTarget == target { return }
            stopCoordinateAnimation()
            let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude))
            // Route and wander acknowledge once a second (up to ~28 m at
            // 100 km/h); manual joystick steps arrive every half second.
            let now = CACurrentMediaTime()
            let interval = lastAcknowledgedUpdateAt.map { now - $0 } ?? 0.45
            lastAcknowledgedUpdateAt = now
            guard distance > 0.15, distance <= 60 else {
                annotation.coordinate = target.clLocationCoordinate
                displayedRouteDistance = parent.markerRouteDistance
                return
            }
            coordinateAnimationStart = current
            if let route = parent.markerRoute, let from = displayedRouteDistance,
               let to = parent.markerRouteDistance {
                coordinateAnimationRoute = route
                coordinateAnimationRouteStart = from
                coordinateAnimationRouteEnd = to
            }
            coordinateAnimationTarget = target
            coordinateAnimationStartedAt = now
            // Spread each move over the time until the next acknowledgement is
            // expected, at constant speed, so the arrow glides instead of
            // jumping between points. It still never runs ahead of an ACK.
            coordinateAnimationDuration = min(1.1, max(0.25, interval))
            let displayLink = CADisplayLink(target: self, selector: #selector(advanceCoordinateAnimation(_:)))
            // The glide runs for most of every second while moving; 30 fps keeps
            // it smooth without driving a ProMotion display at 120 Hz.
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            coordinateDisplayLink = displayLink
            displayLink.add(to: .main, forMode: .common)
        }

        @objc private func advanceCoordinateAnimation(_ displayLink: CADisplayLink) {
            guard let annotation = positionAnnotation,
                  let start = coordinateAnimationStart,
                  let target = coordinateAnimationTarget else {
                stopCoordinateAnimation()
                return
            }
            let elapsed = CACurrentMediaTime() - coordinateAnimationStartedAt
            let progress = min(1, max(0, elapsed / coordinateAnimationDuration))
            let eased = progress
            let latitude = start.latitude + (target.latitude - start.latitude) * eased
            var longitudeDelta = target.longitude - start.longitude
            if longitudeDelta > 180 { longitudeDelta -= 360 }
            if longitudeDelta < -180 { longitudeDelta += 360 }
            var longitude = start.longitude + longitudeDelta * eased
            if longitude > 180 { longitude -= 360 }
            if longitude < -180 { longitude += 360 }
            if let route = coordinateAnimationRoute, let from = coordinateAnimationRouteStart,
               let to = coordinateAnimationRouteEnd {
                let distance = from + (to - from) * eased
                displayedRouteDistance = distance
                annotation.coordinate = (route.coordinate(at: distance) ?? target).clLocationCoordinate
            } else {
                annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            guard progress >= 1 else { return }
            annotation.coordinate = target.clLocationCoordinate
            stopCoordinateAnimation()
        }

        private func stopCoordinateAnimation() {
            coordinateDisplayLink?.invalidate()
            coordinateDisplayLink = nil
            coordinateAnimationStart = nil
            coordinateAnimationTarget = nil
            coordinateAnimationRoute = nil
            coordinateAnimationRouteStart = nil
            coordinateAnimationRouteEnd = nil
        }

        private func updateMarkerAppearance(on map: MKMapView) {
            guard let marker = parent.marker, let annotation = positionAnnotation,
                  let view = map.view(for: annotation) as? GoFlyPositionArrowView else { return }
            view.apply(marker, bearingDegrees: parent.markerBearingDegrees, cameraHeadingDegrees: map.camera.heading)
        }

        func updateRoute(on map: MKMapView) {
            let points = parent.route?.points ?? []
            guard points != routePoints || parent.routeWaypoints != routeWaypointsApplied else { return }
            routePoints = points
            routeWaypointsApplied = parent.routeWaypoints
            map.removeAnnotations(routeNodeAnnotations)
            routeNodeAnnotations = []
            if let routeOverlay { map.removeOverlay(routeOverlay) }
            routeOverlay = nil
            routeRenderer = nil
            appliedRouteColor = nil
            guard points.count > 1 else { return }
            let coordinates = points.map(\.clLocationCoordinate)
            let overlay = MKPolyline(coordinates: coordinates, count: coordinates.count)
            routeOverlay = overlay
            map.addOverlay(overlay, level: .aboveRoads)
            var waypoints = parent.routeWaypoints ?? []
            if parent.routeWaypoints == nil, points.count >= 4 {
                waypoints = [points[points.count / 3], points[points.count * 2 / 3]]
            }
            var annotations = [RouteNodeAnnotation(points[0], kind: .start)]
            annotations += waypoints.enumerated().map { RouteNodeAnnotation($1, kind: .waypoint($0 + 1)) }
            annotations.append(RouteNodeAnnotation(points[points.count - 1], kind: .destination))
            routeNodeAnnotations = annotations
            map.addAnnotations(annotations)
        }

        func applyCameraIfNeeded(on map: MKMapView) {
            guard let intent = parent.cameraIntent,
                  map.bounds.width > 0, map.bounds.height > 0 else { return }
            let visible = parent.viewport.intersection(map.bounds)
            guard visible.width > 1, visible.height > 1,
                  intent.id != appliedIntent || ((parent.adjustsFocusForViewportChanges || intent.ensureVisibleOnly)
                    && (visible != appliedViewport || map.bounds != appliedBounds
                        || map.safeAreaInsets != appliedSafeArea)) else { return }
            appliedIntent = intent.id
            appliedViewport = visible
            appliedBounds = map.bounds
            appliedSafeArea = map.safeAreaInsets
            correctionsRemaining = 2
            if intent.ensureVisibleOnly {
                correctionsRemaining = 0
                let target = map.convert(intent.coordinate.clLocationCoordinate, toPointTo: map)
                let safe = visible.insetBy(dx: 24, dy: min(48, visible.height / 4))
                let desired = CGPoint(x: min(max(target.x, safe.minX), safe.maxX),
                                      y: min(max(target.y, safe.minY), safe.maxY))
                if abs(target.x - desired.x) > 0.5 || abs(target.y - desired.y) > 0.5 {
                    let center = map.convert(map.centerCoordinate, toPointTo: map)
                    map.setCenter(map.convert(CGPoint(x: center.x + target.x - desired.x,
                        y: center.y + target.y - desired.y), toCoordinateFrom: map), animated: false)
                }
                return
            }
            if let fraction = intent.verticalFraction {
                correctionsRemaining = 0
                hasFocused = true
                map.setCenter(intent.coordinate.clLocationCoordinate, animated: false)
                let center = map.convert(map.centerCoordinate, toPointTo: map)
                let desiredY = map.bounds.minY + map.bounds.height * min(max(fraction, 0), 1)
                map.setCenter(map.convert(CGPoint(x: center.x, y: center.y + center.y - desiredY),
                                          toCoordinateFrom: map), animated: false)
                return
            }
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
                // MapKit fits inside the layout margins (the attribution inset
                // already covers the panel), so pad only what they leave out.
                let margins = map.layoutMargins
                let routePadding = UIEdgeInsets(top: max(0, padding.top + 16 - margins.top),
                                                left: max(0, padding.left + 16 - margins.left),
                                                bottom: max(0, padding.bottom + 16 - margins.bottom),
                                                right: max(0, padding.right + 16 - margins.right))
                map.setVisibleMapRect(routeRect, edgePadding: routePadding, animated: false)
                // Pan the route's centre onto the viewport centre in case MapKit
                // still offsets the fitted rect.
                let routeCenter = MKMapPoint(x: routeRect.midX, y: routeRect.midY).coordinate
                let landed = map.convert(routeCenter, toPointTo: map)
                let center = map.convert(map.centerCoordinate, toPointTo: map)
                if abs(landed.x - visible.midX) > 0.5 || abs(landed.y - visible.midY) > 0.5 {
                    map.setCenter(map.convert(CGPoint(x: center.x + landed.x - visible.midX,
                        y: center.y + landed.y - visible.midY), toCoordinateFrom: map), animated: false)
                }
                return
            }
            if hasFocused && !intent.resetsZoom {
                // Pan only: refitting a rect at the current scale lets MapKit
                // round the zoom outwards a little on every intent.
                map.setCenter(intent.coordinate.clLocationCoordinate, animated: false)
            } else {
                let point = MKMapPoint(intent.coordinate.clLocationCoordinate)
                // Only the display's Mercator zoom scale is bounded near the poles;
                // the selected coordinate and device command remain unchanged.
                let scaleLatitude = min(85, max(-85, intent.coordinate.latitude))
                let scale = MKMapPointsPerMeterAtLatitude(scaleLatitude) * 1_000 / visible.width
                let width = max(1, visible.width * scale)
                let height = max(1, visible.height * scale)
                let rect = MKMapRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
                map.setVisibleMapRect(rect, edgePadding: padding, animated: false)
            }
            hasFocused = true
            correctFocusIfNeeded(on: map)
            if let heading = intent.headingDegrees {
                let camera = map.camera
                camera.heading = heading
                map.setCamera(camera, animated: false)
            }
        }

        func correctFocusIfNeeded(on map: MKMapView) {
            guard correctionsRemaining > 0, let intent = parent.cameraIntent,
                  intent.id == appliedIntent else { return }
            let target = map.convert(intent.coordinate.clLocationCoordinate, toPointTo: map)
            // A point focus lands at 1/3 of the map height in every mode, clear of the bottom panel.
            let delta = CGPoint(x: target.x - appliedViewport.midX,
                                y: target.y - (appliedBounds.minY + appliedBounds.height / 3))
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
            if let node = annotation as? RouteNodeAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "routeNode")
                    ?? MKAnnotationView(annotation: node, reuseIdentifier: "routeNode")
                view.annotation = node
                view.image = node.kind.image(dark: mapView.traitCollection.userInterfaceStyle == .dark)
                view.centerOffset = node.kind.centerOffset
                view.canShowCallout = false
                configureAccessibility(view, kind: node.kind)
                return view
            }
            guard annotation is PositionAnnotation, let marker = parent.marker else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "position") as? GoFlyPositionArrowView
                ?? GoFlyPositionArrowView(annotation: annotation, reuseIdentifier: "position")
            view.annotation = annotation
            view.apply(marker, bearingDegrees: parent.markerBearingDegrees, cameraHeadingDegrees: mapView.camera.heading)
            return view
        }

        /// A tappable destination is a VoiceOver button; activation taps its
        /// center, which reaches `mapTapped`.
        private func configureAccessibility(_ view: MKAnnotationView, kind: RouteNodeAnnotation.Kind) {
            guard case .destination = kind, parent.onDestinationTap != nil else {
                view.isAccessibilityElement = false
                return
            }
            view.isAccessibilityElement = true
            view.accessibilityTraits = .button
            view.accessibilityLabel = goFlyString("search.placeDetails")
            view.accessibilityValue = parent.wanderTarget.map {
                goFlyLocalizedFormat(goFlyString("joystick.currentTarget"), $0.title)
            }
            view.accessibilityIdentifier = "map.route.destination"
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

private final class RouteNodeAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case start, waypoint(Int), destination

        var centerOffset: CGPoint { .zero }

        /// Figma `MapNode /` components: white ring start, numbered waypoints,
        /// and a thick destination dot without a stem, centred on the route end.
        /// Dark mode inverts them like the `Dark · MapNode /` components.
        func image(dark: Bool) -> UIImage {
            let ink: UIColor = dark ? .white : .black
            let paper: UIColor = dark ? UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : .white
            switch self {
            case .start:
                return Self.render(CGSize(width: 22, height: 22)) { rect in
                    paper.setFill(); UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
                    let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 4.5, dy: 4.5))
                    ring.lineWidth = 3; ink.setStroke(); ring.stroke()
                }
            case .waypoint(let number):
                return Self.render(CGSize(width: 24, height: 24)) { rect in
                    let circle = rect.insetBy(dx: 2, dy: 2)
                    paper.setFill(); UIBezierPath(ovalIn: circle).fill()
                    let ring = UIBezierPath(ovalIn: circle.insetBy(dx: 1.25, dy: 1.25))
                    ring.lineWidth = 2.5; ink.setStroke(); ring.stroke()
                    let text = NSAttributedString(string: "\(number)", attributes: [
                        .font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: ink])
                    let size = text.size()
                    text.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
                }
            case .destination:
                return Self.render(CGSize(width: 22, height: 22)) { rect in
                    ink.setFill(); UIBezierPath(ovalIn: rect).fill()
                    paper.setFill(); UIBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8)).fill()
                }
            }
        }

        private static func render(_ size: CGSize, _ draw: @escaping (CGRect) -> Void) -> UIImage {
            UIGraphicsImageRenderer(size: size).image { _ in draw(CGRect(origin: .zero, size: size)) }
        }
    }

    @objc dynamic var coordinate: CLLocationCoordinate2D
    let kind: Kind
    init(_ coordinate: GeoCoordinate, kind: Kind) {
        self.coordinate = coordinate.clLocationCoordinate
        self.kind = kind
    }
}

private final class PositionAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}


extension GeoCoordinate {
    /// Figma shows five decimals in visible coordinate text; `displayText` stays the stable key.
    var shortDisplayText: String {
        String(format: "%.5f, %.5f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
    var clLocationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
