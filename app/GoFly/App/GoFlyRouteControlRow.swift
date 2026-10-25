import SwiftUI

/// Vertical double arrow icon for direction toggle.
///
/// Design specification:
/// - Forward: left arrow down lighter, right arrow up solid dark.
/// - Reverse: right arrow up lighter, left arrow down solid dark.
/// - Locked/disabled when round trip is off.
struct GoFlyVerticalArrowsIcon: View {
    let isReversed: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(!isEnabled ? GoFlyTextColor.disabled.opacity(0.4) : (isReversed ? GoFlyTextColor.primary : GoFlyTextColor.secondary.opacity(0.4)))
            Image(systemName: "arrow.up")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(!isEnabled ? GoFlyTextColor.disabled.opacity(0.4) : (isReversed ? GoFlyTextColor.secondary.opacity(0.4) : GoFlyTextColor.primary))
        }
        .accessibilityHidden(true)
    }
}

/// Compact speed chip button without "km/h" unit (width 68 pt).
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
            .frame(width: 68, height: height)
            .background(GoFlyStyle.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
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
            // Repeat button: repeat / repeat.slash
            Button(action: onToggleRoundTrip) {
                Image(systemName: isRoundTrip ? "repeat" : "repeat.slash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isRoundTrip ? GoFlyTextColor.primary : GoFlyTextColor.disabled)
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.surface, in: Circle())
                    .overlay { Circle().strokeBorder(Color(white: 0.78), lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canToggleRoundTrip)
            .accessibilityLabel(goFlyString(isRoundTrip ? "route.roundTrip.on" : "route.roundTrip.off"))
            .accessibilityIdentifier("route.control.repeat")

            // Direction button: vertical double arrows (active only when round trip enabled)
            Button(action: onToggleDirection) {
                GoFlyVerticalArrowsIcon(isReversed: isRoundTrip && isReversed, isEnabled: isRoundTrip && canToggleDirection)
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.surface, in: Circle())
                    .overlay { Circle().strokeBorder(Color(white: 0.78), lineWidth: 0.5) }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isRoundTrip || !canToggleDirection)
            .accessibilityLabel(goFlyString((isRoundTrip && isReversed) ? "route.direction.reverse" : "route.direction.forward"))
            .accessibilityIdentifier("route.control.direction")

            Spacer(minLength: 0)

            // Speed chip: pure number, 68 pt width
            GoFlySpeedChip(speed: speed, action: onSpeedTap, isEnabled: canChangeSpeed, height: 36, showsChevron: true)
        }
    }
}
