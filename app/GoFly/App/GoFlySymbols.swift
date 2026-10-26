import GoFlyCore
import SwiftUI

/// SF Symbols by meaning, shared by controls and their help illustrations.
/// A location arrow is reserved for a position; a pin always represents a place.
enum GoFlySymbols {
    static let recenter = "scope"
    static let fitRoute = "arrow.up.left.and.arrow.down.right"
    static let location = "location"
    static let place = "mappin"
    static let sample = "circle.fill"
    static let coordinates = "scope"
    static let map = "map"
    static let favorite = "star"
    static let favoriteSelected = "star.fill"
    static let search = "magnifyingglass"
    static let paste = "doc.on.clipboard"
    static let clearSearch = "xmark.circle.fill"
    static let settings = "gearshape"
    static let adjustments = "slider.horizontal.3"
    static let close = "xmark"
    static let back = "chevron.left"
    static let disclosure = "chevron.forward"
    static let expand = "chevron.down"
    static let selected = "checkmark"
    static let checked = "checkmark.square.fill"
    static let unchecked = "square"
    static let play = "play.fill"
    static let pause = "pause.fill"
    static let add = "plus"
    static let delete = "trash"
    static let reorder = "line.3.horizontal"
    static let importFile = "square.and.arrow.down"
    static let exportFile = "square.and.arrow.up"
    static let externalLink = "arrow.up.right.square"
    static let retry = "arrow.clockwise"
    static let reset = "arrow.counterclockwise"
    static let warning = "exclamationmark.triangle"
    static let success = "checkmark.circle"
    static let information = "info.circle"
    static let help = "questionmark.circle"
    static let network = "shield"
    static let device = "iphone"
    static let language = "globe"
    static let appearance = "moon"
    static let background = "macwindow"
    static let service = "antenna.radiowaves.left.and.right"
    static let storage = "externaldrive"
    static let locked = "lock.shield"
    static let route = "point.topleft.down.to.point.bottomright.curvepath"
    static let routeList = "list.and.chevron"
    static let importEmpty = "doc.badge.plus"
    static let manualMovement = "hand.draw"
    static let walking = "figure.walk"
    static let heading = "location.north.fill"
    static let waiting = "clock"
    // 2026-10-20 redesign additions.
    static let folder = "folder"
    static let ellipsis = "ellipsis"
    static let selectItems = "checkmark.circle"
    static let undo = "arrow.uturn.backward"
    static let swap = "arrow.up.arrow.down"
    static let addStop = "plus.circle"
    static let recent = "clock.arrow.circlepath"
    static let expandSheet = "chevron.up"
    static let collapseSheet = "chevron.down"
    static let successFilled = "checkmark.circle.fill"
    static let dangerFilled = "exclamationmark.circle.fill"
    static let warningFilled = "exclamationmark.triangle.fill"
    static let flag = "flag"
    static let joystick = "arcade.stick"
}

/// Standalone glyphs grow gently with Dynamic Type without overflowing a 44 pt
/// control. Apply to the Image only so adjacent titles retain their own scaling.
private struct GoFlyControlSymbol: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    let maximum: CGFloat
    let weight: Font.Weight

    init(size: CGFloat, maximum: CGFloat, weight: Font.Weight) {
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.maximum = maximum
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: min(scaledSize, maximum), weight: weight))
            .symbolRenderingMode(.monochrome)
    }
}

extension View {
    func goFlyControlSymbol(size: CGFloat = 20, maximum: CGFloat = 24,
                            weight: Font.Weight = .medium) -> some View {
        modifier(GoFlyControlSymbol(size: size, maximum: maximum, weight: weight))
    }
}

// MARK: - Figma 04 Redesign Custom Vector Icons

