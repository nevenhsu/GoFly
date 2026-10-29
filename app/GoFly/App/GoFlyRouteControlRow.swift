import SwiftUI

/// Round trip icon (Figma `icon / repeat`, 20 pt grid): two opposing arrows,
/// with a diagonal slash (`icon / repeat.slash`) when round trip is off.
struct GoFlyRouteRepeatIcon: View {
    let isOn: Bool
    var isEnabled = true

    var body: some View {
        Canvas { context, _ in
            let color = isEnabled
                ? (isOn ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                : GoFlyTextColor.disabled
            let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            var path = Path()
            path.move(to: CGPoint(x: 7.2, y: 5)); path.addLine(to: CGPoint(x: 17.5, y: 5))
            path.move(to: CGPoint(x: 14.17, y: 1.67)); path.addLine(to: CGPoint(x: 17.5, y: 5))
            path.addLine(to: CGPoint(x: 14.17, y: 8.33))
            path.move(to: CGPoint(x: 12.8, y: 15)); path.addLine(to: CGPoint(x: 2.5, y: 15))
            path.move(to: CGPoint(x: 5.83, y: 11.67)); path.addLine(to: CGPoint(x: 2.5, y: 15))
            path.addLine(to: CGPoint(x: 5.83, y: 18.33))
            context.stroke(path, with: .color(color), style: stroke)
            if !isOn {
                var slash = Path()
                slash.move(to: CGPoint(x: 2.5, y: 2.5)); slash.addLine(to: CGPoint(x: 17.5, y: 17.5))
                context.stroke(slash, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// Direction icon (Figma `icon / direction.forward|reverse`, 20 pt grid): a
/// down arrow on the left and an up arrow on the right; the active direction is dark.
/// Forward: up arrow dark. Reverse: down arrow dark.
struct GoFlyVerticalArrowsIcon: View {
    let isReversed: Bool
    var isEnabled = true

    var body: some View {
        Canvas { context, _ in
            let dark = isEnabled ? GoFlyTextColor.primary : GoFlyTextColor.disabled
            let light = isEnabled ? GoFlyStyle.directionInactive
                : GoFlyTextColor.disabled
            let stroke = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            var down = Path()
            down.move(to: CGPoint(x: 5, y: 3)); down.addLine(to: CGPoint(x: 5, y: 17))
            down.move(to: CGPoint(x: 2, y: 14)); down.addLine(to: CGPoint(x: 5, y: 17))
            down.addLine(to: CGPoint(x: 8, y: 14))
            var up = Path()
            up.move(to: CGPoint(x: 15, y: 17)); up.addLine(to: CGPoint(x: 15, y: 3))
            up.move(to: CGPoint(x: 12, y: 6)); up.addLine(to: CGPoint(x: 15, y: 3))
            up.addLine(to: CGPoint(x: 18, y: 6))
            context.stroke(down, with: .color(isReversed ? dark : light), style: stroke)
            context.stroke(up, with: .color(isReversed ? light : dark), style: stroke)
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

/// Compact speed chip button without "km/h" unit (min width 68 pt).
struct GoFlySpeedChip: View {
    let speed: Int
    var action: () -> Void
    var isEnabled: Bool = true
    var identifier: String = "route.speedChip"
    /// Figma D6 uses a 36 pt chip with a trailing chevron; the joystick row keeps the compact 34 pt chip.
    var height: CGFloat = 34
    var showsChevron = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                GoFlySpeedIcon(size: 16)
                Text("\(speed)")
                    .font(GoFlyFont.footnoteEmphasis)
                    .monospacedDigit()
                    .lineLimit(1)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .frame(minWidth: 68, minHeight: height, maxHeight: height)
            .background(GoFlyStyle.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
            .goFlyShadow(.chip)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(goFlyLocalizedFormat(goFlyString("route.speedShort"), speed))
        .accessibilityIdentifier(identifier)
    }
}

/// Wireframe pure-icon control row for route execution mode (D3, D4).
struct GoFlyRouteControlRow: View {
    let isRoundTrip: Bool
    let isReversed: Bool
    let speed: Int
    var canToggleRoundTrip: Bool = true
    var canToggleDirection: Bool = true
    var canChangeSpeed: Bool = true
    var onToggleRoundTrip: () -> Void
    var onToggleDirection: () -> Void
    var onSpeedTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Round trip: Figma D6 ⇄, primary when on, secondary when off.
            Button(action: onToggleRoundTrip) {
                GoFlyRouteRepeatIcon(isOn: isRoundTrip, isEnabled: canToggleRoundTrip)
                    .frame(width: 36, height: 36)
                    .background(canToggleRoundTrip ? GoFlyStyle.routeControlSurface : GoFlyStyle.disabledSurface,
                                in: Circle())
                    .overlay {
                        if canToggleRoundTrip {
                            Circle().strokeBorder(GoFlyStyle.routeControlBorder, lineWidth: 0.5)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleRoundTrip)
            .accessibilityLabel(goFlyString(isRoundTrip ? "route.roundTrip.on" : "route.roundTrip.off"))
            .accessibilityIdentifier("route.control.repeat")

            // Direction button: only while round trip is on; single trip is always forward.
            if isRoundTrip {
                Button(action: onToggleDirection) {
                    GoFlyVerticalArrowsIcon(isReversed: isReversed, isEnabled: canToggleDirection)
                        .frame(width: 36, height: 36)
                        .background(canToggleDirection ? GoFlyStyle.routeControlSurface : GoFlyStyle.disabledSurface,
                                    in: Circle())
                        .overlay {
                            if canToggleDirection {
                                Circle().strokeBorder(GoFlyStyle.routeControlBorder, lineWidth: 0.5)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canToggleDirection)
                .accessibilityLabel(goFlyString(isReversed ? "route.direction.reverse" : "route.direction.forward"))
                .accessibilityIdentifier("route.control.direction")
            }

            Spacer(minLength: 0)

            // Speed chip: pure number, 68 pt width
            GoFlySpeedChip(speed: speed, action: onSpeedTap, isEnabled: canChangeSpeed, height: 36, showsChevron: true)
        }
    }
}
