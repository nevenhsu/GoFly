import SwiftUI

/// Dark instruction card at the top of execution mode (plan 4.8).
struct GoFlyExecutionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(GoFlyStyle.instructionForeground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.instructionForeground.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GoFlyStyle.instructionSurface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("execution.header")
    }
}

/// Fixed bottom control bar for execution mode: progress, optional leading
/// controls (round trip / heading), pause-resume and an explicit end action.
struct GoFlyExecutionControls<Leading: View>: View {
    let progress: Double?
    let isPaused: Bool
    let canPause: Bool
    let canResume: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onEnd: () -> Void
    @ViewBuilder let leading: () -> Leading

    init(progress: Double?, isPaused: Bool, canPause: Bool, canResume: Bool,
         onPause: @escaping () -> Void, onResume: @escaping () -> Void, onEnd: @escaping () -> Void,
         @ViewBuilder leading: @escaping () -> Leading) {
        self.progress = progress
        self.isPaused = isPaused
        self.canPause = canPause
        self.canResume = canResume
        self.onPause = onPause
        self.onResume = onResume
        self.onEnd = onEnd
        self.leading = leading
    }

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(GoFlyStyle.primary)
                    .accessibilityIdentifier("execution.progress")
            }
            HStack(spacing: 12) {
                leading()
                Spacer(minLength: 0)
                if isPaused {
                    Button(action: onResume) {
                        Label(goFlyString("route.resume"), systemImage: GoFlySymbols.play)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(GoFlyIconStyle())
                    .disabled(!canResume)
                    .accessibilityLabel(goFlyString("route.resume"))
                    .accessibilityIdentifier("execution.resume")
                } else {
                    Button(action: onPause) {
                        Label(goFlyString("route.pause"), systemImage: GoFlySymbols.pause)
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(GoFlyIconStyle())
                    .disabled(!canPause)
                    .accessibilityLabel(goFlyString("route.pause"))
                    .accessibilityIdentifier("execution.pause")
                }
                Button(action: onEnd) {
                    Image(systemName: GoFlySymbols.close)
                }
                .buttonStyle(GoFlyIconStyle())
                .accessibilityLabel(goFlyString("execution.end"))
                .accessibilityIdentifier("execution.end")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(GoFlyStyle.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(GoFlyStyle.border).frame(height: 0.5).allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("execution.controls")
    }
}

extension GoFlyExecutionControls where Leading == EmptyView {
    init(progress: Double?, isPaused: Bool, canPause: Bool, canResume: Bool,
         onPause: @escaping () -> Void, onResume: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.init(progress: progress, isPaused: isPaused, canPause: canPause, canResume: canResume,
                  onPause: onPause, onResume: onResume, onEnd: onEnd, leading: { EmptyView() })
    }
}

/// Secondary control used inside the execution bar, for direction or round trip.
struct GoFlyExecutionToggle: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    var identifier: String = "execution.toggle"

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(isOn ? GoFlyStyle.primary : GoFlyStyle.secondary)
                .background(isOn ? GoFlyStyle.secondarySurface : .clear, in: Capsule())
                .overlay { Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
