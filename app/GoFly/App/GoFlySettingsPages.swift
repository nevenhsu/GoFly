import CoreLocation
import GoFlyCore
import SwiftUI
import UIKit

private struct GoFlySettingsPageContainer<Content: View>: View {
    let titleKey: String
    let rootIdentifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(16)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .goFlyNativeBackTitle()
        .navigationTitle(goFlyString(titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(rootIdentifier)
    }
}

private struct GoFlySettingsStatusCard: View {
    let titleKey: String
    let status: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoFlySettingsValueRow {
                Text(goFlyString(titleKey))
                    .font(.headline)
            } value: {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private struct GoFlySettingsAction: View {
    let titleKey: String
    let action: () -> Void
    var identifier: String
    var disabled = false

    var body: some View {
        Button(action: action) {
            Text(goFlyString(titleKey))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(disabled)
        .accessibilityIdentifier(identifier)
    }
}

struct GoFlyLocationSettingsPage: View {
    @StateObject private var status = GoFlySystemStatus()

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.location", rootIdentifier: "settings.location.page") {
            GoFlySettingsStatusCard(
                titleKey: "settings.location",
                status: locationStatus,
                identifier: "settings.location.status"
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(goFlyString("settings.location.purpose"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                GoFlySettingsAction(
                    titleKey: "settings.openSystemSettings",
                    action: status.openSystemSettings,
                    identifier: "settings.location.open"
                )
                if status.externalOpenFailed {
                    Text(goFlyString("settings.externalOpenFailed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsCard()
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private var locationStatus: String { goFlyString(status.locationStatusKey) }
}

struct GoFlyBackgroundSettingsPage: View {
    @ObservedObject var continuation: MovementContinuationController
    @StateObject private var status = GoFlySystemStatus()

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.background", rootIdentifier: "settings.background.page") {
            GoFlySettingsStatusCard(
                titleKey: "settings.background",
                status: backgroundStatus,
                identifier: "settings.background.status"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(goFlyString("settings.background.purposeTitle"))
                    .font(.headline)
                Text(goFlyString("settings.background.purpose"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsCard()

            GoFlyContinuationStatus(continuation: continuation)

            VStack(alignment: .leading, spacing: 12) {
                GoFlySettingsAction(
                    titleKey: "settings.openSystemSettings",
                    action: status.openSystemSettings,
                    identifier: "settings.background.open"
                )
                if status.externalOpenFailed {
                    Text(goFlyString("settings.externalOpenFailed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsCard()
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private var backgroundStatus: String { goFlyString(status.backgroundStatusKey) }
}

struct GoFlyVPNSettingsPage: View {
    @ObservedObject var recovery: MovementRecoveryController
    @StateObject private var status = GoFlySystemStatus()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.vpn", rootIdentifier: "settings.vpn.page") {
            GoFlySettingsStatusCard(
                titleKey: "settings.vpn",
                status: goFlyString(recovery.connectionState.settingsStatusKey),
                identifier: "settings.vpn.status"
            )

            VStack(alignment: .leading, spacing: 12) {
                Text(goFlyString("settings.vpn.steps"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                GoFlySettingsAction(
                    titleKey: "settings.vpn.openLocalDevVPN",
                    action: status.openLocalDevVPN,
                    identifier: "settings.vpn.open"
                )
                if status.externalOpenFailed {
                    Text(goFlyString("settings.vpn.externalOpenFailed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .settingsCard()

            actionsLayout {
                GoFlySettingsAction(
                    titleKey: "settings.vpn.check",
                    action: recovery.checkConnection,
                    identifier: "settings.vpn.check",
                    disabled: !recovery.canCheck || recovery.isResettingTunnel
                )
                GoFlySettingsAction(
                    titleKey: "service.resetTunnel",
                    action: { _ = recovery.resetTunnel() },
                    identifier: "settings.vpn.reset",
                    disabled: !recovery.canResetTunnel
                )
            }

            if recovery.isChecking || recovery.isResettingTunnel {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("settings.vpn.progress")
            }

            if recovery.connectionState == .unavailable || recovery.connectionState == .timedOut {
                Text(goFlyString("settings.vpn.failureGuide"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsCard()
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
            if recovery.canCheck { recovery.checkConnection() }
        }
    }

    private var actionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}

struct GoFlyDeviceSettingsPage: View {
    @ObservedObject var service: ServiceController
    let setupMetadata: GoFlySetupMetadata?
    @StateObject private var status = GoFlySystemStatus()

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.device", rootIdentifier: "settings.device.page") {
            let snapshot = status.deviceSnapshot(service: service, setupMetadata: setupMetadata)
            VStack(alignment: .leading, spacing: 0) {
                deviceField("settings.device.pairing", value: snapshot.pairingStatus, identifier: "settings.device.pairing")
                Divider()
                deviceField("settings.device.signingExpiry", value: snapshot.signingExpiryStatus, identifier: "settings.device.signingExpiry")
                Divider()
                deviceField("settings.device.teamID", value: snapshot.teamIDStatus, identifier: "settings.device.teamID")
                Divider()
                deviceField("settings.device.service", value: snapshot.serviceStatus, identifier: "settings.device.service")
                Divider()
                deviceField("settings.device.version", value: snapshot.appVersion, identifier: "settings.device.version")
                Divider()
                deviceField("settings.device.system", value: "\(snapshot.deviceName) · \(snapshot.deviceModel) · \(snapshot.systemName) \(snapshot.systemVersion)", identifier: "settings.device.system")
            }
            .settingsCard()

            Text(goFlyString("settings.device.pairingNote"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(goFlyString("settings.device.signingGuideTitle"))
                    .font(.headline)
                Text(goFlyString("settings.device.signingGuide"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsCard()
            .accessibilityIdentifier("settings.device.signingGuide")

            if service.error == .pairingRequired || service.error == .identityMismatch || service.error == .devicePreparationRequired {
                Text(goFlyString("settings.device.repairGuide"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .settingsCard()
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private func deviceField(_ titleKey: String, value: String, identifier: String) -> some View {
        GoFlySettingsValueRow {
            Text(goFlyString(titleKey))
                .font(.body)
        } value: {
            Text(value)
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

struct GoFlyHelpSettingsPage: View {
    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.help", rootIdentifier: "settings.help.page") {
            VStack(alignment: .leading, spacing: 12) {
                Text(goFlyString("settings.help.manualTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.manual"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.wanderTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.wander"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.arrowTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.arrow"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.recenterTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.recenter"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.mapPinTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.mapPin"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.favoritesTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.favorites"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goFlyString("settings.help.waitingTitle"))
                    .font(.headline)
                Text(goFlyString("settings.help.waiting"))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsCard()
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                    .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
            }
    }
}
