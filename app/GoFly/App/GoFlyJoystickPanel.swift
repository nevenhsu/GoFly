import GoFlyCore
import SwiftUI

struct GoFlyJoystickPanel: View {
    @ObservedObject var controller: JoystickMovementController
    var cameraHeadingDegrees: Double
    var maximumHeight: CGFloat
    var onSetOrigin: () -> Void
    var onRandomDestination: () -> Void = { }
    var onSettings: () -> Void = { }
    @State private var contentHeight: CGFloat = 220

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = controller.error {
                    Label(goFlyString(error.localizationKey), systemImage: GoFlySymbols.warning)
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("joystick.error")
                }
                if let error = controller.wanderError {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Label(goFlyString(error.localizationKey), systemImage: GoFlySymbols.warning)
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("joystick.wanderError.message")
                            Button(action: controller.clearWanderError) {
                                Image(systemName: GoFlySymbols.close)
                                    .goFlyControlSymbol(size: 14, maximum: 18, weight: .semibold)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(goFlyString("common.dismiss"))
                            .accessibilityIdentifier("joystick.wanderError.dismiss")
                        }
                    }
                    .foregroundStyle(GoFlyStyle.errorForeground)
                    .padding(12)
                    .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
                }
                if controller.canRetryWander {
                    Button { _ = controller.retryWander() } label: {
                        Text(goFlyString("operation.retry"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(GoFlyActionStyle())
                    .accessibilityHint(goFlyString("joystick.wanderRetryHint"))
                    .accessibilityIdentifier("joystick.wanderRetry")
                }
                wanderControls
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
                            Text(goFlyLocalizedFormat(goFlyString("route.speedValue"),
                                                                 controller.speed.kilometersPerHour))
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
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
        .goFlyCard(floating: true)
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
            Toggle(isOn: Binding(
                get: { controller.wanderEnabled },
                set: { _ = controller.setWanderEnabled($0) }
            )) {
                Label(goFlyString("joystick.wander"),
                      systemImage: controller.wanderEnabled ? GoFlySymbols.checked : GoFlySymbols.unchecked)
                    .font(.body)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(controller.canSetWanderEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .disabled(!controller.canSetWanderEnabled)
            .accessibilityValue(controller.wanderEnabled ? "1" : "0")
            .accessibilityIdentifier("joystick.wander")
            if controller.wanderEnabled {
                Spacer(minLength: 0)
                Button(action: onRandomDestination) {
                    Text(goFlyString("joystick.randomDestination"))
                        .font(.body)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 126, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.canRandomizeWanderTarget ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                .disabled(!controller.canRandomizeWanderTarget)
                .accessibilityIdentifier("joystick.randomDestination")
            }
        }
        .frame(minHeight: 44)
    }
}

private struct GoFlyManualJoystickPad: View {
    @ObservedObject var controller: JoystickMovementController
    let cameraHeadingDegrees: Double
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var touching = false
    @State private var fingerID: UUID?
    @State private var attemptedBegin = false
    @State private var admitted = false
    @State private var endedWhileHeld = false
    @State private var screenVector = CGPoint.zero
    private let diameter: CGFloat = 132
    private let thumbDiameter: CGFloat = 44
    private var radius: CGFloat { (diameter - thumbDiameter) / 2 - 8 }

    var body: some View {
        ZStack {
            Circle().fill(GoFlyStyle.secondarySurface)
            Circle().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 1)
            Circle().strokeBorder(GoFlyStyle.subtleBorder, style: StrokeStyle(lineWidth: 0.5, dash: [2, 5]))
                .padding(20)
            ForEach(0..<4) { direction in
                Capsule()
                    .fill(GoFlyStyle.secondary.opacity(0.5))
                    .frame(width: 2, height: 8)
                    .offset(y: -diameter / 2 + 12)
                    .rotationEffect(.degrees(Double(direction) * 90))
            }
            Circle()
                .fill(isEnabled ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .overlay { Circle().strokeBorder(GoFlyStyle.surface, lineWidth: 1) }
                .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 5, y: 3)
                .offset(thumbOffset)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { value in changed(at: value.location) }
            .onEnded { _ in finishTouch() })
        .onChange(of: touching) { _, touching in
            if !touching { finishTouch() }
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
