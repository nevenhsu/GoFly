import GoFlyCore
import SwiftUI

struct GoFlySpeedSheet: View {
    let speed: RouteSpeed
    var canEdit: Bool = true
    var onSpeedChanged: (RouteSpeed) -> Void
    var onDismiss: () -> Void

    private let presets: [Int] = [5, 20, 60, 120]

    var body: some View {
        VStack(spacing: 20) {
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

            // Current Speed Readout
            VStack(spacing: 4) {
                Text(goFlyString("route.speedCurrent"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(speed.kilometersPerHour)")
                        .font(.system(size: 36, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(GoFlyStyle.primary)
                    Text(goFlyString("route.speedUnit"))
                        .font(.headline.weight(.medium))
                        .foregroundStyle(GoFlyStyle.secondary)
                }
                .accessibilityIdentifier("route.speed.value")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Preset Chips
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    let isSelected = speed.kilometersPerHour == preset
                    Button {
                        if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: preset) {
                            onSpeedChanged(newSpeed)
                        }
                    } label: {
                        Text("\(preset) \(goFlyString("route.speedUnit"))")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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

            // Slider
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { Double(speed.kilometersPerHour) },
                        set: { value in
                            if canEdit, let newSpeed = RouteSpeed(kilometersPerHour: Int(value.rounded())) {
                                onSpeedChanged(newSpeed)
                            }
                        }
                    ),
                    in: 1...120,
                    step: 1
                ) {
                    Text(goFlyString("route.speedSetting"))
                } minimumValueLabel: {
                    Text("1")
                        .font(.caption)
                        .foregroundStyle(GoFlyStyle.secondary)
                } maximumValueLabel: {
                    Text("120")
                        .font(.caption)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
                .tint(GoFlyStyle.primary)
                .disabled(!canEdit)
                .accessibilityIdentifier("route.speed")
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
