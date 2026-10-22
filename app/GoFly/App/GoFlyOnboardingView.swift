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
        ScrollView {
            VStack(spacing: 16) {
                GoFlyOnboardingStepIndicator(step: 2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                GoFlyOnboardingEmblem(symbol: "location.fill")
                    .padding(.top, 48)
                VStack(spacing: 8) {
                    Text(goFlyString("onboarding.location.title"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(goFlyString("onboarding.location.message"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.location")
                }
                .padding(.top, 8)
                locationStatus
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.surface)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
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
                        Text(goFlyString(controller.locationAuthorization == .denied
                            ? "onboarding.location.continue" : "onboarding.location.skip"))
                    }
                    .buttonStyle(GoFlyActionStyle())
                    .accessibilityIdentifier("onboarding.location.skip")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(GoFlyStyle.surface)
            .overlay(alignment: .top) { Divider() }
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
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.notDetermined")),
                            tone: .neutral, identifier: "onboarding.location.status")
                .padding(.top, 8)
        case .authorized:
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.authorized")),
                            tone: .success, identifier: "onboarding.location.status")
                .padding(.top, 8)
        case .denied:
            GoFlyStatusPill(text: goFlyLocalizedFormat(goFlyString("onboarding.location.statusFormat"),
                                goFlyString("onboarding.location.status.denied")),
                            tone: .warning, identifier: "onboarding.location.status")
                .padding(.top, 8)
        }

        if controller.locationAuthorization == .denied {
            GoFlyStatusBanner(tone: .warning,
                              title: goFlyString("onboarding.location.deniedTitle"),
                              message: goFlyString("onboarding.location.denied"),
                              identifier: "onboarding.location.deniedBanner")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isWelcome: Bool {
        title == "onboarding.welcome.title"
    }

    private var emblemTopSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 48 : 80
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GoFlyOnboardingStepIndicator(step: title == "onboarding.welcome.title" ? 1 : 2)
                    .padding(.top, 10)
                GoFlyOnboardingEmblem(symbol: symbol)
                    .padding(.top, emblemTopSpacing)
                Text(goFlyString(title))
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                content()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.surface)
        // Keep the welcome page visually quiet while retaining the system back
        // button on the pushed location page for keyboard and VoiceOver users.
        .toolbar(isWelcome ? .hidden : .visible, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
        Image(systemName: symbol)
            .font(.system(size: 48, weight: .medium))
            .foregroundStyle(GoFlyStyle.primary)
            .frame(width: 120, height: 120)
            .background(GoFlyStyle.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct GoFlyOnboardingFeatureIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(GoFlyStyle.primary)
            .frame(width: 72, height: 72)
            .background(GoFlyStyle.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
            VStack(alignment: .leading, spacing: 14) {
                GoFlyOnboardingStepIndicator(step: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                VStack(alignment: .leading, spacing: 8) {
                    Text(goFlyString("onboarding.vpn.title"))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(goFlyString("onboarding.vpn.subtitle"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if controller.vpnState == .unavailable || controller.vpnState == .timedOut {
                    errorMessage(controller.vpnState == .timedOut
                        ? "onboarding.vpn.timedOut" : "onboarding.vpn.unavailable")
                } else if controller.vpnState == .reachable {
                    GoFlyStatusBanner(tone: .success,
                                      title: goFlyString("onboarding.vpn.connected"),
                                      identifier: "onboarding.vpn.status")
                }
                if externalOpenFailed {
                    GoFlyStatusBanner(tone: .danger, title: goFlyString(externalOpenFailureKey))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(goFlyString("onboarding.vpn.stepsTitle"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GoFlyStyle.secondary)
                    vpnStepRow(number: 1, title: "onboarding.vpn.step1")
                    Divider().padding(.leading, 32)
                    vpnStepRow(number: 2, title: "onboarding.vpn.step2")
                    Divider().padding(.leading, 32)
                    vpnStepRow(number: 3, title: "onboarding.vpn.step3")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GoFlyStyle.secondarySurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    showingHelp = true
                } label: {
                    Text(goFlyString("onboarding.vpn.helpLink"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .frame(minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.vpn.help.open")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.surface)
        // This page is pushed from location, so its native back button remains
        // available to the onboarding UI test and assistive technologies.
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 12) {
                Button {
                    openLocalDevVPN()
                } label: {
                    Label(goFlyString("onboarding.vpn.open"), systemImage: "arrow.up.forward.square")
                }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .accessibilityIdentifier("onboarding.vpn.open")

                HStack(spacing: 12) {
                    Button {
                        controller.checkConnection()
                    } label: {
                        HStack(spacing: 8) {
                            if controller.isChecking { ProgressView() }
                            Text(goFlyString("onboarding.vpn.check"))
                        }
                    }
                    .buttonStyle(GoFlyCompactActionStyle())
                    .disabled(controller.isAdvancing)
                    .accessibilityIdentifier("onboarding.vpn.check")

                    Button {
                        controller.advanceVPN(onAdvance: onComplete)
                    } label: {
                        HStack(spacing: 8) {
                            if controller.isAdvancing { ProgressView() }
                            Text(goFlyString("onboarding.vpn.complete"))
                        }
                    }
                    .buttonStyle(GoFlyCompactActionStyle(primary: true))
                    .disabled(!controller.canAdvanceVPN)
                    .accessibilityHint(goFlyString("onboarding.vpn.nextHint"))
                    .accessibilityIdentifier("onboarding.vpn.next")
                }
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
        .frame(minHeight: 52)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func vpnStepRow(number: Int, title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(GoFlyStyle.surface)
                .frame(width: 22, height: 22)
                .background(GoFlyStyle.primary, in: Circle())
                .accessibilityHidden(true)
            Text(goFlyString(title))
                .font(.subheadline)
                .foregroundStyle(GoFlyStyle.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorMessage(_ key: String) -> some View {
        GoFlyStatusBanner(tone: .danger,
                          title: goFlyString("onboarding.vpn.unavailableTitle"),
                          message: goFlyString(key),
                          identifier: "onboarding.vpn.failure")
    }
}

private struct GoFlyOnboardingStepIndicator: View {
    let step: Int
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { index in
                Capsule().fill(index <= step ? GoFlyStyle.primary : GoFlyStyle.border)
                        .frame(width: 37, height: 4)
                }
            }
            Text(goFlyLocalizedFormat(goFlyString("onboarding.step"), step))
                .font(.caption.monospacedDigit())
                .foregroundStyle(GoFlyStyle.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: goFlyString("onboarding.step"), step))
    }
}

private struct GoFlyCompactActionStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if !primary && isEnabled {
                    Capsule().strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }

    private var background: Color {
        guard isEnabled else { return GoFlyStyle.disabledSurface }
        return primary ? GoFlyStyle.primary : GoFlyStyle.secondarySurface
    }

    private var foreground: Color {
        guard isEnabled else { return GoFlyStyle.disabledForeground }
        return primary ? GoFlyStyle.surface : GoFlyStyle.primary
    }
}
