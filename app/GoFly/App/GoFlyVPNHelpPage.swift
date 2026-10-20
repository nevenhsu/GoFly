import SwiftUI
import UIKit

/// The same connection instructions are reachable from onboarding and Settings.
struct GoFlyVPNHelpPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var externalOpenFailed = false
    @State private var externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"

    var body: some View {
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
                        dismiss()
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
        .accessibilityIdentifier("vpn.help.page")
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

    private func openLocalDevVPN() {
        externalOpenFailed = false
        externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"
        GoFlyExternalLinks.openLocalDevVPN { externalOpenFailed = !$0 }
    }

    private func openSystemSettings() {
        externalOpenFailed = false
        externalOpenFailureKey = "settings.externalOpenFailed"
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) { accepted in
            externalOpenFailed = !accepted
        }
    }

    private func errorMessage(_ key: String) -> some View {
        GoFlyStatusBanner(tone: .danger, title: goFlyString(key))
    }
}
