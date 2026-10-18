import GoFlyCore
import Observation
import SwiftUI
import UIKit

struct ServiceSettingsView: View {
    @ObservedObject var service: ServiceController
    @ObservedObject var continuation: MovementContinuationController
    @ObservedObject var recovery: MovementRecoveryController
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
                        Label {
                            Text(goFlyString(key))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
                        .accessibilityIdentifier("background.notice.compact")
                    }
                    if let error = service.error, service.preparedOperation == nil {
                        Label {
                            Text(goFlyString(error.rawValue))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
                        .accessibilityIdentifier("service.error")
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
                settingsLink(
                    title: "settings.device",
                    value: systemStatus.deviceSnapshot(service: service, setupMetadata: setupMetadata).pairingStatus,
                    destination: { GoFlyDeviceSettingsPage(service: service, setupMetadata: setupMetadata) }
                )
            }

            settingsSection("settings.preferences") {
                languagePicker
                appearancePicker
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(GoFlyStyle.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                    .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
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
            GoFlySettingsValueRow {
                Text(goFlyString(titleKey))
                    .font(.body)
                    .foregroundStyle(GoFlyStyle.primary)
                    .multilineTextAlignment(.leading)
            } value: {
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var languagePicker: some View {
        @Bindable var preferences = GoFlyPreferences.shared
        return Menu {
            Picker(goFlyString("settings.language"), selection: Binding(
                get: { preferences.language },
                set: { preferences.setLanguage($0) }
            )) {
                ForEach(GoFlyLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
        } label: {
            settingsRow(titleKey: "settings.language", value: preferences.language.title)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goFlyString("settings.language"))
        .accessibilityValue(preferences.language.title)
        .accessibilityIdentifier("settings.language")
    }

    private var appearancePicker: some View {
        @Bindable var preferences = GoFlyPreferences.shared
        return Menu {
            Picker(goFlyString("settings.appearance"), selection: Binding(
                get: { preferences.appearance },
                set: { preferences.setAppearance($0) }
            )) {
                ForEach(GoFlyAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
        } label: {
            settingsRow(titleKey: "settings.appearance", value: preferences.appearance.title)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goFlyString("settings.appearance"))
        .accessibilityValue(preferences.appearance.title)
        .accessibilityIdentifier("settings.appearance")
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(goFlyString("service.title")).font(.headline)
                    Spacer(minLength: 12)
                    status
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("service.title")).font(.headline)
                    status
                }
            }

            Button {
                if offersStop {
                    _ = service.stop()
                } else {
                    _ = service.start()
                }
            } label: {
                HStack(spacing: 8) {
                    if service.nativeBusy { ProgressView() }
                    Text(goFlyString(offersStop ? "service.stop" : "service.start"))
                }
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
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
                Text(goFlyString("gps.title"))
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
        .padding(16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius)
                .strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
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
