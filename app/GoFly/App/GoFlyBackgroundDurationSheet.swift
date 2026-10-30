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

    private var prevHour: Int {
        hours > 0 ? hours - 1 : 24
    }

    private var nextHour: Int {
        hours < 24 ? hours + 1 : 0
    }

    private var prevMinute: Int {
        minutes > 0 ? minutes - 1 : 59
    }

    private var nextMinute: Int {
        minutes < 59 ? minutes + 1 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            GoFlySheetHeader(title: goFlyString("settings.background.duration")) {
                GoFlyNavActionButton(title: goFlyString("common.cancel"), identifier: "settings.background.duration.cancel") {
                    cancel()
                }
            } trailing: {
                GoFlyNavActionButton(title: goFlyString("common.done"), isProminent: true, identifier: "settings.background.duration.done") {
                    onDismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            timePickerWheel
                .padding(.top, 16)
                .padding(.horizontal, 16)

            Button(action: onDismiss) {
                Text(goFlyString("common.doneSetting"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .frame(height: 56)
            .accessibilityIdentifier("settings.background.duration.confirm")
            .padding(.top, 24)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: hours) { _, _ in commit() }
        .onChange(of: minutes) { _, _ in commit() }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .presentationBackgroundInteraction(.enabled)
    }

    /// Figma `TimePicker / Wheel` (`238:9472`): 361 × 128 pt card with 3 rows of numbers and center selection band.
    private var timePickerWheel: some View {
        ZStack {
            // Selection band
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .systemFill).opacity(0.5))
                .frame(height: 40)
                .padding(.horizontal, 8)

            HStack(spacing: 0) {
                // Hour column
                hourColumn
                    .frame(maxWidth: .infinity)

                // Colon separator
                Text(":")
                    .goFlyFont(GoFlyFont.title)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(width: 20)
                    .accessibilityHidden(true)

                // Minute column
                minuteColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 128)
        .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
        )
    }

    private var hourColumn: some View {
        VStack(spacing: 8) {
            Button {
                stepHour(-1)
            } label: {
                Text("\(prevHour)")
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("\(hours)")
                    .goFlyFont(GoFlyFont.title)
                    .foregroundStyle(GoFlyTextColor.primary)
                Text(goFlyString("settings.background.duration.wheelUnit.hours"))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.primary)
            }
            .frame(height: 36)

            Button {
                stepHour(1)
            } label: {
                Text("\(nextHour)")
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -15 {
                        stepHour(1)
                    } else if value.translation.height > 15 {
                        stepHour(-1)
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(goFlyString("settings.background.duration.hours"))
        .accessibilityValue("\(hours) \(goFlyString("settings.background.duration.wheelUnit.hours"))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stepHour(1)
            case .decrement: stepHour(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("settings.background.duration.hours")
    }

    private var minuteColumn: some View {
        VStack(spacing: 8) {
            Button {
                stepMinute(-1)
            } label: {
                Text(String(format: "%02d", prevMinute))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text(String(format: "%02d", minutes))
                    .goFlyFont(GoFlyFont.title)
                    .foregroundStyle(GoFlyTextColor.primary)
                Text(goFlyString("settings.background.duration.wheelUnit.minutes"))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.primary)
            }
            .frame(height: 36)

            Button {
                stepMinute(1)
            } label: {
                Text(String(format: "%02d", nextMinute))
                    .goFlyFont(GoFlyFont.subheadline)
                    .foregroundStyle(GoFlyTextColor.disabled)
                    .frame(height: 22)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -15 {
                        stepMinute(1)
                    } else if value.translation.height > 15 {
                        stepMinute(-1)
                    }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(goFlyString("settings.background.duration.minutes"))
        .accessibilityValue("\(minutes) \(goFlyString("settings.background.duration.wheelUnit.minutes"))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stepMinute(1)
            case .decrement: stepMinute(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("settings.background.duration.minutes")
    }

    private func stepHour(_ delta: Int) {
        let newHours = (hours + delta + 25) % 25
        hours = newHours
    }

    private func stepMinute(_ delta: Int) {
        let newMinutes = (minutes + delta + 60) % 60
        minutes = newMinutes
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
