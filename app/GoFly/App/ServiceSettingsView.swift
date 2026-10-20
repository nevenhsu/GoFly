import GoFlyCore
import Observation
import SwiftUI
import UIKit

struct ServiceSettingsView: View {
    @ObservedObject var service: ServiceController
    @ObservedObject var continuation: MovementContinuationController
    @ObservedObject var recovery: ConnectionRecoveryController
    let setupMetadata: GoFlySetupMetadata?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var systemStatus = GoFlySystemStatus()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    serviceCard
                    settingsGroups
                    if let key = continuation.noticeKey {
                        GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                                          message: goFlyString("background.systemDecidesRuntime"),
                                          identifier: "background.notice.compact")
                    }
                    if let error = service.error, service.preparedOperation == nil {
                        GoFlyStatusBanner(tone: .danger, title: goFlyString(error.rawValue),
                                          message: goFlyString("settings.vpn.failureGuide"),
                                          identifier: "service.error")
                    }
                }
                .padding(16)
            }
            .safeAreaInset(edge: .bottom) {
                if let operation = service.preparedOperation {
                    GoFlyOperationPanel(
                        operation: operation, unconfirmedFailure: nil,
                        nativeBusy: service.nativeBusy, maximumHeight: geometry.size.height * 0.45,
                        reasonIdentifier: "service.error",
                        onCancel: { _ = service.cancelPreparation(id: $0) },
                        onRetry: { _ = service.retryPreparedOperation(id: $0) },
                        onReturn: { }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .goFlyNativeBackTitle()
        .toolbar(.visible, for: .navigationBar)
        .onAppear { systemStatus.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            systemStatus.refresh()
        }
    }

    private var settingsGroups: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("settings.permissions") {
                settingsLink(
                    title: "settings.location",
                    value: locationSummary,
                    destination: { GoFlyLocationSettingsPage() }
                )
                settingsDivider
                settingsLink(
                    title: "settings.background",
                    value: backgroundSummary,
                    destination: { GoFlyBackgroundSettingsPage(continuation: continuation) }
                )
            }

            settingsSection("settings.connectionAndDevice") {
                settingsLink(
                    title: "settings.vpn",
                    value: goFlyString(recovery.connectionState.settingsStatusKey),
                    destination: { GoFlyVPNSettingsPage(recovery: recovery) }
                )
                settingsDivider
                settingsLink(
                    title: "settings.device",
                    value: systemStatus.deviceSnapshot(service: service, setupMetadata: setupMetadata).pairingStatus,
                    destination: { GoFlyDeviceSettingsPage(service: service, setupMetadata: setupMetadata) }
                )
            }

            settingsSection("settings.preferences") {
                settingsLink(
                    title: "settings.languageAndAppearance",
                    value: GoFlyPreferences.shared.language.title,
                    destination: { GoFlyPreferencesSettingsPage() }
                )
            }

            settingsSection("settings.helpSection") {
                settingsLink(
                    title: "settings.help",
                    value: nil,
                    destination: { GoFlyHelpSettingsPage() }
                )
            }
        }
    }

    private var locationSummary: String { goFlyString(systemStatus.locationStatusKey) }
    private var backgroundSummary: String { goFlyString(systemStatus.backgroundStatusKey) }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goFlyString(titleKey))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .goFlyCard(radius: GoFlyStyle.cardRadius)
        }
    }

    private func settingsLink<Destination: View>(
        title titleKey: String,
        value: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            settingsRow(titleKey: titleKey, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.\(titleKey.replacingOccurrences(of: "settings.", with: ""))")
    }

    private func settingsRow(titleKey: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: settingsSymbol(for: titleKey))
                .goFlyControlSymbol(size: 17, weight: .semibold)
                .foregroundStyle(GoFlyStyle.surface)
                .frame(width: 30, height: 30)
                .background(GoFlyStyle.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            GoFlySettingsValueRow {
                Text(goFlyString(titleKey))
                    .font(.body)
                    .foregroundStyle(GoFlyStyle.primary)
                    .multilineTextAlignment(.leading)
            } value: {
                if let value {
                    if titleKey == "settings.location" && systemStatus.locationAuthorization == .denied {
                        Label(value, systemImage: GoFlySymbols.warning)
                            .font(.subheadline)
                            .foregroundStyle(GoFlyStyle.warningForeground)
                    } else {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(GoFlyStyle.secondary)
                    }
                }
            }
            Image(systemName: GoFlySymbols.disclosure)
                .goFlyControlSymbol(size: 12, maximum: 16, weight: .semibold)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func settingsSymbol(for key: String) -> String {
        switch key {
        case "settings.location": GoFlySymbols.location
        case "settings.background": GoFlySymbols.background
        case "settings.vpn": GoFlySymbols.network
        case "settings.device": GoFlySymbols.device
        case "settings.language": GoFlySymbols.language
        case "settings.appearance": GoFlySymbols.appearance
        default: GoFlySymbols.help
        }
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString("service.title")).font(.headline)
                    status
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GoFlyStatusPill(text: goFlyString(servicePillKey), tone: servicePillTone,
                                action: nil, identifier: "service.statusPill")
            }
            Button {
                if offersStop {
                    _ = service.stop()
                } else {
                    _ = service.start()
                }
            } label: {
                HStack(spacing: 8) {
                    if service.nativeBusy {
                        ProgressView()
                    } else {
                        Image(systemName: offersStop ? "stop.fill" : GoFlySymbols.play)
                            .goFlyControlSymbol(size: 15, weight: .semibold)
                    }
                    Text(goFlyString(offersStop ? "service.stop" : "service.start"))
                }
            }
            .buttonStyle(GoFlyActionStyle())
            .disabled(offersStop ? !service.canStop : !service.canStart)
            .accessibilityIdentifier("service.primary")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { repairButtons }
            } else {
                HStack(spacing: 12) { repairButtons }
            }

            if service.phase == .ready || service.phase == .preparing {
                Text(goFlyString("service.stopBeforeRepair"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label(goFlyString("gps.title"), systemImage: "location.circle")
                    .font(.subheadline.weight(.semibold))
                Text(goFlyString(service.gpsStatusKey))
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityIdentifier("service.gpsStatus")
                if let date = service.clearConfirmedAt {
                    HStack(spacing: 4) {
                        Text(goFlyString("gps.clearConfirmedAt"))
                        Text(date, style: .time)
                    }
                    .font(.caption)
                    .foregroundStyle(GoFlyStyle.secondary)
                }
            }
        }
        .padding(20)
        .goFlyCard()
    }

    private var servicePillKey: String {
        if service.error != nil || service.phase == .repairRequired { return "service.statusPill.error" }
        switch service.phase {
        case .ready, .preparing, .stopping, .restoring, .resetting: return "service.statusPill.ready"
        case .stopped: return "service.statusPill.stopped"
        case .repairRequired: return "service.statusPill.error"
        }
    }

    private var servicePillTone: GoFlyStatusTone {
        if service.error != nil || service.phase == .repairRequired { return .danger }
        switch service.phase {
        case .ready, .preparing, .stopping, .restoring, .resetting: return .success
        case .stopped: return .neutral
        case .repairRequired: return .danger
        }
    }

    private var status: some View {
        Text(goFlyString(service.statusKey))
            .font(.subheadline)
            .foregroundStyle(GoFlyStyle.secondary)
            .accessibilityIdentifier("service.status")
    }

    @ViewBuilder
    private var repairButtons: some View {
        Button {
            _ = service.restoreGPS()
        } label: {
            Text(goFlyString("service.restoreGPS"))
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(!service.canRestoreGPS || recovery.isChecking || recovery.isResettingTunnel)
        .accessibilityHint(goFlyString("service.repairHint"))
        .accessibilityIdentifier("service.restoreGPS")

        Button {
            _ = recovery.resetTunnel()
        } label: {
            Text(goFlyString("service.resetTunnel"))
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(!recovery.canResetTunnel)
        .accessibilityHint(goFlyString("service.repairHint"))
        .accessibilityIdentifier("service.resetTunnel")
    }

    private var offersStop: Bool {
        service.phase == .ready || service.phase == .preparing
            || service.phase == .repairRequired || service.phase == .stopping
    }
}
