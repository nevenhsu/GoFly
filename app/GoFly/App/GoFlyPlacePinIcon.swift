import SwiftUI

enum GoFlyPlacePinKind: Equatable {
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
                        .frame(width: 5, height: 24).padding(.top, 18)
                    Capsule().fill(GoFlyStyle.primary)
                        .frame(width: 2, height: 23).padding(.top, 18)
                    Circle().fill(GoFlyStyle.primary)
                        .frame(width: 24, height: 24)
                        .overlay { Circle().fill(GoFlyStyle.surface).frame(width: 8, height: 8) }
                        .shadow(color: .black.opacity(0.16), radius: 2, y: 2)
                }
                .frame(width: 30, height: 44)
            }
        }
        .frame(width: 30, height: kind == .candidate ? 44 : 36, alignment: .bottom)
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
