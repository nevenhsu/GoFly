import SwiftUI

enum GoFlyWanderPinKind {
    case destination, candidate
}

struct GoFlyWanderPinIcon: View {
    let kind: GoFlyWanderPinKind

    var body: some View {
        Group {
            switch kind {
            case .destination:
                ZStack(alignment: .top) {
                    DestinationPinOutline()
                        .fill(GoFlyStyle.surface)
                        .overlay { DestinationPinOutline().stroke(GoFlyStyle.primary, lineWidth: 2) }
                    Circle()
                        .stroke(GoFlyStyle.primary, lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .padding(.top, 7)
                }
                .frame(width: 23, height: 34)
            case .candidate:
                VStack(spacing: 0) {
                    Circle().fill(GoFlyStyle.primary).frame(width: 8, height: 8)
                    Rectangle().fill(GoFlyStyle.primary).frame(width: 1.5, height: 26)
                }
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
