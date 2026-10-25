import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyJoystickPanel: View {
    @ObservedObject var controller: JoystickMovementController
    var cameraHeadingDegrees: Double
    var maximumHeight: CGFloat
    /// Figma E1.a: only the title row and speed chip remain (76 pt panel).
    var isCollapsed = false
    /// Wander simulation has no tab bar, so the panel itself leaves 32 pt (E2) or 24 pt (E2.a) plus the safe area below its content.
    var bottomPadding: CGFloat? = nil
    var onRandomDestination: () -> Void = { }
    var onStartWander: () -> Void = { }
    var canStartWander: Bool?
    var onStopWander: () -> Void = { }
    var onSettings: () -> Void = { }
    @State private var showingSpeedSheet = false

    /// Row 44, 24 pt, 152 pt pad, 24 pt, 52 pt button, then 36 pt — 340 pt under the 12 pt grabber.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wanderControls
                .padding(.top, isCollapsed && !controller.wanderEnabled ? 4 : 8)
            if !isCollapsed {
                if controller.requiresStop {
                    Button(goFlyString("operation.settings"), action: onSettings)
                        .buttonStyle(GoFlyActionStyle(fixedHeight: 52))
                        .padding(.top, 24)
                        .accessibilityIdentifier("joystick.settings")
                } else {
                    GoFlyManualJoystickPad(controller: controller, cameraHeadingDegrees: cameraHeadingDegrees)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    wanderActions
                        .padding(.top, 24)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, bottomPadding ?? (isCollapsed ? 16 : 36))
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingSpeedSheet) {
            GoFlySpeedSheet(
                speed: controller.speed,
                canEdit: controller.canSetSpeed,
                onSpeedChanged: { _ = controller.setSpeed($0) },
                onDismiss: { showingSpeedSheet = false }
            )
        }
        .background(GoFlyStyle.cardSurface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joystick.panel")
    }

    private var wanderControls: some View {
        wanderRow
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("joystick.wanderControls")
    }

    private var wanderRow: some View {
        HStack(spacing: 12) {
            if controller.wanderEnabled || !isCollapsed {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            Text(rowTitle)
                .font(GoFlyFont.title)
                .lineLimit(1)
            Spacer(minLength: 8)
            GoFlySpeedChip(
                speed: controller.speed.kilometersPerHour,
                action: { showingSpeedSheet = true },
                isEnabled: controller.canSetSpeed,
                identifier: "joystick.speed",
                height: 36,
                showsChevron: true
            )
        }
        .frame(height: 44)
    }

    private var rowTitle: String {
        if controller.wanderEnabled { return goFlyString("joystick.wanderActive") }
        return goFlyString(isCollapsed ? "mode.joystick" : "joystick.wander")
    }

    @ViewBuilder
    private var wanderActions: some View {
        if controller.wanderEnabled {
            HStack(spacing: 12) {
                Button(action: onStopWander) { Text(goFlyString("joystick.stopWander")) }
                    .buttonStyle(GoFlyActionStyle(fixedHeight: 52))
                    .accessibilityIdentifier("joystick.stopWander")
                Button(action: onRandomDestination) { Text(goFlyString("joystick.changePlace")) }
                    .buttonStyle(GoFlyActionStyle(primary: true, fixedHeight: 52))
                    .accessibilityIdentifier("joystick.randomDestination")
            }
        } else {
            Button(action: onStartWander) { Text(goFlyString("joystick.startWander")) }
                .buttonStyle(GoFlyActionStyle(primary: true, fixedHeight: 52))
                .disabled(!(canStartWander ?? controller.canSetWanderEnabled))
                .accessibilityIdentifier("joystick.wander")
        }
    }
}

/// The live destination row is also rendered by the simulator component gallery.
struct GoFlyWanderDestinationRow: View {
    let title: String
    let caption: String
    let canRandomize: Bool
    let onRandomDestination: () -> Void
    var wanderEnabled: Binding<Bool>? = nil
    var canToggleWander = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        layout {
            HStack(spacing: 12) {
                Image(systemName: GoFlySymbols.place)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 36, height: 36)
                    .background(GoFlyStyle.secondarySurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(caption).font(GoFlyFont.captionEmphasis).foregroundStyle(GoFlyTextColor.secondary)
                    Text(title).font(GoFlyFont.bodyEmphasis)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onRandomDestination) {
                Image(systemName: "shuffle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(GoFlyStyle.secondarySurface, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canRandomize)
            .accessibilityLabel(goFlyString("joystick.randomDestination"))
            .accessibilityIdentifier("joystick.randomDestination")
            if let wanderEnabled {
                Toggle("", isOn: wanderEnabled)
                    .labelsHidden()
                    .tint(GoFlyStyle.success)
                    .disabled(!canToggleWander)
                    .accessibilityLabel(goFlyString("joystick.wander"))
                    .accessibilityValue(wanderEnabled.wrappedValue ? "1" : "0")
                    .accessibilityIdentifier("joystick.wander")
            }
        }
        .frame(minHeight: 48)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("joystick.destination")
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
    private let diameter: CGFloat = 152
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
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                let angle = Double(index) * 90 - cameraHeadingDegrees
                Text(letter)
                    .font(GoFlyFont.micro)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .offset(x: CGFloat(sin(angle * .pi / 180)) * (diameter / 2 - 24),
                            y: -CGFloat(cos(angle * .pi / 180)) * (diameter / 2 - 24))
                    .accessibilityHidden(true)
            }
            Circle()
                .fill(isEnabled ? GoFlyStyle.surface : GoFlyStyle.disabledSurface)
                .frame(width: thumbDiameter, height: thumbDiameter)
                .overlay {
                    Circle().strokeBorder(isEnabled ? GoFlyStyle.subtleBorder : GoFlyStyle.border, lineWidth: 1)
                    Circle()
                        .fill(isEnabled ? GoFlyStyle.secondarySurface : GoFlyStyle.disabledSurface)
                        .frame(width: 20, height: 20)
                }
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
