import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    let onComplete: @MainActor () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsOpenFailed = false

    private enum Page: Hashable { case location, vpn }

    var body: some View {
        NavigationStack(path: navigationPath) {
            welcome
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .location:
                        location
                    case .vpn:
                        GoFlyVPNOnboardingView(controller: controller, onComplete: onComplete)
                    }
                }
        }
        .tint(GoFlyStyle.primary)
    }

    private var pages: [Page] {
        switch controller.step {
        case .welcome: []
        case .location: [.location]
        case .vpn, .complete: [.location, .vpn]
        }
    }

    private var navigationPath: Binding<[Page]> {
        Binding(
            get: { pages },
            set: { newPages in
                let stepsBack = max(0, pages.count - newPages.count)
                for _ in 0..<stepsBack { controller.goBack() }
            }
        )
    }

    private var welcome: some View {
        GoFlyWelcomeView(isPreparing: false, onNext: controller.advanceWelcome)
    }

    private var location: some View {
        GoFlyOnboardingPage(title: "onboarding.location.title", symbol: "location.fill") {
            Text(goFlyString("onboarding.location.message"))
                .font(.title3)
                .foregroundStyle(GoFlyStyle.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboarding.location")
            locationStatus
        } actions: {
            Button {
                Task { await controller.allowLocation() }
            } label: {
                HStack(spacing: 8) {
                    if controller.isRequestingLocation { ProgressView() }
                    Text(goFlyString(controller.locationAuthorization == .notDetermined
                        ? "onboarding.location.allow" : "onboarding.next"))
                }
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(controller.isRequestingLocation)
            .accessibilityIdentifier("onboarding.location.allow")

            if controller.locationAuthorization == .denied {
                Button(action: openLocationSettings) {
                    Text(goFlyString("onboarding.location.openSettings"))
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("onboarding.location.openSettings")
            } else if controller.locationAuthorization == .notDetermined {
                Button {
                    controller.skipLocation()
                } label: {
                    Text(goFlyString("onboarding.location.skip"))
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("onboarding.location.skip")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.refreshLocationAuthorization() }
        }
    }

    /// iOS shows its permission sheet only once, so a decided permission is
    /// stated here instead of leaving "Next" looking like a missing prompt.
    @ViewBuilder private var locationStatus: some View {
        switch controller.locationAuthorization {
        case .notDetermined:
            EmptyView()
        case .authorized:
            Label(goFlyString("onboarding.location.authorized"), systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("onboarding.location.status")
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label(goFlyString("onboarding.location.denied"), systemImage: GoFlySymbols.warning)
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding.location.status")
                if settingsOpenFailed {
                    Text(goFlyString("settings.externalOpenFailed"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                }
            }
        }
    }

    private func openLocationSettings() {
        settingsOpenFailed = false
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            settingsOpenFailed = true
            return
        }
        UIApplication.shared.open(url) { accepted in
            settingsOpenFailed = !accepted
        }
    }

}

/// Shared by bootstrap and the admitted onboarding flow so first launch opens
/// directly on the welcome page without constructing normal runtime owners early.
struct GoFlyWelcomeView: View {
    let isPreparing: Bool
    let onNext: @MainActor () -> Void

    var body: some View {
        // LocalDevVPN setup belongs to the VPN page, so Welcome carries no body copy.
        GoFlyOnboardingPage(title: "onboarding.welcome.title", symbol: "paperplane.fill") {
            EmptyView()
        } actions: {
            if isPreparing {
                ProgressView(goFlyString("setup.preparing.message"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityIdentifier("onboarding.welcome.loading")
            }
            Button {
                guard !isPreparing else { return }
                onNext()
            } label: {
                Text(goFlyString("onboarding.next"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(isPreparing)
            .accessibilityIdentifier("onboarding.welcome.next")
        }
    }
}

private struct GoFlyOnboardingPage<Content: View, Actions: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GoFlyOnboardingEmblem(symbol: symbol)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                content()
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .background(GoFlyStyle.surface)
        .navigationTitle(goFlyString(title))
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) { actions() }
                .padding(24)
                .background(GoFlyStyle.surface)
                .overlay(alignment: .top) { Divider() }
        }
    }
}

/// A static, decorative emblem keeps first launch calm and respects Reduce Motion.
private struct GoFlyOnboardingEmblem: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(GoFlyStyle.border, lineWidth: 0.5)
                .frame(width: 190, height: 190)
            Circle()
                .stroke(GoFlyStyle.border.opacity(0.7), lineWidth: 0.5)
                .frame(width: 142, height: 142)
            Circle()
                .fill(GoFlyStyle.secondarySurface)
                .frame(width: 100, height: 100)
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(GoFlyStyle.primary)
            Circle()
                .fill(GoFlyStyle.primary)
                .frame(width: 8, height: 8)
                .offset(x: 79, y: -53)
            Circle()
                .fill(GoFlyStyle.secondary)
                .frame(width: 5, height: 5)
                .offset(x: -60, y: 39)
        }
        .frame(width: 208, height: 208)
        .accessibilityHidden(true)
    }
}

private struct GoFlyVPNOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    let onComplete: @MainActor () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var showingHelp = false
    @State private var externalOpenFailed = false
    @State private var externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"

    private let appURL = URL(string: "localdevvpn://")!
    private let storeURL = URL(string: "https://apps.apple.com/app/localdevvpn/id6755608044")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: GoFlySymbols.network)
                        .goFlyControlSymbol(size: 24, weight: .medium)
                        .frame(width: 48, height: 48)
                        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(goFlyString("onboarding.vpn.title"))
                            .font(.headline)
                        Text(goFlyString(statusKey))
                            .font(.subheadline)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("onboarding.vpn.status")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .goFlyCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("onboarding.vpn.stepsTitle"))
                        .font(.headline)
                    Text(goFlyString("onboarding.vpn.steps"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    openLocalDevVPN()
                } label: {
                    Text(goFlyString("onboarding.vpn.open"))
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("onboarding.vpn.open")

                VStack(spacing: 0) {
                    Button {
                        openStore()
                    } label: {
                        externalRow("onboarding.vpn.appStore", icon: GoFlySymbols.externalLink)
                    }
                    Divider().padding(.leading, 16)
                    Button {
                        showingHelp = true
                    } label: {
                        externalRow("onboarding.vpn.help", icon: GoFlySymbols.disclosure)
                    }
                    .accessibilityIdentifier("onboarding.vpn.help.open")
                }
                .buttonStyle(.plain)
                .goFlyCard()

                if controller.vpnState == .unavailable || controller.vpnState == .timedOut {
                    errorMessage(controller.vpnState == .timedOut
                        ? "onboarding.vpn.timedOut" : "onboarding.vpn.unavailable")
                        .accessibilityIdentifier("onboarding.vpn.failure")
                    if let detail = controller.vpnFailureDetail {
                        failureDetail(detail)
                    }
                }
                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }
            }
            .padding(24)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("onboarding.vpn.title"))
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button {
                    controller.checkConnection()
                } label: {
                    HStack(spacing: 8) {
                        if controller.isChecking { ProgressView() }
                        Text(goFlyString(checkButtonKey))
                    }
                }
                .buttonStyle(GoFlyActionStyle())
                .disabled(controller.isAdvancing)
                .accessibilityIdentifier("onboarding.vpn.check")

                Button {
                    controller.advanceVPN(onAdvance: onComplete)
                } label: {
                    HStack(spacing: 8) {
                        if controller.isAdvancing { ProgressView() }
                        Text(goFlyString("onboarding.next"))
                    }
                }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!controller.canAdvanceVPN)
                .accessibilityHint(goFlyString("onboarding.vpn.nextHint"))
                .accessibilityIdentifier("onboarding.vpn.next")
            }
            .padding(24)
            .background(GoFlyStyle.surface)
            .overlay(alignment: .top) { Divider() }
        }
        .onAppear {
            isVisible = true
            controller.setVPNActive(scenePhase == .active)
        }
        .onDisappear {
            isVisible = false
            controller.setVPNActive(false)
        }
        .onChange(of: scenePhase) { _, phase in
            controller.setVPNActive(isVisible && phase == .active)
        }
        .navigationDestination(isPresented: $showingHelp) {
            connectionHelp
        }
    }

    private var statusKey: String {
        switch controller.vpnState {
        case .unknown: "onboarding.vpn.help.notChecked"
        case .checking: "onboarding.vpn.checking"
        case .reachable: "onboarding.vpn.connected"
        case .unavailable, .timedOut: "onboarding.vpn.help.notReachable"
        }
    }

    private var connectionHelp: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: GoFlySymbols.network)
                        .font(.largeTitle)
                        .accessibilityHidden(true)
                    Text(goFlyString("onboarding.vpn.help.heading"))
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(goFlyString("onboarding.vpn.help.intro"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                }

                VStack(spacing: 12) {
                    helpStep(1, symbol: "1.circle.fill")
                    helpStep(2, symbol: "2.circle.fill")
                    helpStep(3, symbol: "3.circle.fill")
                    helpStep(4, symbol: "4.circle.fill")
                }

                Label {
                    Text(goFlyString("onboarding.vpn.help.confirmation"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: GoFlySymbols.information)
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    Text(goFlyString("onboarding.vpn.help.troubleshooting"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 16) {
                        helpTip("onboarding.vpn.help.permission", symbol: "hand.raised")
                        Button(action: openSystemSettings) {
                            Label(goFlyString("onboarding.vpn.help.openSettings"), systemImage: GoFlySymbols.settings)
                        }
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("onboarding.vpn.help.openSettings")
                        Divider()
                        helpTip("onboarding.vpn.help.reconnect", symbol: GoFlySymbols.retry)
                    }
                    .padding(16)
                    .goFlyCard()
                }

                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }

                VStack(spacing: 12) {
                    Button(action: openLocalDevVPN) {
                        Label(goFlyString("onboarding.vpn.open"), systemImage: GoFlySymbols.externalLink)
                    }
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .accessibilityIdentifier("onboarding.vpn.help.openVPN")

                    Button {
                        // Returning reactivates the VPN page's existing serialized check pipeline.
                        showingHelp = false
                    } label: {
                        Text(goFlyString("onboarding.vpn.help.returnAndCheck"))
                    }
                    .buttonStyle(GoFlyActionStyle())
                    .accessibilityIdentifier("onboarding.vpn.help.return")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("onboarding.vpn.help"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpStep(_ number: Int, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(goFlyString("onboarding.vpn.help.step\(number).title"))
                    .font(.headline)
                    .accessibilityIdentifier("onboarding.vpn.help.step\(number)")
                Text(goFlyString("onboarding.vpn.help.step\(number).message"))
                    .font(.body)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .goFlyCard()
    }

    private func helpTip(_ key: String, symbol: String) -> some View {
        Label {
            Text(goFlyString(key))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(GoFlyStyle.secondary)
    }

    private var checkButtonKey: String {
        switch controller.vpnState {
        case .reachable: "onboarding.vpn.connected"
        case .checking: "onboarding.vpn.checking"
        default: "onboarding.vpn.check"
        }
    }

    private func openStore() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        UIApplication.shared.open(storeURL) { accepted in
            externalOpenFailed = !accepted
        }
    }

    private func openLocalDevVPN() {
        externalOpenFailed = false
        UIApplication.shared.open(appURL) { accepted in
            if !accepted { openStore() }
        }
    }

    private func openSystemSettings() {
        externalOpenFailed = false
        externalOpenFailureKey = "settings.externalOpenFailed"
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            externalOpenFailed = true
            return
        }
        UIApplication.shared.open(url) { accepted in
            externalOpenFailed = !accepted
        }
    }

    private func externalRow(_ key: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Text(goFlyString(key))
            Spacer(minLength: 8)
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityHidden(true)
        }
        .font(.body)
        .foregroundStyle(GoFlyStyle.primary)
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    /// iOS's own network reason, shown verbatim so a device report can be diagnosed.
    private func failureDetail(_ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(goFlyString("onboarding.vpn.failureDetail"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(GoFlyStyle.secondary)
            Text(detail)
                .font(.caption.monospaced())
                .foregroundStyle(GoFlyStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding.vpn.failureDetail")
    }

    private func errorMessage(_ key: String) -> some View {
        Label(goFlyString(key), systemImage: GoFlySymbols.warning)
            .font(.footnote)
            .foregroundStyle(GoFlyStyle.errorForeground)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