/// Bottom bar tab icons matching Figma `04 · iOS Redesign` (`icon / pin`, `icon / route`, `icon / joystick`).
struct GoFlyTabIcon: View {
    let mode: SessionMapMode
    let selected: Bool
    var size: CGFloat = 25

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 25.0
            let stroke = StrokeStyle(lineWidth: (selected ? 2.29 : 1.875) * s, lineCap: .round, lineJoin: .round)
            switch mode {
            case .teleport:
                var outer = Path()
                outer.move(to: CGPoint(x: 20.833 * s, y: 10.417 * s))
                outer.addCurve(
                    to: CGPoint(x: 13.125 * s, y: 22.708 * s),
                    control1: CGPoint(x: 20.833 * s, y: 15.615 * s),
                    control2: CGPoint(x: 15.063 * s, y: 21.031 * s)
                )
                outer.addCurve(
                    to: CGPoint(x: 11.875 * s, y: 22.708 * s),
                    control1: CGPoint(x: 12.76 * s, y: 22.98 * s),
                    control2: CGPoint(x: 12.24 * s, y: 22.98 * s)
                )
                outer.addCurve(
                    to: CGPoint(x: 4.167 * s, y: 10.417 * s),
                    control1: CGPoint(x: 9.938 * s, y: 21.031 * s),
                    control2: CGPoint(x: 4.167 * s, y: 15.615 * s)
                )
                outer.addArc(
                    center: CGPoint(x: 12.5 * s, y: 10.417 * s),
                    radius: 8.333 * s,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: false
                )
                outer.closeSubpath()
                context.stroke(outer, with: .foreground, style: stroke)

                let inner = Path(ellipseIn: CGRect(x: 9.375 * s, y: 7.292 * s, width: 6.25 * s, height: 6.25 * s))
                context.stroke(inner, with: .foreground, style: stroke)

            case .route:
                let bottomCircle = Path(ellipseIn: CGRect(x: 3.125 * s, y: 16.667 * s, width: 6.25 * s, height: 6.25 * s))
                let topCircle = Path(ellipseIn: CGRect(x: 15.625 * s, y: 2.083 * s, width: 6.25 * s, height: 6.25 * s))
                var curve = Path()
                curve.move(to: CGPoint(x: 9.375 * s, y: 19.792 * s))
                curve.addLine(to: CGPoint(x: 18.229 * s, y: 19.792 * s))
                curve.addArc(
                    center: CGPoint(x: 18.229 * s, y: 16.146 * s),
                    radius: 3.646 * s,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: true
                )
                curve.addLine(to: CGPoint(x: 6.771 * s, y: 12.5 * s))
                curve.addArc(
                    center: CGPoint(x: 6.771 * s, y: 8.854 * s),
                    radius: 3.646 * s,
                    startAngle: .degrees(90),
                    endAngle: .degrees(-90),
                    clockwise: false
                )
                curve.addLine(to: CGPoint(x: 15.625 * s, y: 5.208 * s))
                context.stroke(bottomCircle, with: .foreground, style: stroke)
                context.stroke(curve, with: .foreground, style: stroke)
                context.stroke(topCircle, with: .foreground, style: stroke)

            case .joystick:
                let base = Path(roundedRect: CGRect(x: 3.125 * s, y: 15.625 * s, width: 18.75 * s, height: 6.25 * s),
                                cornerRadius: 2.083 * s)
                var leftTick = Path()
                leftTick.move(to: CGPoint(x: 6.25 * s, y: 15.625 * s))
                leftTick.addLine(to: CGPoint(x: 6.25 * s, y: 13.542 * s))
                var stem = Path()
                stem.move(to: CGPoint(x: 12.5 * s, y: 15.625 * s))
                stem.addLine(to: CGPoint(x: 12.5 * s, y: 9.375 * s))
                let knob = Path(ellipseIn: CGRect(x: 9.375 * s, y: 3.125 * s, width: 6.25 * s, height: 6.25 * s))
                context.stroke(base, with: .foreground, style: stroke)
                context.stroke(leftTick, with: .foreground, style: stroke)
                context.stroke(stem, with: .foreground, style: stroke)
                context.stroke(knob, with: .foreground, style: stroke)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Map recenter crosshair icon matching Figma `icon / locate` (`22×22`).
struct GoFlyRecenterIcon: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 22.0
            let stroke = StrokeStyle(lineWidth: 1.74 * s, lineCap: .round, lineJoin: .round)
            var ticks = Path()
            ticks.move(to: CGPoint(x: 1.833 * s, y: 11 * s))
            ticks.addLine(to: CGPoint(x: 4.583 * s, y: 11 * s))
            ticks.move(to: CGPoint(x: 17.417 * s, y: 11 * s))
            ticks.addLine(to: CGPoint(x: 20.167 * s, y: 11 * s))
            ticks.move(to: CGPoint(x: 11 * s, y: 1.833 * s))
            ticks.addLine(to: CGPoint(x: 11 * s, y: 4.583 * s))
            ticks.move(to: CGPoint(x: 11 * s, y: 17.417 * s))
            ticks.addLine(to: CGPoint(x: 11 * s, y: 20.167 * s))
            let outer = Path(ellipseIn: CGRect(x: 4.583 * s, y: 4.583 * s, width: 12.833 * s, height: 12.833 * s))
            let inner = Path(ellipseIn: CGRect(x: 8.708 * s, y: 8.708 * s, width: 4.583 * s, height: 4.583 * s))
            context.stroke(ticks, with: .foreground, style: stroke)
            context.stroke(outer, with: .foreground, style: stroke)
            context.fill(inner, with: .foreground)
            context.stroke(inner, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Speedometer gauge icon matching Figma `icon / speed` (`18×18`).
struct GoFlySpeedIcon: View {
    var size: CGFloat = 18

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 18.0
            let stroke = StrokeStyle(lineWidth: 1.425 * s, lineCap: .round, lineJoin: .round)
            var needle = Path()
            needle.move(to: CGPoint(x: 9 * s, y: 10.5 * s))
            needle.addLine(to: CGPoint(x: 12 * s, y: 7.5 * s))
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: 9 * s, y: 10.5 * s),
                radius: 7.5 * s,
                startAngle: .degrees(150),
                endAngle: .degrees(30),
                clockwise: false
            )
            context.stroke(needle, with: .foreground, style: stroke)
            context.stroke(arc, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Round trip repeat icon with optional diagonal slash when disabled, matching Figma `04 · iOS Redesign`.
struct GoFlyRoundTripIcon: View {
    var enabled: Bool = true
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Image(systemName: "repeat")
                .font(.system(size: size, weight: .semibold))
            if !enabled {
                Canvas { context, canvasSize in
                    let s = min(canvasSize.width, canvasSize.height)
                    var slash = Path()
                    slash.move(to: CGPoint(x: s * 0.15, y: s * 0.15))
                    slash.addLine(to: CGPoint(x: s * 0.85, y: s * 0.85))
                    context.stroke(
                        slash,
                        with: .foreground,
                        style: StrokeStyle(lineWidth: max(1.5, s * 0.11), lineCap: .round)
                    )
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// 5-point star icon matching Figma `icon / star`.
struct GoFlyStarIcon: View {
    var size: CGFloat = 18
    var filled: Bool = false
    var lineWidth: CGFloat? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 18.0
            let ox: CGFloat = 1.875 * s
            let oy: CGFloat = 1.875 * s
            let pts: [(CGFloat, CGFloat)] = [
                (7.125, 0),
                (9.33, 4.47),
                (14.25, 5.1825),
                (10.6875, 8.655),
                (11.5275, 13.56),
                (7.125, 11.25),
                (2.7225, 13.56),
                (3.5625, 8.655),
                (0, 5.1825),
                (4.92, 4.47)
            ]
            var path = Path()
            for (i, pt) in pts.enumerated() {
                let p = CGPoint(x: ox + pt.0 * s, y: oy + pt.1 * s)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            let stroke = StrokeStyle(lineWidth: lineWidth ?? (1.425 * s), lineCap: .round, lineJoin: .round)
            if filled {
                context.fill(path, with: .foreground)
            }
            context.stroke(path, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Clean outline trash icon matching Figma `icon / trash` (no inner vertical stripes).
struct GoFlyTrashIcon: View {
    var size: CGFloat = 17
    var lineWidth: CGFloat? = nil

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 17.0
            let stroke = StrokeStyle(lineWidth: lineWidth ?? (1.35 * s), lineCap: .round, lineJoin: .round)
            var lid = Path()
            lid.move(to: CGPoint(x: 2.125 * s, y: 4.25 * s))
            lid.addLine(to: CGPoint(x: 14.875 * s, y: 4.25 * s))

            var handle = Path()
            handle.move(to: CGPoint(x: 5.667 * s, y: 4.25 * s))
            handle.addLine(to: CGPoint(x: 5.667 * s, y: 2.833 * s))
            handle.addQuadCurve(to: CGPoint(x: 7.083 * s, y: 1.417 * s),
                                control: CGPoint(x: 5.667 * s, y: 1.417 * s))
            handle.addLine(to: CGPoint(x: 9.917 * s, y: 1.417 * s))
            handle.addQuadCurve(to: CGPoint(x: 11.333 * s, y: 2.833 * s),
                                control: CGPoint(x: 11.333 * s, y: 1.417 * s))
            handle.addLine(to: CGPoint(x: 11.333 * s, y: 4.25 * s))

            var bodyPath = Path()
            bodyPath.move(to: CGPoint(x: 13.458 * s, y: 4.25 * s))
            bodyPath.addLine(to: CGPoint(x: 13.458 * s, y: 14.167 * s))
            bodyPath.addQuadCurve(to: CGPoint(x: 12.042 * s, y: 15.583 * s),
                                  control: CGPoint(x: 13.458 * s, y: 15.583 * s))
            bodyPath.addLine(to: CGPoint(x: 4.958 * s, y: 15.583 * s))
            bodyPath.addQuadCurve(to: CGPoint(x: 3.542 * s, y: 14.167 * s),
                                  control: CGPoint(x: 3.542 * s, y: 15.583 * s))
            bodyPath.addLine(to: CGPoint(x: 3.542 * s, y: 4.25 * s))

            context.stroke(lid, with: .foreground, style: stroke)
            context.stroke(handle, with: .foreground, style: stroke)
            context.stroke(bodyPath, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Folder with inner route zig-zag matching Figma `icon / route folder` (`22×22`).
struct GoFlyRouteFolderIcon: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) / 22.0
            let stroke = StrokeStyle(lineWidth: 1.74 * s, lineCap: .round, lineJoin: .round)
            var folder = Path()
            folder.move(to: CGPoint(x: 2.5 * s, y: 6.0 * s))
            folder.addQuadCurve(to: CGPoint(x: 4.0 * s, y: 4.5 * s), control: CGPoint(x: 2.5 * s, y: 4.5 * s))
            folder.addLine(to: CGPoint(x: 8.2 * s, y: 4.5 * s))
            folder.addLine(to: CGPoint(x: 10.0 * s, y: 6.5 * s))
            folder.addLine(to: CGPoint(x: 18.0 * s, y: 6.5 * s))
            folder.addQuadCurve(to: CGPoint(x: 19.5 * s, y: 8.0 * s), control: CGPoint(x: 19.5 * s, y: 6.5 * s))
            folder.addLine(to: CGPoint(x: 19.5 * s, y: 16.5 * s))
            folder.addQuadCurve(to: CGPoint(x: 18.0 * s, y: 18.0 * s), control: CGPoint(x: 19.5 * s, y: 18.0 * s))
            folder.addLine(to: CGPoint(x: 4.0 * s, y: 18.0 * s))
            folder.addQuadCurve(to: CGPoint(x: 2.5 * s, y: 16.5 * s), control: CGPoint(x: 2.5 * s, y: 18.0 * s))
            folder.closeSubpath()

            var route = Path()
            route.move(to: CGPoint(x: 6.0 * s, y: 15.0 * s))
            route.addLine(to: CGPoint(x: 9.0 * s, y: 11.5 * s))
            route.addLine(to: CGPoint(x: 12.0 * s, y: 13.5 * s))
            route.addLine(to: CGPoint(x: 16.0 * s, y: 9.5 * s))

            context.stroke(folder, with: .foreground, style: stroke)
            context.stroke(route, with: .foreground, style: stroke)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Multi-select checkbox matching Figma `C3 · 多選模式 / 批次刪除` (`22×22`).
struct GoFlyCheckboxIcon: View {
    let selected: Bool
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            if selected {
                // Figma `checkbox / on` is 24 pt next to the 22 pt off ring (size is the off diameter).
                Circle()
                    .fill(GoFlyStyle.primary)
                    .frame(width: size + 2, height: size + 2)
                Canvas { context, canvasSize in
                    let s = min(canvasSize.width, canvasSize.height) / 22.0
                    var check = Path()
                    check.move(to: CGPoint(x: 7.0 * s, y: 11.2 * s))
                    check.addLine(to: CGPoint(x: 9.8 * s, y: 14.0 * s))
                    check.addLine(to: CGPoint(x: 15.0 * s, y: 8.4 * s))
                    context.stroke(check, with: .color(GoFlyStyle.surface),
                                   style: StrokeStyle(lineWidth: 2.0 * s, lineCap: .round, lineJoin: .round))
                }
                .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(GoFlyStyle.checkboxOffFill)
                    .overlay { Circle().strokeBorder(GoFlyStyle.checkboxOffBorder, lineWidth: 1.5) }
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

enum GoFlySettingsIconKind {
    case location, vpn, wifi, background, language, appearance, device
}

/// 32×32 rounded-square badge with 16×16 white outline icon matching Figma `F1 · 設定首頁`.
struct GoFlySettingsBadgeIcon: View {
    let kind: GoFlySettingsIconKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GoFlyStyle.primary)
                .frame(width: 32, height: 32)
            if kind == .wifi {
                Image(systemName: "wifi")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoFlyTextColor.inverse)
            } else {
                Canvas { context, canvasSize in
                let s = min(canvasSize.width, canvasSize.height) / 16.0
                let stroke = StrokeStyle(lineWidth: 1.47 * s, lineCap: .round, lineJoin: .round)
                let color = GraphicsContext.Shading.color(GoFlyStyle.surface)
                switch kind {
                case .wifi:
                    break
                case .location:
                    var p = Path()
                    p.move(to: CGPoint(x: 2.0 * s, y: 7.333 * s))
                    p.addLine(to: CGPoint(x: 14.667 * s, y: 1.333 * s))
                    p.addLine(to: CGPoint(x: 8.667 * s, y: 14.0 * s))
                    p.addLine(to: CGPoint(x: 7.333 * s, y: 8.667 * s))
                    p.closeSubpath()
                    context.stroke(p, with: color, style: stroke)
                case .vpn:
                    var p = Path()
                    p.move(to: CGPoint(x: 8.0 * s, y: 1.333 * s))
                    p.addCurve(to: CGPoint(x: 13.333 * s, y: 3.333 * s),
                               control1: CGPoint(x: 9.6 * s, y: 2.5 * s),
                               control2: CGPoint(x: 11.5 * s, y: 3.333 * s))
                    p.addLine(to: CGPoint(x: 13.333 * s, y: 8.667 * s))
                    p.addCurve(to: CGPoint(x: 8.0 * s, y: 14.667 * s),
                               control1: CGPoint(x: 13.333 * s, y: 12.0 * s),
                               control2: CGPoint(x: 10.8 * s, y: 13.7 * s))
                    p.addCurve(to: CGPoint(x: 2.667 * s, y: 8.667 * s),
                               control1: CGPoint(x: 5.2 * s, y: 13.7 * s),
                               control2: CGPoint(x: 2.667 * s, y: 12.0 * s))
                    p.addLine(to: CGPoint(x: 2.667 * s, y: 3.333 * s))
                    p.addCurve(to: CGPoint(x: 8.0 * s, y: 1.333 * s),
                               control1: CGPoint(x: 4.5 * s, y: 3.333 * s),
                               control2: CGPoint(x: 6.4 * s, y: 2.5 * s))
                    p.closeSubpath()
                    context.stroke(p, with: color, style: stroke)
                case .background:
                    let rect = Path(roundedRect: CGRect(x: 2.0 * s, y: 2.667 * s, width: 12.0 * s, height: 10.667 * s),
                                    cornerRadius: 1.333 * s)
                    var bar = Path()
                    bar.move(to: CGPoint(x: 2.0 * s, y: 6.0 * s))
                    bar.addLine(to: CGPoint(x: 14.0 * s, y: 6.0 * s))
                    context.stroke(rect, with: color, style: stroke)
                    context.stroke(bar, with: color, style: stroke)
                case .language:
                    let circle = Path(ellipseIn: CGRect(x: 1.333 * s, y: 1.333 * s, width: 13.333 * s, height: 13.333 * s))
                    var meridian = Path()
                    meridian.move(to: CGPoint(x: 8.0 * s, y: 1.333 * s))
                    meridian.addCurve(to: CGPoint(x: 8.0 * s, y: 14.667 * s),
                                      control1: CGPoint(x: 4.4 * s, y: 5.0 * s),
                                      control2: CGPoint(x: 4.4 * s, y: 11.0 * s))
                    meridian.addCurve(to: CGPoint(x: 8.0 * s, y: 1.333 * s),
                                      control1: CGPoint(x: 11.6 * s, y: 11.0 * s),
                                      control2: CGPoint(x: 11.6 * s, y: 5.0 * s))
                    var equator = Path()
                    equator.move(to: CGPoint(x: 1.333 * s, y: 8.0 * s))
                    equator.addLine(to: CGPoint(x: 14.667 * s, y: 8.0 * s))
                    context.stroke(circle, with: color, style: stroke)
                    context.stroke(meridian, with: color, style: stroke)
                    context.stroke(equator, with: color, style: stroke)
                case .appearance:
                    var moon = Path()
                    moon.move(to: CGPoint(x: 8.0 * s, y: 2.0 * s))
                    moon.addArc(center: CGPoint(x: 11.0 * s, y: 5.0 * s),
                                radius: 4.243 * s,
                                startAngle: .degrees(-135),
                                endAngle: .degrees(45),
                                clockwise: true)
                    moon.addArc(center: CGPoint(x: 8.0 * s, y: 8.0 * s),
                                radius: 6.0 * s,
                                startAngle: .degrees(0),
                                endAngle: .degrees(-90),
                                clockwise: false)
                    moon.closeSubpath()
                    context.stroke(moon, with: color, style: stroke)
                case .device:
                    let rect = Path(roundedRect: CGRect(x: 3.333 * s, y: 1.333 * s, width: 9.333 * s, height: 13.333 * s),
                                    cornerRadius: 1.333 * s)
                    let dot = Path(ellipseIn: CGRect(x: 7.25 * s, y: 11.25 * s, width: 1.5 * s, height: 1.5 * s))
                    context.stroke(rect, with: color, style: stroke)
                    context.fill(dot, with: color)
                }
            }
            .frame(width: 16, height: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

