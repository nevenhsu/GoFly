import SwiftUI

enum GoFlyPlacePinKind {
    case destination, candidate
}

struct GoFlyPlacePinIcon: View {
    let kind: GoFlyPlacePinKind

    var body: some View {
        Group {
            switch kind {
            case .destination:
                ZStack(alignment: .top) {
                    DestinationPinOutline()
                        .fill(GoFlyStyle.surface)
                        .overlay { DestinationPinOutline().stroke(GoFlyStyle.surface, lineWidth: 4) }
                        .overlay { DestinationPinOutline().stroke(GoFlyStyle.primary, lineWidth: 2) }
                    Circle()
                        .stroke(GoFlyStyle.primary, lineWidth: 2)
                        .frame(width: 7, height: 7)
                        .padding(.top, 8)
                }
                .frame(width: 23, height: 34)
            case .candidate:
                ZStack(alignment: .top) {
                    Capsule().fill(GoFlyStyle.surface)
                        .frame(width: 5, height: 28).padding(.top, 7)
                    Capsule().fill(GoFlyStyle.primary)
                        .frame(width: 2, height: 27).padding(.top, 7)
                    Circle().fill(GoFlyStyle.primary)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().strokeBorder(GoFlyStyle.surface, lineWidth: 1.5) }
                }
                .frame(width: 14, height: 35)
            }
        }
        .frame(width: 24, height: 36, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

private struct DestinationPinOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: point(0.5, 1))
        path.addCurve(to: point(0, 0.36), control1: point(0.28, 0.79), control2: point(0, 0.56))
        path.addCurve(to: point(0.5, 0), control1: point(0, 0.14), control2: point(0.22, 0))
        path.addCurve(to: point(1, 0.36), control1: point(0.78, 0), control2: point(1, 0.14))
        path.addCurve(to: point(0.5, 1), control1: point(1, 0.56), control2: point(0.72, 0.79))
        path.closeSubpath()
        return path
    }
}
