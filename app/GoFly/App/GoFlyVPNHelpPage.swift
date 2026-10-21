import SwiftUI
import UIKit

/// The same connection instructions are reachable from onboarding and Settings.
struct GoFlyVPNHelpPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var externalOpenFailed = false
    @State private var externalOpenFailureKey = "onboarding.vpn.externalOpenFailed"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString("onboarding.vpn.help.heading"))
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(goFlyString("onboarding.vpn.help.intro"))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                }

                VStack(spacing: 0) {
                    helpStep(1, symbol: "1.circle.fill")
                    Divider().padding(.leading, 56)
                    helpStep(2, symbol: "2.circle.fill")
                    Divider().padding(.leading, 56)
                    helpStep(3, symbol: "3.circle.fill")
                    Divider().padding(.leading, 56)
                    helpStep(4, symbol: "4.circle.fill")
                }
                .goFlyCard(radius: 14)

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
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 16) {
                        helpTip("onboarding.vpn.help.reconnect", symbol: GoFlySymbols.retry)
                        Divider()
                            .padding(.leading, 0)
                        helpTip("onboarding.vpn.help.permission", symbol: "hand.raised")
                        Button(action: openSystemSettings) {
                            Label(goFlyString("onboarding.vpn.help.openSettings"), systemImage: GoFlySymbols.settings)
                        }
                        .buttonStyle(GoFlyActionStyle())
                        .accessibilityIdentifier("onboarding.vpn.help.openSettings")
                        Button(action: openLocalDevVPN) {
                            Label(goFlyString("onboarding.vpn.open"), systemImage: GoFlySymbols.externalLink)
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(GoFlyStyle.primary)
                        .accessibilityIdentifier("onboarding.vpn.help.openVPN")
                    }
                    .padding(16)
                    .goFlyCard(radius: 14)
                }

                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("onboarding.vpn.help"))
        .navigationBarTitleDisplayMode(.inline)
        .goFlyNativeBackTitle()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                // Returning reactivates the VPN page's existing serialized check pipeline.
                dismiss()
            } label: {
                Text(goFlyString("onboarding.vpn.help.returnAndCheck"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("onboarding.vpn.help.return")
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(GoFlyStyle.canvas)
            .overlay(alignment: .top) { Divider() }
        }
        .accessibilityIdentifier("vpn.help.page")
    }

    private func helpStep(_ number: Int, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(GoFlyStyle.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(goFlyString("onboarding.vpn.help.step\(number).title"))
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("onboarding.vpn.help.step\(number)")
                Text(goFlyString("onboarding.vpn.help.step\(number).message"))
                    .font(.footnote)
                    .foregroundStyle(GoFlyStyle.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
