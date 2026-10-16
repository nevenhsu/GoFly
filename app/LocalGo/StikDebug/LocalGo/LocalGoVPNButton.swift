import SwiftUI

/// Opens the companion app without changing its VPN setting.
struct LocalGoVPNButton: View {
    @Environment(\.openURL) private var openURL
    private let appURL = URL(string: "localdevvpn://")!
    private let storeURL = URL(string: "https://apps.apple.com/tw/app/localdevvpn/id6755608044")!

    var body: some View {
        Button {
            openURL(appURL) { accepted in
                if !accepted { openURL(storeURL) }
            }
        } label: {
            HStack(spacing: 8) {
                Text("開啟 LocalDevVPN")
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
            }
        }
        .buttonStyle(LocalGoButtonStyle(.secondary))
        .accessibilityHint("若尚未安裝，會開啟 App Store")
    }
}
