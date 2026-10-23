import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyJoystickPanel: View {
    @ObservedObject var controller: JoystickMovementController
    var cameraHeadingDegrees: Double
    var maximumHeight: CGFloat
    var onRandomDestination: () -> Void = { }
    var onSettings: () -> Void = { }
    @State private var contentHeight: CGFloat = 220
    @State private var showingSpeedSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                wanderControls
                Divider().padding(.top, 4)
                if controller.requiresStop {
                    Button(goFlyString("operation.settings"), action: onSettings)
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("joystick.settings")
                } else {
                    speedRow
                    GoFlyManualJoystickPad(controller: controller, cameraHeadingDegrees: cameraHeadingDegrees)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(76, maximumHeight)))
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

    private var speedRow: some View {
        HStack(alignment: .center) {
            Text(goFlyString("route.speed"))
                .font(.body)
                .foregroundStyle(GoFlyStyle.primary)
            Spacer(minLength: 8)
            Button {
                showingSpeedSheet = true
            } label: {
                HStack(spacing: 6) {
                    GoFlySpeedIcon(size: 18)
                    Text(goFlyLocalizedFormat(goFlyString("route.speedShort"), controller.speed.kilometersPerHour))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(GoFlyStyle.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(GoFlyStyle.border, lineWidth: 0.75) }
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!controller.canSetSpeed)
            .accessibilityLabel(goFlyString("route.speed"))
            .accessibilityIdentifier("joystick.speed")
        }
        .frame(minHeight: 44)
    }

    private var wanderControls: some View {
        wanderRow
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("joystick.wanderControls")
    }

    private var wanderRow: some View {
        HStack(spacing: 12) {
            if controller.wanderEnabled {
                Button(action: onRandomDestination) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controller.canRandomizeWanderTarget)
                .accessibilityLabel(goFlyString("joystick.randomDestination"))
                .accessibilityIdentifier("joystick.randomDestination")
            } else {
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.primary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.wanderEnabled ? goFlyString("joystick.wanderActive") : goFlyString("joystick.wander"))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(controller.wanderEnabled ? (controller.wanderTarget?.place.title ?? "") : goFlyString("joystick.wanderDetail"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { controller.wanderEnabled },
                set: { _ = controller.setWanderEnabled($0) }
            ))
            .labelsHidden()
            .fixedSize()
            .tint(GoFlyStyle.success)
            .disabled(!controller.canSetWanderEnabled)
            .accessibilityLabel(goFlyString("joystick.wander"))
            .accessibilityValue(controller.wanderEnabled ? "1" : "0")
            .accessibilityIdentifier("joystick.wander")
        }
        .frame(minHeight: 44)
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
                    Text(caption).font(.caption.weight(.medium)).foregroundStyle(GoFlyStyle.secondary)
                    Text(title).font(.body.weight(.semibold))
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
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                let angle = Double(index) * 90 - cameraHeadingDegrees
                Text(letter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GoFlyStyle.secondary)
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
