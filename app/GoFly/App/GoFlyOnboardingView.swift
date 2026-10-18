import GoFlyCore
import SwiftUI
import UIKit

struct GoFlyOnboardingView: View {
    @ObservedObject var controller: OnboardingController
    let onComplete: @MainActor () -> Void

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
        GoFlyOnboardingPage(title: "onboarding.location.title") {
            Text(goFlyString("onboarding.location.message"))
                .font(.body)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("onboarding.location")
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

            Button {
                controller.skipLocation()
            } label: {
                Text(goFlyString("onboarding.location.skip"))
            }
            .buttonStyle(GoFlyActionStyle())
            .accessibilityIdentifier("onboarding.location.skip")
        }
    }

}

/// Shared by bootstrap and the admitted onboarding flow so first launch opens
/// directly on the welcome page without constructing normal runtime owners early.
struct GoFlyWelcomeView: View {
    let isPreparing: Bool
    let onNext: @MainActor () -> Void

    var body: some View {
        GoFlyOnboardingPage(title: "onboarding.welcome.title") {
            Text(goFlyString("onboarding.welcome.message"))
                .font(.body)
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("onboarding.welcome")
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
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(GoFlyStyle.surface)
        .navigationTitle(goFlyString(title))
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) { actions() }
                .padding(24)
                .background(GoFlyStyle.surface)
        }
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(goFlyString("onboarding.vpn.title"))
                        .font(.body)
                    Spacer(minLength: 8)
                    Text(goFlyString(statusKey))
                        .font(.subheadline)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("onboarding.vpn.status")
                }
                .padding(16)
                .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("onboarding.vpn.stepsTitle"))
                        .font(.headline)
                    Text(goFlyString("onboarding.vpn.steps"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
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
                        externalRow("onboarding.vpn.appStore", icon: "arrow.up.right")
                    }
                    Divider()
                    Button {
                        showingHelp = true
                    } label: {
                        externalRow("onboarding.vpn.help", icon: "chevron.forward")
                    }
                    .accessibilityIdentifier("onboarding.vpn.help.open")
                }
                .buttonStyle(.plain)
                .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))

                if controller.vpnState == .unavailable || controller.vpnState == .timedOut {
                    errorMessage(controller.vpnState == .timedOut
                        ? "onboarding.vpn.timedOut" : "onboarding.vpn.unavailable")
                        .accessibilityIdentifier("onboarding.vpn.failure")
                }
                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }
            }
            .padding(24)
        }
        .background(GoFlyStyle.surface)
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
                    Image(systemName: "network")
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
                }

                Label {
                    Text(goFlyString("onboarding.vpn.help.confirmation"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
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
                            Label(goFlyString("onboarding.vpn.help.openSettings"), systemImage: "gear")
                        }
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("onboarding.vpn.help.openSettings")
                        Divider()
                        helpTip("onboarding.vpn.help.reconnect", symbol: "arrow.clockwise")
                    }
                    .padding(16)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
                }

                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }

                VStack(spacing: 12) {
                    Button(action: openLocalDevVPN) {
                        Label(goFlyString("onboarding.vpn.open"), systemImage: "arrow.up.right")
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
        .background(GoFlyStyle.surface)
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
        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
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
            Image(systemName: icon).font(.footnote)
        }
        .font(.body)
        .foregroundStyle(GoFlyStyle.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func errorMessage(_ key: String) -> some View {
        Label(goFlyString(key), systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(GoFlyStyle.errorForeground)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}
