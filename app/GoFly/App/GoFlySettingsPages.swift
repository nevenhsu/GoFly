import CoreLocation
import GoFlyCore
import Observation
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

private struct GoFlySettingsGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(GoFlyStyle.surface,
                    in: RoundedRectangle(cornerRadius: 14,
                                         style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

private struct GoFlySettingsRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
    }
}

private struct GoFlySettingsStatusCard: View {
    let titleKey: String
    let status: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: symbol)
                    .goFlyControlSymbol(size: 22, weight: .medium)
                    .foregroundStyle(GoFlyStyle.primary)
                    .frame(width: 44, height: 44)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(goFlyString(titleKey))
                        .font(.headline)
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .goFlyCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var symbol: String {
        switch titleKey {
        case "settings.location": GoFlySymbols.location
        case "settings.background": GoFlySymbols.background
        case "settings.vpn": GoFlySymbols.network
        default: GoFlySymbols.device
        }
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
            GoFlySettingsGroup {
                Button(action: status.openSystemSettings) {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.location"))
                                .font(.body)
                        } value: {
                            Text(locationStatus)
                                .font(.body)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }
                        Image(systemName: GoFlySymbols.disclosure)
                            .goFlyControlSymbol(size: 13, maximum: 16, weight: .semibold)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.location.status")
            }

            Text(goFlyString("settings.location.purpose"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("settings.location.purpose")
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"))
            }
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
            GoFlySettingsGroup {
                GoFlySettingsRow {
                    GoFlySettingsValueRow {
                        Text(goFlyString("settings.background.purposeTitle"))
                            .font(.body)
                    } value: {
                        Text(goFlyString("background.systemDecidesRuntime"))
                            .font(.body)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().padding(.leading, 16)
                Button(action: status.openSystemSettings) {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.background"))
                                .font(.body)
                        } value: {
                            Text(backgroundStatus)
                                .font(.body)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }
                        Image(systemName: GoFlySymbols.disclosure)
                            .goFlyControlSymbol(size: 13, maximum: 16, weight: .semibold)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.background.open")
            }

            Text(goFlyString("settings.background.purpose"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("background.description")

            if continuation.hasRuntime || continuation.noticeKey != nil {
                GoFlyContinuationStatus(continuation: continuation)
            }

            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"))
            }
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    private var backgroundStatus: String { goFlyString(status.backgroundStatusKey) }
}

struct GoFlyVPNSettingsPage: View {
    @ObservedObject var recovery: ConnectionRecoveryController
    @StateObject private var status = GoFlySystemStatus()
    @State private var showingHelp = false

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.vpn", rootIdentifier: "settings.vpn.page") {
            GoFlySettingsGroup {
                GoFlySettingsRow {
                    GoFlySettingsValueRow {
                        Text(goFlyString("settings.vpn"))
                            .font(.body)
                    } value: {
                        GoFlyStatusPill(text: goFlyString(recovery.connectionState.settingsStatusKey),
                                        tone: vpnTone,
                                        action: nil,
                                        identifier: "settings.vpn.status")
                    }
                }
                Divider().padding(.leading, 16)
                GoFlySettingsRow {
                    Text(goFlyString("settings.vpn.check"))
                        .font(.body)
                    Spacer(minLength: 8)
                    Text(goFlyString(recovery.connectionState.settingsStatusKey))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
            }

            GoFlySettingsGroup {
                Button(action: recovery.checkConnection) {
                    GoFlySettingsRow {
                        Text(goFlyString("settings.vpn.check"))
                            .font(.body)
                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!recovery.canCheck || recovery.isResettingTunnel)
                .accessibilityIdentifier("settings.vpn.check")
                Divider().padding(.leading, 16)
                Button(action: status.openLocalDevVPN) {
                    GoFlySettingsRow {
                        Text(goFlyString("settings.vpn.openLocalDevVPN"))
                            .font(.body)
                        Spacer(minLength: 8)
                        Image(systemName: GoFlySymbols.disclosure)
                            .goFlyControlSymbol(size: 13, maximum: 16, weight: .semibold)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.vpn.open")
                Divider().padding(.leading, 16)
                Button(action: { _ = recovery.resetTunnel() }) {
                    GoFlySettingsRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goFlyString("service.resetTunnel"))
                                .font(.body)
                            Text(goFlyString("service.stopBeforeRepair"))
                                .font(.caption)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!recovery.canResetTunnel)
                .accessibilityIdentifier("settings.vpn.reset")
            }

            GoFlySettingsGroup {
                NavigationLink {
                    GoFlyVPNHelpPage()
                } label: {
                    GoFlySettingsRow {
                        Text(goFlyString("onboarding.vpn.help"))
                            .font(.body)
                        Spacer(minLength: 8)
                        Image(systemName: GoFlySymbols.disclosure)
                            .goFlyControlSymbol(size: 13, maximum: 16, weight: .semibold)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.vpn.help")
            }

            Text(goFlyString("settings.vpn.steps"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("onboarding.vpn.externalOpenFailed"))
            }

            if recovery.isChecking || recovery.isResettingTunnel {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("settings.vpn.progress")
            }

            if recovery.connectionState == .unavailable || recovery.connectionState == .timedOut {
                GoFlyStatusBanner(tone: .danger,
                                  title: goFlyString(recovery.connectionState.settingsStatusKey),
                                  message: goFlyString("settings.vpn.failureGuide"),
                                  actionTitle: goFlyString("onboarding.vpn.help"),
                                  onAction: { showingHelp = true },
                                  identifier: "settings.vpn.failure")
            }
        }
        .navigationDestination(isPresented: $showingHelp) { GoFlyVPNHelpPage() }
        .onAppear {
            status.refresh()
            if recovery.canCheck { recovery.checkConnection() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
            if recovery.canCheck { recovery.checkConnection() }
        }
    }

    private var vpnTone: GoFlyStatusTone {
        switch recovery.connectionState {
        case .reachable: .success
        case .unavailable, .timedOut: .danger
        case .checking: .warning
        case .unknown: .neutral
        }
    }

}

struct GoFlyDeviceSettingsPage: View {
    @ObservedObject var service: ServiceController
    let setupMetadata: GoFlySetupMetadata?
    @StateObject private var status = GoFlySystemStatus()
    @State private var exportItem: DiagnosticsShareItem?
    @State private var exportFailed = false

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.device", rootIdentifier: "settings.device.page") {
            let snapshot = status.deviceSnapshot(service: service, setupMetadata: setupMetadata)
            GoFlySettingsGroup {
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

            Text(goFlyString("settings.device.pairingNote"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)

            diagnosticsSection
        }
        .sheet(item: $exportItem) { item in
            GoFlyShareSheet(url: item.url)
        }
        .onAppear { status.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status.refresh()
        }
    }

    /// Keeps the diagnostics export reachable from Settings › Device after the
    /// UI redesign; it is the only way to collect evidence without USB.
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(goFlyString("settings.diagnostics.title"))
                .font(.headline)
            Text(goFlyString("settings.diagnostics.description"))
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GoFlySettingsAction(
                titleKey: "settings.diagnostics.export",
                action: exportDiagnostics,
                identifier: "settings.diagnostics.export"
            )
            if exportFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.diagnostics.exportFailed"))
            }
        }
        .settingsCard()
    }

    private func exportDiagnostics() {
        do {
            exportItem = DiagnosticsShareItem(url: try Diagnostics.shared.export())
            exportFailed = false
            Diagnostics.shared.record("diagnostics.export", category: .device, level: .notice, [:])
        } catch {
            exportFailed = true
            Diagnostics.shared.record("diagnostics.exportFailed", category: .device, level: .error, [:])
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
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

struct GoFlyHelpSettingsPage: View {
    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.help", rootIdentifier: "settings.help.page") {
            VStack(alignment: .leading, spacing: 0) {
                helpTopic("manual", symbol: GoFlySymbols.manualMovement)
                helpDivider
                helpTopic("wander", symbol: GoFlySymbols.walking)
                helpDivider
                helpTopic("arrow", symbol: GoFlySymbols.heading)
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 0) {
                helpTopic("recenter", symbol: GoFlySymbols.recenter)
                helpDivider
                helpTopic("mapPin", symbol: GoFlySymbols.place)
                helpDivider
                helpTopic("favorites", symbol: GoFlySymbols.favorite)
                helpDivider
                helpTopic("waiting", symbol: GoFlySymbols.waiting)
            }
            .settingsCard()
        }
    }

    private var helpDivider: some View {
        Divider().padding(.leading, 38).padding(.vertical, 16)
    }

    private func helpTopic(_ topic: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .goFlyControlSymbol(size: 20, weight: .medium)
                .foregroundStyle(GoFlyStyle.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(goFlyString("settings.help.\(topic)Title"))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(goFlyString("settings.help.\(topic)"))
                    .font(.body)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    func settingsCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .goFlyCard()
    }
}

struct GoFlyContinuationStatus: View {
    @ObservedObject var continuation: MovementContinuationController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 12)
                    status
                }
                VStack(alignment: .leading, spacing: 8) {
                    title
                    status
                }
            }

            Text(goFlyString("background.description"))
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.description")

            Text(goFlyString("background.systemDecidesRuntime"))
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.systemDecides")

            if continuation.hasRuntime {
                Label {
                    Text(goFlyString("background.runtimeAvailable"))
                } icon: {
                    Image(systemName: GoFlySymbols.success)
                }
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("background.runtimeAvailable")
            }

            if let key = continuation.noticeKey {
                GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                                  message: goFlyString("background.systemDecidesRuntime"),
                                  identifier: "background.notice")
            }
        }
        .padding(16)
        .goFlyCard(floating: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("background.card")
    }

    private var title: some View {
        Text(goFlyString("background.title"))
            .font(.headline)
            .accessibilityIdentifier("background.title")
    }

    private var status: some View {
        Text(goFlyString(stateKey))
            .font(.subheadline)
            .foregroundStyle(GoFlyStyle.secondary)
            .accessibilityIdentifier("background.status")
    }

    private var stateKey: String {
        switch continuation.state {
        case .idle: return "background.state.idle"
        case .submitting: return "background.state.submitting"
        case .accepted: return "background.state.accepted"
        case .running: return "background.state.running"
        case .rejected: return "background.state.rejected"
        case .expired: return "background.state.expired"
        case .finished: return "background.state.finished"
        }
    }
}

struct GoFlyPreferencesSettingsPage: View {
    @Bindable private var preferences = GoFlyPreferences.shared

    var body: some View {
        Form {
            Section {
                Picker(goFlyString("settings.language"), selection: Binding(
                    get: { preferences.language },
                    set: { preferences.setLanguage($0) }
                )) {
                    ForEach(GoFlyLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.language")
            } header: {
                Text(goFlyString("settings.language"))
            }
            Section {
                Picker(goFlyString("settings.appearance"), selection: Binding(
                    get: { preferences.appearance },
                    set: { preferences.setAppearance($0) }
                )) {
                    ForEach(GoFlyAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.appearance")
            } header: {
                Text(goFlyString("settings.appearance"))
            }
        }
        .pickerStyle(.menu)
        .navigationTitle(goFlyString("settings.languageAndAppearance"))
        .navigationBarTitleDisplayMode(.inline)
        .goFlyNativeBackTitle()
        .accessibilityIdentifier("settings.preferences.page")
    }
}
