import GoFlyCore
import Observation
import SwiftUI
import UIKit

struct ServiceSettingsView: View {
    @ObservedObject var service: ServiceController
    @ObservedObject var movement: GoFlyMovementModel
    @ObservedObject var continuation: MovementContinuationController
    @ObservedObject var recovery: ConnectionRecoveryController
    let setupMetadata: GoFlySetupMetadata?
    @StateObject private var systemStatus = GoFlySystemStatus()
    @ObservedObject private var network = GoFlyNetworkMonitor.shared
    @State private var serviceNoticeDismissed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if network.shouldShowWiFiError {
                    GoFlyStatusBanner(
                        tone: .danger,
                        title: goFlyString("wifi.error.title"),
                        message: goFlyString("wifi.error.message"),
                        actionTitle: goFlyString("wifi.error.action"),
                        onAction: { network.openWiFiSettings() },
                        onDismiss: { network.dismissNotice() },
                        identifier: "settings.wifiError",
                        isFloating: true
                    )
                }
                if let failure = bannerFailure, !serviceNoticeDismissed {
                    GoFlyStatusBanner(
                        tone: .danger,
                        title: goFlyString(failure.rawValue),
                        message: goFlyString("settings.vpn.failureGuide"),
                        actionTitle: goFlyString("operation.retry"),
                        onAction: retryBannerFailure,
                        onDismiss: { serviceNoticeDismissed = true },
                        identifier: "service.error",
                        actionEnabled: !service.nativeBusy,
                        isFloating: true
                    )
                }
                if let key = continuation.noticeKey {
                    GoFlyStatusBanner(
                        tone: .warning,
                        title: goFlyString(key),
                        message: goFlyString("background.systemDecidesRuntime"),
                        identifier: "background.notice.compact",
                        isFloating: true
                    )
                }
                serviceCard
                settingsGroups
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("settings.title"))
        .navigationBarTitleDisplayMode(.large)
        .goFlyNativeBackTitle("settings.title")
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            systemStatus.refresh()
            recovery.requestForegroundCheck()
        }
        .onChange(of: bannerFailure) { _, newFailure in
            if newFailure != nil { serviceNoticeDismissed = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            systemStatus.refresh()
            recovery.requestForegroundCheck()
        }
    }

    /// Settings only surfaces real connection failures; a cancelled operation is never an error here.
    private var bannerFailure: DeviceServiceFailure? {
        let failure: DeviceServiceFailure?
        if case .failed(let preparedFailure)? = service.preparedOperation?.state {
            failure = preparedFailure
        } else if service.preparedOperation == nil {
            failure = service.error
        } else {
            failure = nil
        }
        return failure == .operationCancelled ? nil : failure
    }

    private func retryBannerFailure() {
        if let operation = service.preparedOperation {
            _ = service.retryPreparedOperation(id: operation.id)
        } else {
            _ = service.start()
        }
    }

    private var settingsGroups: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("settings.permissionsAndConnection", footerKey: "settings.permissionsFooter") {
                settingsLink(title: "settings.location", value: locationSummary,
                             destination: { GoFlyLocationSettingsPage() })
                settingsDivider
                settingsLink(title: "settings.vpn", value: goFlyString(recovery.connectionState.settingsStatusKey),
                             destination: { GoFlyVPNSettingsPage(recovery: recovery) })
                settingsDivider
                Button(action: network.openWiFiSettings) {
                    settingsRow(titleKey: "settings.wifi",
                                value: goFlyString(network.isWiFiConnected ? "settings.wifi.connected" : "settings.wifi.notConnected"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.wifi")
                settingsDivider
                settingsLink(title: "settings.background", value: backgroundSummary,
                             destination: { GoFlyBackgroundSettingsPage(continuation: continuation) })
            }
            settingsSection("settings.preferences") {
                settingsLink(title: "settings.language", value: GoFlyPreferences.shared.language.title,
                             destination: { GoFlyLanguageSettingsPage() })
                settingsDivider
                settingsLink(title: "settings.appearance", value: GoFlyPreferences.shared.appearance.title,
                             destination: { GoFlyAppearanceSettingsPage() })
            }
            settingsSection("settings.deviceSection") {
                settingsLink(title: "settings.device", value: nil,
                             destination: { GoFlyDeviceSettingsPage(service: service, setupMetadata: setupMetadata) })
            }
        }
    }

    private var locationSummary: String { goFlyString(systemStatus.locationStatusKey) }
    private var backgroundSummary: String { goFlyString(systemStatus.backgroundStatusKey) }

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ titleKey: String,
        footerKey: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goFlyString(titleKey))
                .font(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                content()
            }
            .goFlyCard(radius: 14)
            if let footerKey {
                Text(goFlyString(footerKey))
                    .font(GoFlyFont.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .padding(.horizontal, 16)
            }
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
            GoFlySettingsBadgeIcon(kind: settingsIconKind(for: titleKey))
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            GoFlySettingsValueRow {
                Text(goFlyString(titleKey))
                    .font(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .multilineTextAlignment(.leading)
            } value: {
                if let value {
                    if (titleKey == "settings.location" && systemStatus.locationAuthorization == .denied) ||
                       (titleKey == "settings.wifi" && !network.isWiFiConnected) {
                        Label(value, systemImage: GoFlySymbols.warning)
                            .font(GoFlyFont.subheadline)
                            .foregroundStyle(GoFlyTextColor.warning)
                    } else {
                        Text(value)
                            .font(GoFlyFont.subheadline)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
            }
            Image(systemName: GoFlySymbols.disclosure)
                .goFlyControlSymbol(size: 12, maximum: 16, weight: .semibold)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var settingsDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func settingsIconKind(for key: String) -> GoFlySettingsIconKind {
        switch key {
        case "settings.location": .location
        case "settings.background": .background
        case "settings.vpn": .vpn
        case "settings.wifi": .wifi
        case "settings.language": .language
        case "settings.appearance": .appearance
        default: .device
        }
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString("service.title")).font(GoFlyFont.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                GoFlyStatusPill(text: goFlyString(movement.status.textKey), tone: movement.status.tone,
                                action: nil, identifier: "service.statusPill")
                    .accessibilityValue(goFlyString(movement.status.textKey))
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

            if service.canForceReset {
                Button {
                    _ = service.forceReset()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: GoFlySymbols.reset)
                            .goFlyControlSymbol(size: 15, weight: .semibold)
                        Text(goFlyString("service.reset"))
                    }
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityHint(goFlyString("service.resetHint"))
                .accessibilityIdentifier("service.reset")
            }

            if service.phase == .repairRequired || service.clearConfirmedAt != nil {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Label(goFlyString("gps.title"), systemImage: "location.circle")
                        .font(GoFlyFont.subheadlineEmphasis)
                    Text(goFlyString(service.gpsStatusKey))
                        .font(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .accessibilityIdentifier("service.gpsStatus")
                    if let date = service.clearConfirmedAt {
                        HStack(spacing: 4) {
                            Text(goFlyString("gps.clearConfirmedAt"))
                            Text(date, style: .time)
                        }
                        .font(GoFlyFont.caption)
                        .foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
            }
        }
        .padding(16)
        .goFlyCard(radius: 14)
    }

    private var status: some View {
        Text(goFlyString(service.statusKey))
            .font(GoFlyFont.subheadline)
            .foregroundStyle(GoFlyTextColor.secondary)
            .accessibilityIdentifier("service.status")
    }

    private var offersStop: Bool {
        movement.status == .simulating || movement.status == .paused
            || service.phase == .preparing || service.phase == .repairRequired || service.isRecoveringConnection
    }
}
