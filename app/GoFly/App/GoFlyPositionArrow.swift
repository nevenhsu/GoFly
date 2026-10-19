import GoFlyCore
import MapKit
import SwiftUI

/// A position has an arrow silhouette, never the place pin's round head.
/// Both layers share one path, so the contrast keyline cannot drift from the fill.
final class GoFlyPositionArrowView: MKAnnotationView {
    private let contrast = CAShapeLayer()
    private let arrow = CAShapeLayer()
    private let drawing = CALayer()
    private var source = PositionSource.gps

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 40, height: 44)
        drawing.frame = bounds
        layer.addSublayer(drawing)
        for shape in [contrast, arrow] {
            shape.frame = bounds
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.contentsScale = traitCollection.displayScale
            drawing.addSublayer(shape)
        }
        let path = Self.path(in: bounds.insetBy(dx: 5, dy: 5))
        contrast.path = path
        contrast.lineWidth = 5
        arrow.path = path
        arrow.lineWidth = 2
        isAccessibilityElement = true
        accessibilityIdentifier = "map.positionMarker"
        canShowCallout = false
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (view: GoFlyPositionArrowView, _: UITraitCollection) in view.applyColors()
        }
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func apply(_ marker: PositionMarker, bearingDegrees: Double?, cameraHeadingDegrees: Double) {
        applyAppearance(source: marker.source, freshness: marker.freshness,
                        bearingDegrees: bearingDegrees, cameraHeadingDegrees: cameraHeadingDegrees)
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

    /// The preview exercises these same production layers without inventing a GPS fix or ACK.
    func applyAppearance(source: PositionSource, freshness: PositionFreshness,
                         bearingDegrees: Double?, cameraHeadingDegrees: Double) {
        self.source = source
        alpha = freshness == .waiting ? 0.5 : 1
        let radians = bearingDegrees.map { ($0 - cameraHeadingDegrees) * .pi / 180 } ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        drawing.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(radians)))
        applyColors()
        CATransaction.commit()
    }

    private func applyColors() {
        contrast.fillColor = UIColor.clear.cgColor
        contrast.strokeColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
        arrow.strokeColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
        arrow.fillColor = source == .simulation
            ? UIColor.label.resolvedColor(with: traitCollection).cgColor : UIColor.clear.cgColor
    }

    private static func path(in rect: CGRect) -> CGPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: p(0.47, 0.05))
        path.addQuadCurve(to: p(0.53, 0.05), control: p(0.5, 0))
        path.addLine(to: p(0.96, 0.92))
        path.addQuadCurve(to: p(0.92, 0.97), control: p(1, 1))
        path.addLine(to: p(0.52, 0.76))
        path.addQuadCurve(to: p(0.48, 0.76), control: p(0.5, 0.75))
        path.addLine(to: p(0.08, 0.97))
        path.addQuadCurve(to: p(0.04, 0.92), control: p(0, 1))
        path.closeSubpath()
        return path
    }
}
