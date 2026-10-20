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
                switch controller.locationAuthorization {
                case .notDetermined: Task { await controller.allowLocation() }
                case .authorized: controller.skipLocation()
                case .denied: openLocationSettings()
                }
            } label: {
                HStack(spacing: 8) {
                    if controller.isRequestingLocation { ProgressView() }
                    Text(goFlyString(locationActionKey))
                }
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .disabled(controller.isRequestingLocation)
            .accessibilityIdentifier("onboarding.location.allow")

            if controller.locationAuthorization != .authorized {
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

    private var locationActionKey: String {
        switch controller.locationAuthorization {
        case .notDetermined: "onboarding.location.allow"
        case .authorized: "onboarding.next"
        case .denied: "onboarding.location.openSettings"
        }
    }

    @ViewBuilder private var locationStatus: some View {
        switch controller.locationAuthorization {
        case .notDetermined:
            Label(goFlyString("settings.status.notDetermined"), systemImage: "location.circle")
                .foregroundStyle(GoFlyStyle.secondary)
                .accessibilityIdentifier("onboarding.location.status")
        case .authorized:
            Label(goFlyString("onboarding.location.authorized"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(GoFlyStyle.successForeground)
                .accessibilityIdentifier("onboarding.location.status")
        case .denied:
            GoFlyStatusBanner(tone: .warning, title: goFlyString("settings.status.denied"),
                              message: goFlyString("onboarding.location.denied"),
                              identifier: "onboarding.location.status")
        }
        if settingsOpenFailed {
            GoFlyStatusBanner(tone: .danger, title: goFlyString("settings.externalOpenFailed"))
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
                GoFlyOnboardingStepIndicator(step: title == "onboarding.welcome.title" ? 1 : 2)
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
                .padding(.horizontal, 24)
                .padding(.top, 16)
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


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                GoFlyOnboardingStepIndicator(step: 3)
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: GoFlySymbols.network)
                        .goFlyControlSymbol(size: 24, weight: .medium)
                        .frame(width: 48, height: 48)
                        .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(goFlyString("onboarding.vpn.title"))
                            .font(.headline)
                        Label(goFlyString(statusKey), systemImage: vpnTone.symbol)
                            .font(.subheadline)
                            .foregroundStyle(vpnTone.foreground)
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
                .buttonStyle(GoFlyActionStyle(primary: true))
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
            .padding(.horizontal, 24)
            .padding(.top, 16)
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
            GoFlyVPNHelpPage()
        }
    }

    private var vpnTone: GoFlyStatusTone {
        switch controller.vpnState {
        case .reachable: .success
        case .unavailable, .timedOut: .danger
        default: .neutral
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
        GoFlyExternalLinks.openStore { accepted in
            externalOpenFailed = !accepted
        }
    }

    private func openLocalDevVPN() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        GoFlyExternalLinks.openLocalDevVPN { externalOpenFailed = !$0 }
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
        GoFlyStatusBanner(tone: .danger, title: goFlyString(key),
                          message: goFlyString("onboarding.vpn.help.intro"))
    }
}

private struct GoFlyOnboardingStepIndicator: View {
    let step: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...3, id: \.self) { index in
                Capsule().fill(index <= step ? GoFlyStyle.primary : GoFlyStyle.border)
                    .frame(height: 4)
            }
            Text("\(step) / 3").font(.caption.monospacedDigit()).foregroundStyle(GoFlyStyle.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: goFlyString("onboarding.step"), step))
    }
}
