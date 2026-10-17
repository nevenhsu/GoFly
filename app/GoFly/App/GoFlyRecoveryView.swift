import GoFlyCore
import SwiftUI

/// A data-only recovery projection. Actions use the existing controller gates.
struct GoFlyRecoveryView: View {
    @ObservedObject var recovery: MovementRecoveryController
    @ObservedObject var store: SessionRecoveryStore
    @ObservedObject var service: ServiceController
    var maximumHeight: CGFloat
    var onSettings: () -> Void = { }
    @State private var contentHeight: CGFloat = 160

    var hasContent: Bool {
        recovery.requiresColdConfirmation || hasSummary || recovery.noticeKey != nil || storageFailure != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if hasSummary {
                    Text(goFlyString("recovery.previousTask"))
                        .font(.headline)
                        .accessibilityIdentifier("recovery.summary.title")
                    summary
                    action("recovery.discard", id: "recovery.discard") {
                        recovery.discardUnverifiedMovement()
                    }
                }
                if let key = recovery.noticeKey {
                    Label(goFlyString(key), systemImage: recovery.requiresColdConfirmation
                          ? "exclamationmark.triangle" : "network")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("recovery.notice")
                }
                if recovery.requiresColdConfirmation {
                    action("service.restoreGPS", id: "recovery.restoreGPS") { _ = service.restoreGPS() }
                        .disabled(!service.canRestoreGPS)
                }
                if recovery.noticeKey != nil {
                    action("onboarding.vpn.check", id: "recovery.checkConnection") { recovery.checkConnection() }
                        .disabled(!recovery.canCheck)
                }
                if recovery.requiresColdConfirmation || recovery.noticeKey != nil {
                    action("operation.settings", id: "recovery.settings", perform: onSettings)
                }
                if let failure = storageFailure {
                    Label(goFlyString(failure.localizationKey), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("recovery.storageError")
                    if store.loadState == .ready && store.hasUnsavedChanges
                        && [.writeFailed, .unavailable, .unsafeFile].contains(failure) {
                        action("operation.retry", id: "recovery.retrySaving") { _ = store.retrySaving() }
                            .disabled(store.isSaving)
                    }
                }
                if hasContent && store.isSaving {
                    ProgressView(goFlyString("recovery.saving"))
                        .font(.footnote)
                } else if hasContent && store.hasUnsavedChanges && storageFailure != nil {
                    Text(goFlyString("recovery.unsaved"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(44, maximumHeight)))
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recovery.panel")
    }

    private var storageFailure: SessionRecoveryFailure? {
        if case .blocked(let failure) = store.loadState { return failure }
        return store.error
    }

    private var hasSummary: Bool {
        recovery.unverifiedMovement != nil || (recovery.requiresColdConfirmation &&
            (recovery.unverifiedUncertainty.map { $0.source != .unverifiedPreviousMovement } ?? false))
    }

    @ViewBuilder private var summary: some View {
        switch recovery.unverifiedMovement {
        case .route(let route):
            Text(goFlyString("mode.route")).font(.subheadline.weight(.semibold))
            Text(goFlyLocalizedFormat(goFlyString("recovery.routeProgress"),
                route.progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(GoFlyPreferences.shared.locale))))
                .accessibilityIdentifier("recovery.routeProgress")
            if route.usesPositionAxis {
                HStack(alignment: .top) {
                    Text(goFlyString("route.axis.origin"))
                    Spacer(minLength: 8)
                    Text(goFlyString("route.axis.destination")).multilineTextAlignment(.trailing)
                }
                .font(.caption)
            }
            Text(goFlyString("route.direction.\(route.heading.rawValue)"))
                .accessibilityIdentifier("recovery.routeHeading")
            if route.roundTripEnabled { Text(goFlyString("route.roundTrip")) }
        case .wander(let wander):
            Text(goFlyLocalizedFormat(goFlyString("joystick.currentTarget"), wander.target.place.title))
                .accessibilityIdentifier("recovery.wanderTarget")
        case .manual:
            Text(goFlyString("recovery.manualWaiting"))
                .accessibilityIdentifier("recovery.manualSummary")
        case nil:
            Text(goFlyString("recovery.uncertain"))
                .accessibilityIdentifier("recovery.uncertainty")
            if let place = recovery.unverifiedUncertainty?.requestedPlace {
                Text(goFlyLocalizedFormat(goFlyString("operation.destination"), place.title))
                    .accessibilityIdentifier("recovery.requestedPlace")
            }
        }
    }

    private func action(_ key: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(goFlyString(key))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyActionStyle())
        .accessibilityIdentifier(id)
    }
}
