#if DEBUG && targetEnvironment(simulator)
import GoFlyCore
import SwiftUI

/// Simulator-only gallery for the redesign's shared components. It is only
/// reachable with `-gofly-ui-gallery`, so it never appears in a normal launch,
/// a device build or a release build. Used for screenshots and UI checks.
struct GoFlyComponentGallery: View {
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var detent: GoFlySheetDetent = .half
    @State private var mode: SessionMapMode = .teleport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                bannerSection
                pillSection
                snackbarSection
                bottomBarSection
                executionSection
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
            HStack(spacing: 8) {
                GoFlyStatusPill(text: goFlyString("gallery.pillActive"),
                                tone: .active, action: {}, identifier: "gallery.pill.active")
                GoFlyStatusPill(text: goFlyString("gallery.pillDanger"),
                                tone: .danger, action: {}, identifier: "gallery.pill.danger")
                GoFlyStatusPill(text: goFlyString("gallery.pillNeutral"),
                                tone: .neutral, identifier: "gallery.pill.neutral")
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
#endif
