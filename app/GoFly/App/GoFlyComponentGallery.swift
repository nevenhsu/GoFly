#if DEBUG && targetEnvironment(simulator)
import Combine
import GoFlyCore
import SwiftUI

/// Simulator-only gallery for the redesign's shared components. It is only
/// reachable with `-gofly-ui-gallery`, so it never appears in a normal launch,
/// a device build or a release build. Used for screenshots and UI checks.
struct GoFlyComponentGallery: View {
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var detent: GoFlySheetDetent = .half
    @State private var mode: SessionMapMode = .teleport
    @StateObject private var joystick = JoystickMovementController(commands: GalleryJoystickCommands())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                bannerSection
                pillSection
                snackbarSection
                bottomBarSection
                executionSection
                joystickSection
                sheetSection
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .goFlySnackbar($snackbar)
        .accessibilityIdentifier("gallery")
    }

    private var bannerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("StatusBanner")
            GoFlyStatusBanner(
                tone: .danger,
                title: goFlyString("gallery.dangerTitle"),
                message: goFlyString("statusBanner.repairHint"),
                actionTitle: goFlyString("operation.settings"),
                onAction: {},
                onDismiss: {},
                identifier: "gallery.banner.danger"
            )
            GoFlyStatusBanner(
                tone: .warning,
                title: goFlyString("gallery.warningTitle"),
                message: goFlyString("gallery.warningMessage"),
                identifier: "gallery.banner.warning"
            )
            GoFlyStatusBanner(
                tone: .success,
                title: goFlyString("gallery.successTitle"),
                identifier: "gallery.banner.success"
            )
        }
    }

    private var pillSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("StatusPill")
            let statuses: [GoFlySessionStatus] = [.started, .simulating, .paused, .stopped, .error]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(statuses, id: \.textKey) { status in
                    GoFlyStatusPill(text: goFlyString(status.textKey), tone: status.tone,
                                    identifier: "gallery.pill." + status.textKey)
                }
            }
        }
    }

    private var snackbarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Snackbar")
            Button(goFlyString("gallery.showSnackbar")) {
                snackbar = GoFlySnackbarMessage(
                    text: goFlyString("gallery.snackbarText"),
                    actionTitle: goFlyString("common.undo"),
                    action: {})
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("gallery.snackbar.show")
            GoFlySnackbar(message: GoFlySnackbarMessage(
                text: goFlyString("gallery.snackbarText"),
                actionTitle: goFlyString("common.undo"),
                action: {}))
            .accessibilityIdentifier("gallery.snackbar.preview")
        }
    }

    private var bottomBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("BottomBar")
            GoFlyBottomBar(selection: $mode)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityIdentifier("gallery.bottomBar")
        }
    }

    private var executionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Execution")
            GoFlyWanderDestinationRow(title: goFlyString("gallery.executionTitle"),
                                     caption: goFlyString("joystick.wander"), canRandomize: true,
                                     onRandomDestination: {})
            GoFlyExecutionHeader(title: goFlyString("gallery.executionTitle"),
                                 detail: goFlyString("gallery.executionDetail"))
            GoFlyExecutionControls(progress: 0.42, isPaused: false, canPause: true, canResume: false,
                                   onPause: {}, onResume: {}, onEnd: {}) {
                GoFlyExecutionToggle(title: goFlyString("route.roundTrip"),
                                     symbol: GoFlySymbols.swap, isOn: true, action: {},
                                     identifier: "gallery.execution.roundTrip")
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var joystickSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("JoystickPanel")
            GoFlyJoystickPanel(
                controller: joystick,
                cameraHeadingDegrees: 0,
                maximumHeight: 420,
                onRandomDestination: {},
                onSettings: {}
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
        }
    }

    private var sheetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("BottomSheet")
            GoFlyBottomSheet(detent: $detent, availableHeight: 520, collapsedHeight: 96) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(goFlyString("gallery.sheetTitle")).font(.headline)
                    Text(goFlyString("gallery.sheetBody"))
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                    ForEach(0..<6, id: \.self) { index in
                        Text(goFlyString("gallery.sheetRow"))
                            .font(.body)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

@MainActor
private final class GalleryJoystickCommands: JoystickCommanding {
    private let subject = PassthroughSubject<JoystickCommandEvent, Never>()
    var canBeginJoystick: Bool { true }
    var currentJoystickOrigin: GeoCoordinate? { GeoCoordinate(latitude: 25.0330, longitude: 121.5654) }
    var movementAdmissionRevision: UInt64 { 1 }
    var joystickEvents: AnyPublisher<JoystickCommandEvent, Never> { subject.eraseToAnyPublisher() }
    func beginJoystick(_ intent: JoystickMovementIntent, expectedMovementAdmissionRevision: UInt64) async -> JoystickPreparationOutcome { .cancelled }
    func joystickInputRevision(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func reviseJoystickInput(executionID: UUID, lease: MovementTaskLease) -> JoystickInputRevision? { nil }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, displacement: JoystickDisplacement) async -> JoystickStepOutcome { .cancelled }
    func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64, expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome { .cancelled }
    func releaseJoystick(executionID: UUID, lease: MovementTaskLease, disposition: JoystickReleaseDisposition) -> Bool { false }
    func resumeJoystick(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool { false }
    func waitForJoystickIdle(executionID: UUID, lease: MovementTaskLease) async -> JoystickIdleSettlement { .settled }
}
#endif
