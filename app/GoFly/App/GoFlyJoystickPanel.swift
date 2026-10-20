import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyJoystickPanel: View {
    @ObservedObject var controller: JoystickMovementController
    var cameraHeadingDegrees: Double
    var maximumHeight: CGFloat
    var onSetOrigin: () -> Void
    var onRandomDestination: () -> Void = { }
    var onSettings: () -> Void = { }
    @State private var contentHeight: CGFloat = 220
    @State private var confirmingEnd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = controller.error {
                    GoFlyStatusBanner(tone: .danger, title: goFlyString(error.localizationKey),
                        message: goFlyString("status.repairGuidance"),
                        actionTitle: goFlyString("operation.settings"), onAction: onSettings,
                        identifier: "joystick.error")
                } else if let error = controller.wanderError {
                    GoFlyStatusBanner(tone: .warning, title: goFlyString(error.localizationKey),
                        message: goFlyString("status.repairGuidance"),
                        actionTitle: controller.canRetryWander ? goFlyString("operation.retry") : nil,
                        onAction: controller.canRetryWander ? { _ = controller.retryWander() } : nil,
                        onDismiss: controller.clearWanderError, identifier: "joystick.wanderError")
                }
                wanderControls
                if controller.wanderEnabled {
                    Button(action: onRandomDestination) {
                        Label(goFlyString("joystick.randomDestination"), systemImage: GoFlySymbols.retry)
                    }
                    .buttonStyle(GoFlyActionStyle(small: true))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .disabled(!controller.canRandomizeWanderTarget)
                    .accessibilityIdentifier("joystick.randomDestination")
                }
                if controller.requiresStop {
                    Button(goFlyString("operation.settings"), action: onSettings)
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("joystick.settings")
                } else if needsOriginEntry {
                    Button(action: onSetOrigin) {
                        Label(goFlyString("joystick.setOrigin"), systemImage: GoFlySymbols.place)
                            .font(.body)
                            .padding(.horizontal, 16)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GoFlyStyle.primary)
                    .background(GoFlyStyle.secondarySurface, in: Capsule())
                    .accessibilityIdentifier("joystick.setOrigin")
                } else {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(goFlyString("route.speed"))
                            Spacer(minLength: 12)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(controller.speed.kilometersPerHour)")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                Text(goFlyString("route.speedUnit"))
                                    .font(.footnote)
                                    .foregroundStyle(GoFlyStyle.secondary)
                            }
                            .accessibilityIdentifier("joystick.speed.value")
                        }
                        .font(.body)
                        Slider(value: Binding(
                            get: { Double(controller.speed.kilometersPerHour) },
                            set: { if let speed = RouteSpeed(kilometersPerHour: Int($0)) { _ = controller.setSpeed(speed) } }
                        ), in: 2...100, step: 1) {
                            Text(goFlyString("route.speed"))
                        }
                        .tint(GoFlyStyle.primary)
                        .frame(minHeight: 44)
                        .disabled(!controller.canSetSpeed)
                        .accessibilityIdentifier("joystick.speed")
                    }
                    GoFlyManualJoystickPad(controller: controller, cameraHeadingDegrees: cameraHeadingDegrees)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(76, maximumHeight)))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if controller.wanderEnabled {
                GoFlyExecutionControls(progress: nil, isPaused: controller.phase == .paused || controller.phase == .suspended,
                    canPause: controller.canPause, canResume: controller.canResume,
                    onPause: { _ = controller.pause() }, onResume: { _ = controller.resume() },
                    onEnd: { confirmingEnd = true })
            }
        }
        .confirmationDialog(goFlyString("execution.end"), isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button(goFlyString("execution.end"), role: .destructive) { _ = controller.setWanderEnabled(false) }
            Button(goFlyString("common.cancel"), role: .cancel) { }
        }
        .background(GoFlyStyle.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joystick.panel")
    }

    // Dispatch temporarily invalidates location proof. Keep an existing task's pad mounted.
    private var needsOriginEntry: Bool {
        controller.requiresOrigin && controller.intent == nil
            && [.neutral, .suspended, .interrupted].contains(controller.phase)
    }

    private var wanderControls: some View {
        ViewThatFits(in: .horizontal) {
            wanderRow
            ScrollView(.horizontal) {
                wanderRow.fixedSize(horizontal: true, vertical: false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joystick.wanderControls")
    }

    private var wanderRow: some View {
        HStack(spacing: 12) {
            Image(systemName: GoFlySymbols.walking)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(GoFlyStyle.secondarySurface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goFlyString("joystick.wander"))
                    .font(.body.weight(.semibold))
                Text(goFlyString("joystick.wanderDetail"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { controller.wanderEnabled },
                set: { _ = controller.setWanderEnabled($0) }
            ))
            .labelsHidden()
            .tint(GoFlyStyle.success)
            .disabled(!controller.canSetWanderEnabled)
            .accessibilityLabel(goFlyString("joystick.wander"))
            .accessibilityValue(controller.wanderEnabled ? "1" : "0")
            .accessibilityIdentifier("joystick.wander")
        }
        .frame(minHeight: 44)
    }

}

private struct GoFlyManualJoystickPad: View {
    @ObservedObject var controller: JoystickMovementController
    let cameraHeadingDegrees: Double
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fingerID: UUID?
    @State private var attemptedBegin = false
    @State private var admitted = false
    @State private var endedWhileHeld = false
    @State private var screenVector = CGPoint.zero
    private let diameter: CGFloat = 150
    private let thumbDiameter: CGFloat = 44
    private var radius: CGFloat { (diameter - thumbDiameter) / 2 - 8 }

    var body: some View {
        ZStack {
            Circle().fill(GoFlyStyle.secondarySurface)
            Circle().strokeBorder(touching ? GoFlyStyle.primary : GoFlyStyle.subtleBorder, lineWidth: touching ? 2 : 1)
            Circle().strokeBorder(GoFlyStyle.subtleBorder, style: StrokeStyle(lineWidth: 0.5, dash: [2, 5]))
                .padding(20)
            ForEach(0..<24) { direction in
                Capsule()
                    .fill(GoFlyStyle.secondary.opacity(0.5))
                    .frame(width: direction % 6 == 0 ? 2 : 1, height: direction % 6 == 0 ? 8 : 4)
                    .offset(y: -diameter / 2 + 12)
                    .rotationEffect(.degrees(Double(direction) * 15))
            }
            Circle()
                .fill(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .overlay { Circle().strokeBorder(GoFlyStyle.surface, lineWidth: 1) }
                .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 5, y: 3)
                .offset(thumbOffset)
                .animation(reduceMotion || touching ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: thumbOffset)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { value in changed(at: value.location) }
            .onEnded { _ in finishTouch() })
        .onChange(of: touching) { _, touching in
            if !touching { finishTouch() }
            else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }
        .onChange(of: cameraHeadingDegrees) { _, _ in
            guard let fingerID, admitted, !endedWhileHeld, scenePhase == .active,
                  let input = input(for: screenVector), input.strength > 0 else { return }
            _ = controller.updateGesture(id: fingerID, input: input)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { endHeldInput() }
        }
        .onDisappear { finishTouch() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goFlyString("joystick.pad"))
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(goFlyString(controller.wanderEnabled ? "joystick.wanderPadHint" : "joystick.padHint"))
        .accessibilityDirectTouch()
        .accessibilityIdentifier("joystick.pad")
    }

    private var isEnabled: Bool { admitted && !endedWhileHeld || controller.canBeginGesture }

    private var thumbOffset: CGSize {
        guard let input = controller.displayInput, input.strength > 0, cameraHeadingDegrees.isFinite else { return .zero }
        let angle = (input.bearingDegrees - cameraHeadingDegrees) * .pi / 180
        let travel = CGFloat(input.strength) * radius
        return CGSize(width: CGFloat(sin(angle)) * travel, height: -CGFloat(cos(angle)) * travel)
    }

    private var accessibilityValue: String {
        guard let input = controller.displayInput, input.strength > 0 else { return goFlyString("joystick.centered") }
        return goFlyLocalizedFormat(goFlyString("joystick.inputValue"),
            input.bearingDegrees.formatted(.number.precision(.fractionLength(0)).locale(GoFlyPreferences.shared.locale)),
            input.strength.formatted(.percent.precision(.fractionLength(0)).locale(GoFlyPreferences.shared.locale)))
    }

    private func input(for vector: CGPoint) -> JoystickInput? {
        JoystickInput.fromScreenVector(x: Double(vector.x), y: Double(vector.y), radius: Double(radius),
                                      cameraHeadingDegrees: cameraHeadingDegrees)
    }

    private func changed(at location: CGPoint) {
        guard scenePhase == .active else { return }
        if fingerID == nil {
            fingerID = UUID()
            attemptedBegin = false
            admitted = false
            endedWhileHeld = false
        }
        guard let fingerID, !endedWhileHeld else { return }
        screenVector = CGPoint(x: location.x - diameter / 2, y: location.y - diameter / 2)
        guard let input = input(for: screenVector) else { return }
        if input.strength == 0 {
            if admitted { endHeldInput() }
            return
        }
        if !attemptedBegin {
            // A center touch keeps its one admission attempt until the first valid nonzero input.
            attemptedBegin = true
            admitted = controller.beginGesture(id: fingerID, input: input)
        } else if admitted {
            _ = controller.updateGesture(id: fingerID, input: input)
        }
    }

    private func endHeldInput() {
        if let fingerID, admitted, !endedWhileHeld { _ = controller.endGesture(id: fingerID) }
        endedWhileHeld = true
        screenVector = .zero
    }

    private func finishTouch() {
        endHeldInput()
        fingerID = nil
        attemptedBegin = false
        admitted = false
        endedWhileHeld = false
    }
}
