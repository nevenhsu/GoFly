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
                        .font(GoFlyFont.title)
                        .accessibilityAddTraits(.isHeader)
                    Text(goFlyString("onboarding.vpn.help.intro"))
                        .font(GoFlyFont.footnote)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 0) {
                    helpStep(1)
                    Divider().padding(.leading, 50)
                    helpStep(2)
                    Divider().padding(.leading, 50)
                    helpStep(3)
                    Divider().padding(.leading, 50)
                    helpStep(4)
                }
                .background(GoFlyStyle.secondarySurface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(goFlyString("onboarding.vpn.help.troubleshooting"))
                        .font(GoFlyFont.footnoteEmphasis)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goFlyString("onboarding.vpn.help.reconnectTitle"))
                                .font(GoFlyFont.subheadlineEmphasis)
                                .foregroundStyle(GoFlyTextColor.primary)
                            Text(goFlyString("onboarding.vpn.help.reconnect"))
                                .font(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        Divider().padding(.leading, 14)

                        Button(action: openSystemSettings) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(goFlyString("onboarding.vpn.help.permissionTitle"))
                                        .font(GoFlyFont.subheadlineEmphasis)
                                        .foregroundStyle(GoFlyTextColor.primary)
                                    Text(goFlyString("onboarding.vpn.help.permission"))
                                        .font(GoFlyFont.footnote)
                                        .foregroundStyle(GoFlyTextColor.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: GoFlySymbols.disclosure)
                                    .font(GoFlyFont.captionEmphasis)
                                    .foregroundStyle(GoFlyTextColor.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.vpn.help.openSettings")
                    }
                    .background(GoFlyStyle.secondarySurface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if externalOpenFailed {
                    errorMessage(externalOpenFailureKey)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(GoFlyStyle.surface)
        .navigationTitle(goFlyString("onboarding.vpn.help"))
        .navigationBarTitleDisplayMode(.inline)
        .goFlyNativeBackTitle()
        .accessibilityIdentifier("vpn.help.page")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { dismiss() } label: {
                Text(goFlyString("onboarding.vpn.help.returnAndCheck"))
            }
            .buttonStyle(GoFlyActionStyle(primary: true))
            .accessibilityIdentifier("onboarding.vpn.help.openVPN")
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(GoFlyStyle.surface)
        }
    }

    private func helpStep(_ number: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(number)")
                .font(GoFlyFont.captionEmphasis)
                .foregroundStyle(GoFlyTextColor.inverse)
                .frame(width: 24, height: 24)
                .background(GoFlyStyle.primary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goFlyString("onboarding.vpn.help.step\(number).title"))
                    .font(GoFlyFont.subheadlineEmphasis)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .accessibilityIdentifier("onboarding.vpn.help.step\(number)")
                Text(goFlyString("onboarding.vpn.help.step\(number).message"))
                    .font(GoFlyFont.footnote)
                    .foregroundStyle(GoFlyTextColor.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 62)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
