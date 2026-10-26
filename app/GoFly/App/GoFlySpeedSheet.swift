import GoFlyCore
import SwiftUI

struct GoFlySpeedSheet: View {
    let speed: RouteSpeed
    var canEdit: Bool = true
    var onSpeedChanged: (RouteSpeed) -> Void
    var onDismiss: () -> Void

    private let presets: [Int] = RouteSpeed.presets.map(\.kilometersPerHour)

    /// Flat colorful vector icons on a transparent background (orange, navy, mustard); they carry their own colors, so no light/dark variants are needed.
    private func presetIcon(for preset: Int) -> String? {
        switch preset {
        case 5: return "SpeedPresetWalk"
        case 25: return "SpeedPresetBicycle"
        case 50: return "SpeedPresetScooter"
        case 100: return "SpeedPresetCar"
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Same sheet frame as the favorite place editor: header 12 pt from the top, 20 pt sides.
            GoFlySheetHeader(title: goFlyString("route.speedSetting")) {
                EmptyView()
            } trailing: {
                Button(action: onDismiss) {
                    Text(goFlyString("common.done"))
                        .font(GoFlyFont.bodyEmphasis)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("route.speed.done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            VStack(spacing: 16) {
            // Current Speed Readout in a single row
            HStack(alignment: .firstTextBaseline) {
                Text(goFlyString("route.speedCurrent"))
                    .font(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.secondary)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(speed.kilometersPerHour)")
                        .font(GoFlyFont.metric)
                        .monospacedDigit()
                        .foregroundStyle(GoFlyTextColor.primary)
                    Text(goFlyString("route.speedUnit"))
                        .font(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
                .accessibilityIdentifier("route.speed.value")
            }
            .padding(.vertical, 4)

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
                            if let icon = presetIcon(for: preset) {
                                Image(icon)
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                            }
                            Text("\(preset)")
                        }
                        .font(GoFlyFont.footnoteEmphasis)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSelected ? GoFlyStyle.primary : GoFlyStyle.surface, in: Capsule())
                        .overlay {
                            if !isSelected {
                                Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 1)
                            }
                        }
                        .foregroundStyle(isSelected ? GoFlyStyle.surface : GoFlyTextColor.primary)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityIdentifier("route.speed.preset.\(preset)")
                }
            }

            // Slider with min/max labels below
            VStack(spacing: 4) {
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
                        .font(GoFlyFont.caption)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    Spacer()
                    Text("120 \(goFlyString("route.speedUnit"))")
                        .font(GoFlyFont.caption)
                        .foregroundStyle(GoFlyTextColor.secondary)
                }
            }
            .padding(.top, 4)

            }
            .padding(20)

            Spacer(minLength: 0)

            // Bottom Confirm Button
            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("route.speed.confirm")
            .padding(.top, 40)
            .padding(.horizontal, 20)
            .padding(.bottom, -1) // the Home indicator sits 20 pt below the button
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(373)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
    }
}
