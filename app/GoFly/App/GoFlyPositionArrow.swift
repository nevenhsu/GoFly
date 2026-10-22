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
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        drawing.frame = bounds
        layer.addSublayer(drawing)
        for shape in [contrast, arrow] {
            shape.frame = bounds
            shape.lineCap = .butt
            shape.lineJoin = .miter
            shape.miterLimit = 4
            shape.contentsScale = traitCollection.displayScale
            drawing.addSublayer(shape)
        }
        let path = Self.path(in: bounds)
        contrast.path = path
        arrow.path = path
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
        let labelColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
        let bgColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
        contrast.fillColor = UIColor.clear.cgColor
        contrast.strokeColor = bgColor
        if source == .simulation {
            arrow.fillColor = labelColor
            arrow.strokeColor = bgColor
            arrow.lineWidth = 1.5
            contrast.lineWidth = 3.5
        } else {
            arrow.fillColor = UIColor.clear.cgColor
            arrow.strokeColor = labelColor
            arrow.lineWidth = 2.5
            contrast.lineWidth = 5.0
        }
    }

    private static func path(in rect: CGRect) -> CGPath {
        let arrowWidth: CGFloat = 24
        let arrowHeight: CGFloat = 27
        let originX = rect.midX - arrowWidth / 2
        let originY = rect.midY - arrowHeight / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: originX + 12, y: originY + 0))
        path.addLine(to: CGPoint(x: originX + 24, y: originY + 27))
        path.addLine(to: CGPoint(x: originX + 12, y: originY + 21))
        path.addLine(to: CGPoint(x: originX + 0, y: originY + 27))
        path.closeSubpath()
        return path
    }
}
