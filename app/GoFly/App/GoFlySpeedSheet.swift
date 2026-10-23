import GoFlyCore
import SwiftUI

struct GoFlySpeedSheet: View {
    let speed: RouteSpeed
    var canEdit: Bool = true
    var onSpeedChanged: (RouteSpeed) -> Void
    var onDismiss: () -> Void

    private let presets: [Int] = [5, 20, 60, 120]

    private func presetIcon(for preset: Int) -> String {
        switch preset {
        case 5: return "🚶"
        case 20: return "🚲"
        case 60: return "🚗"
        case 120: return "🏎️"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text(goFlyString("route.speedSetting"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                Spacer()
                Button(action: onDismiss) {
                    Text(goFlyString("common.done"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("route.speed.done")
            }

            Divider()

            // Current Speed Readout in a single row
            HStack(alignment: .firstTextBaseline) {
                Text(goFlyString("route.speedCurrent"))
                    .font(.body)
                    .foregroundStyle(GoFlyStyle.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(speed.kilometersPerHour)")
                        .font(.system(size: 36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(GoFlyStyle.primary)
                    Text(goFlyString("route.speedUnit"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GoFlyStyle.secondary)
                }
                .accessibilityIdentifier("route.speed.value")
            }
            .padding(.vertical, 2)

            // Preset Chips with icons
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { preset in
                    let isSelected = speed.kilometersPerHour == preset
                    Button {
                        if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: preset) {
                            onSpeedChanged(newSpeed)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(presetIcon(for: preset))
                            Text("\(preset)")
                        }
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(isSelected ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
                        .overlay {
                            if !isSelected {
                                Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 1)
                            }
                        }
                        .foregroundStyle(isSelected ? GoFlyStyle.surface : GoFlyStyle.primary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityIdentifier("route.speed.preset.\(preset)")
                }
            }

            // Slider with min/max labels below
            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { Double(speed.kilometersPerHour) },
                        set: { value in
                            if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: Int(value.rounded())) {
                                onSpeedChanged(newSpeed)
                            }
                        }
                    ),
                    in: 1...120
                )
                .tint(GoFlyStyle.primary)
                .disabled(!canEdit)
                .accessibilityIdentifier("route.speed")

                HStack {
                    Text("1 \(goFlyString("route.speedUnit"))")
                        .font(.caption)
                        .foregroundStyle(GoFlyStyle.secondary)
                    Spacer()
                    Text("120 \(goFlyString("route.speedUnit"))")
                        .font(.caption)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
            }
            .padding(.top, 4)

            Spacer(minLength: 0)

            // Bottom Confirm Button
            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("route.speed.confirm")
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(GoFlyStyle.cardSurface)
        .presentationDetents([.height(412)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.cardSurface)
    }
}
