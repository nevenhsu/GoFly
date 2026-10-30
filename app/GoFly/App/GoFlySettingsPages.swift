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
        .background(GoFlyStyle.cardSurface,
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
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                GoFlyIcon(symbol)
                    .goFlyIconSize(size: 22)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 44, height: 44)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(goFlyString(titleKey))
                        .goFlyFont(GoFlyFont.headline)
                    Text(status)
                        .goFlyFont(GoFlyFont.subheadline)
                        .foregroundStyle(GoFlyTextColor.secondary)
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

    private var symbol: GoFlyIconAsset {
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
                                .goFlyFont(GoFlyFont.body)
                        } value: {
                            Text(locationStatus)
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.location.status")
            }

        }
        .goFlyToastOverlay(topInset: 8) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"),
                                  identifier: "settings.location.externalOpenFailed")
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
    @State private var showingDuration = false
    private var preferences: GoFlyPreferences { GoFlyPreferences.shared }

    var body: some View {
        GoFlySettingsPageContainer(titleKey: "settings.background", rootIdentifier: "settings.background.page") {
            GoFlySettingsGroup {
                GoFlySettingsRow {
                    GoFlySettingsValueRow {
                        Text(goFlyString("settings.background.purposeTitle"))
                            .goFlyFont(GoFlyFont.body)
                    } value: {
                        Text(goFlyString("settings.background.systemTask"))
                            .goFlyFont(GoFlyFont.body)
                            .foregroundStyle(GoFlyTextColor.secondary)
                    }
                }
                Divider().padding(.leading, 16)
                Button { showingDuration = true } label: {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.background.duration"))
                                .goFlyFont(GoFlyFont.body)
                        } value: {
                            Text(GoFlyBackgroundDuration.summary(seconds: preferences.backgroundRunSeconds))
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.background.duration")
            }

            GoFlySettingsGroup {
                Button(action: status.openSystemSettings) {
                    GoFlySettingsRow {
                        GoFlySettingsValueRow {
                            Text(goFlyString("settings.background"))
                                .goFlyFont(GoFlyFont.body)
                        } value: {
                            Text(backgroundStatus)
                                .goFlyFont(GoFlyFont.body)
                                .foregroundStyle(GoFlyTextColor.secondary)
                        }
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.background.open")
            }

            if continuation.hasRuntime || continuation.noticeKey != nil {
                GoFlyContinuationStatus(continuation: continuation)
            }

        }
        .sheet(isPresented: $showingDuration, onDismiss: continuation.backgroundDurationDidChange) {
            GoFlyBackgroundDurationSheet(
                seconds: preferences.backgroundRunSeconds,
                onChange: { preferences.setBackgroundRunSeconds($0) },
                onDismiss: { showingDuration = false })
        }
        .goFlyTracksSystemPresentation(showingDuration, id: "settings.background.duration")
        .goFlyToastOverlay(topInset: 8) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"),
                                  identifier: "settings.background.externalOpenFailed")
            }
            if let key = continuation.noticeKey {
                GoFlyStatusBanner(tone: .warning, title: goFlyString(key),
                                  message: goFlyString("background.systemDecidesRuntime"),
                                  identifier: "background.notice")
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
                            .goFlyFont(GoFlyFont.body)
                    } value: {
                        GoFlyStatusPill(text: goFlyString(recovery.connectionState.settingsStatusKey),
                                        tone: vpnTone,
                                        action: nil,
                                        identifier: "settings.vpn.status")
                    }
                }
            }

            GoFlySettingsGroup {
                Button(action: recovery.checkConnection) {
                    GoFlySettingsRow {
                        Text(goFlyString("settings.vpn.check"))
                            .goFlyFont(GoFlyFont.body)
                        Spacer(minLength: 8)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!recovery.canCheck)
                .accessibilityIdentifier("settings.vpn.check")
                Divider().padding(.leading, 16)
                Button(action: status.openLocalDevVPN) {
                    GoFlySettingsRow {
                        Text(goFlyString("settings.vpn.openLocalDevVPN"))
                            .goFlyFont(GoFlyFont.body)
                        Spacer(minLength: 8)
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.vpn.open")
            }

            GoFlySettingsGroup {
                NavigationLink {
                    GoFlyVPNHelpPage()
                } label: {
                    GoFlySettingsRow {
                        Text(goFlyString("onboarding.vpn.help"))
                            .goFlyFont(GoFlyFont.body)
                        Spacer(minLength: 8)
                        GoFlyIcon(GoFlySymbols.disclosure)
                            .goFlyIconSize(size: 13, maximum: 16)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.vpn.help")
            }

            if recovery.isChecking {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("settings.vpn.progress")
            }
        }
        .navigationDestination(isPresented: $showingHelp) { GoFlyVPNHelpPage() }
        .goFlyToastOverlay(topInset: 8) {
            if status.externalOpenFailed {
                GoFlyStatusBanner(tone: .danger, title: goFlyString("onboarding.vpn.externalOpenFailed"),
                                  identifier: "settings.vpn.externalOpenFailed")
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
                Divider().padding(.leading, 16)
                deviceField("settings.device.signingExpiry", value: snapshot.signingExpiryStatus, identifier: "settings.device.signingExpiry")
                Divider().padding(.leading, 16)
                deviceField("settings.device.teamID", value: snapshot.teamIDStatus, identifier: "settings.device.teamID")
                Divider().padding(.leading, 16)
                deviceField("settings.device.service", value: snapshot.serviceStatus, identifier: "settings.device.service")
                Divider().padding(.leading, 16)
                deviceField("settings.device.version", value: snapshot.appVersion, identifier: "settings.device.version")
                Divider().padding(.leading, 16)
                deviceField("settings.device.system", value: "\(snapshot.deviceName) · \(snapshot.deviceModel) · \(snapshot.systemName) \(snapshot.systemVersion)", identifier: "settings.device.system")
            }

            diagnosticsSection
        }
        .sheet(item: $exportItem) { item in
            GoFlyShareSheet(url: item.url)
        }
        .goFlyTracksSystemPresentation(exportItem != nil, id: "settings.diagnostics.share")
        .goFlyToastOverlay(topInset: 8) {
            if exportFailed {
                GoFlyStatusBanner(tone: .danger,
                                  title: goFlyString("settings.diagnostics.exportFailed"),
                                  onDismiss: { exportFailed = false },
                                  identifier: "settings.diagnostics.exportFailed")
            }
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
                .goFlyFont(GoFlyFont.headline)
            Text(goFlyString("settings.diagnostics.description"))
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            GoFlySettingsAction(
                titleKey: "settings.diagnostics.export",
                action: exportDiagnostics,
                identifier: "settings.diagnostics.export"
            )
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
                .goFlyFont(GoFlyFont.body)
        } value: {
            Text(value)
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    private func helpTopic(_ topic: String, symbol: GoFlyIconAsset) -> some View {
        HStack(alignment: .top, spacing: 14) {
            GoFlyIcon(symbol)
                .goFlyIconSize(size: 20)
                .foregroundStyle(GoFlyTextColor.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(goFlyString("settings.help.\(topic)Title"))
                    .goFlyFont(GoFlyFont.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(goFlyString("settings.help.\(topic)"))
                    .goFlyFont(GoFlyFont.body)
                    .foregroundStyle(GoFlyTextColor.secondary)
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
                .goFlyFont(GoFlyFont.subheadline)
                .foregroundStyle(GoFlyTextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.description")

            Text(goFlyString("background.systemDecidesRuntime"))
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("background.systemDecides")

            if continuation.hasRuntime {
                Label {
                    Text(goFlyString("background.runtimeAvailable"))
                } icon: {
                    GoFlyIcon(GoFlySymbols.success)
                }
                .goFlyFont(GoFlyFont.footnote)
                .foregroundStyle(GoFlyTextColor.secondary)
                .accessibilityIdentifier("background.runtimeAvailable")
            }

        }
        .padding(16)
        .goFlyCard(floating: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("background.card")
    }

    private var title: some View {
        Text(goFlyString("background.title"))
            .goFlyFont(GoFlyFont.headline)
            .accessibilityIdentifier("background.title")
    }

    private var status: some View {
        Text(goFlyString(stateKey))
            .goFlyFont(GoFlyFont.subheadline)
            .foregroundStyle(GoFlyTextColor.secondary)
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

struct GoFlyLanguageSettingsPage: View {
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
        }
        .pickerStyle(.menu)
        .navigationTitle(goFlyString("settings.language"))
        .navigationBarTitleDisplayMode(.inline)
        .goFlyNativeBackTitle()
        .accessibilityIdentifier("settings.language.page")
    }
}

struct GoFlyAppearanceSettingsPage: View {
    @Bindable private var preferences = GoFlyPreferences.shared

    var body: some View {
        Form {
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
        .navigationTitle(goFlyString("settings.appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .goFlyNativeBackTitle()
        .accessibilityIdentifier("settings.appearance.page")
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
