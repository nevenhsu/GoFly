import GoFlyCore
import SwiftUI

enum GoFlyBackgroundDuration {
    /// Short form for the F6 row value (Figma "12 hr").
    @MainActor static func summary(seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60
        let h = goFlyString("settings.background.duration.hr")
        let m = goFlyString("settings.background.duration.min")
        switch (hours, minutes) {
        case (0, _): return "\(minutes) \(m)"
        case (_, 0): return "\(hours) \(h)"
        default: return "\(hours) \(h) \(minutes) \(m)"
        }
    }
}

/// Time input for how long a movement keeps running after the app moves to
/// the background (Figma F6.a, 336 pt sheet): header, 130 pt wheel 16 pt
/// below it, 40 pt above the button.
struct GoFlyBackgroundDurationSheet: View {
    let seconds: Int
    var onChange: (Int) -> Void
    var onDismiss: () -> Void

    @State private var hours: Int
    @State private var minutes: Int
    private let original: Int

    init(seconds: Int, onChange: @escaping (Int) -> Void, onDismiss: @escaping () -> Void) {
        self.seconds = seconds
        self.original = seconds
        self.onChange = onChange
        self.onDismiss = onDismiss
        _hours = State(initialValue: seconds / 3600)
        _minutes = State(initialValue: seconds % 3600 / 60)
    }

    private var total: Int { hours * 3600 + minutes * 60 }

    var body: some View {
        VStack(spacing: 0) {
            GoFlySheetHeader(title: nil) {
                Button(action: cancel) {
                    Text(goFlyString("common.cancel"))
                        .font(GoFlyFont.body)
                        .foregroundStyle(GoFlyTextColor.primary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.background.duration.cancel")
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
                .accessibilityIdentifier("settings.background.duration.done")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            wheels
                .padding(.top, 9)
                .padding(.horizontal, 20)

            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("settings.background.duration.confirm")
            .padding(.top, 40)
            .padding(.horizontal, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hours) { _, _ in commit() }
        .onChange(of: minutes) { _, _ in commit() }
        .presentationDetents([.height(336)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
    }

    /// Figma `TimePicker / Wheel`: hour and minute wheels split by a colon.
    private var wheels: some View {
        HStack(spacing: 0) {
            wheel(selection: $hours, range: Array(0...24),
                  unitKey: "settings.background.duration.hours", identifier: "hours", padded: false)
            Text(":")
                .font(GoFlyFont.title)
                .foregroundStyle(GoFlyTextColor.disabled)
                .accessibilityHidden(true)
            wheel(selection: $minutes, range: Array(0...59),
                  unitKey: "settings.background.duration.minutes", identifier: "minutes", padded: true)
        }
        .padding(.horizontal, 8)
        .frame(height: 130)
        .clipped()
        .background(GoFlyStyle.durationWheelSurface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius, style: .continuous)
            .strokeBorder(GoFlyStyle.durationWheelBorder, lineWidth: 0.5))
    }

    private func wheel(selection: Binding<Int>, range: [Int], unitKey: String,
                       identifier: String, padded: Bool) -> some View {
        Picker(goFlyString(unitKey), selection: selection) {
            ForEach(range, id: \.self) { value in
                Text("\(padded ? String(format: "%02d", value) : String(value)) \(goFlyString(unitKey))")
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("settings.background.duration.\(identifier)")
    }

    /// Keeps the total inside 1 minute…24 h 59 min.
    private func commit() {
        let clamped = Int(BackgroundRunDuration.clamp(TimeInterval(total)))
        if clamped != total {
            hours = clamped / 3600
            minutes = clamped % 3600 / 60
        }
        onChange(clamped)
    }

    private func cancel() {
        onChange(original)
        onDismiss()
    }
}
