import SwiftUI

/// Dark instruction card at the top of execution mode (plan 4.8).
struct GoFlyExecutionHeader: View {
    let title: String
    var detail: String?
    var symbol: String?
    var onLeadingAction: (() -> Void)? = nil
    var onTrailingAction: (() -> Void)? = nil
    var trailingSymbol: String = "shuffle"
    var trailingAccessibilityLabel: String? = nil
    var trailingAccessibilityIdentifier: String = "execution.header.trailingAction"

    private var iconBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.32)
                : UIColor.white.withAlphaComponent(0.14)
        })
    }

    var body: some View {
        HStack(spacing: 12) {
            if let onLeadingAction {
                Button(action: onLeadingAction) {
                    Image(systemName: instructionSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.instructionForeground)
                        .frame(width: 44, height: 44)
                        .background(iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("joystick.randomDestination"))
                .accessibilityIdentifier("execution.header.action")
            } else {
                Image(systemName: instructionSymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.instructionForeground)
                    .frame(width: 44, height: 44)
                    .background(iconBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(GoFlyStyle.instructionForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.instructionForeground.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let onTrailingAction {
                Spacer(minLength: 8)
                Button(action: onTrailingAction) {
                    Image(systemName: trailingSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.instructionForeground)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(GoFlyStyle.instructionForeground.opacity(0.45), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(trailingAccessibilityLabel ?? goFlyString("joystick.randomDestination"))
                .accessibilityIdentifier(trailingAccessibilityIdentifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GoFlyStyle.instructionSurface,
                    in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("execution.header")
    }

    private var instructionSymbol: String {
        if let symbol { return symbol }
        // The wander status is exposed as a localized detail string. The route
        // header keeps the navigation arrow used by the execution design.
        if detail == goFlyString("joystick.phase.moving") { return GoFlySymbols.heading }
        if detail == goFlyString("joystick.phase.suspended") || detail == goFlyString("joystick.phase.interrupted") || detail == goFlyString("joystick.phase.paused") {
            return GoFlySymbols.pause
        }
        return GoFlySymbols.heading
    }
}

/// Fixed bottom control bar for execution mode: progress, optional leading
/// controls (round trip / heading), pause-resume and an explicit end action.
struct GoFlyExecutionControls<Leading: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(GoFlyProgressStyle())
                    .accessibilityIdentifier("execution.progress")
            }
            actionLayout {
                leading()
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button(action: onEnd) {
                    Label(goFlyString("execution.end"), systemImage: GoFlySymbols.close)
                        .lineLimit(1)
                }
                .buttonStyle(GoFlyActionStyle())
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityIdentifier("execution.end")
                if isPaused {
                    Button(action: onResume) {
                        Label(goFlyString("route.resume"), systemImage: GoFlySymbols.play)
                            .lineLimit(1)
                    }
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .disabled(!canResume)
                    .accessibilityIdentifier("execution.resume")
                } else {
                    Button(action: onPause) {
                        Label(goFlyString("route.pause"), systemImage: GoFlySymbols.pause)
                            .lineLimit(1)
                    }
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                    .disabled(!canPause)
                    .accessibilityIdentifier("execution.pause")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(GoFlyStyle.cardSurface)
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
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier(identifier)
    }
}
