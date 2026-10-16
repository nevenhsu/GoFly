import SwiftUI
import GoFlyMacCore

struct MacRootView: View {
    @Bindable var model: MacAppModel
    var body: some View {
        VStack(spacing: 0) {
            if model.isPreview {
                HStack(spacing: 16) {
                    Text("介面預覽").font(GoFlyStyle.font(12, bold: true))
                    Text("示意資料，不會操作手機").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    Spacer()
                    Picker("預覽情境", selection: $model.previewScenario) {
                        ForEach(PreviewScenario.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 230).onChange(of: model.previewScenario) { model.applyScenario() }
                }.padding(.horizontal, 24).frame(height: 38).fixedSize(horizontal: false, vertical: true)
                    .background(Color(white: 0.94))
                Rule()
            }
            if model.page == .home { home }
            else {
                HStack(spacing: 0) {
                    sidebar
                    VStack(alignment: .leading, spacing: 0) {
                        header.padding(.bottom, 36)
                        if let failure = model.failure { errorCard(failure) }
                        else { pageContent }
                        if let message = model.previewMessage {
                            Text(message).font(GoFlyStyle.font(13, bold: true)).padding(.top, 12)
                                .accessibilityIdentifier("preview-result")
                        }
                        footer.padding(.top, 28)
                    }
                    .padding(.horizontal, 56).padding(.top, 26).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(.white).foregroundStyle(.black)
        .font(GoFlyStyle.font(14))
    }

    private var home: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 108)
            DesignAsset("WingedArrow", width: 96)
            Text("GoFly").font(GoFlyStyle.font(36, bold: true)).padding(.top, 12)
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                else if model.environment?.ready == true { DesignAsset("EnvironmentPassed", width: 24) }
                Text(model.busy ? "正在檢查 Mac 環境…" : model.environment?.ready == true ? "Mac 環境已就緒" : "Mac 環境尚未就緒")
                    .font(GoFlyStyle.font(14)).foregroundStyle(Color(white: 0.4))
            }.padding(.top, 16).padding(.bottom, 24)
            PillButton(title: "首次安裝", primary: true, width: 400, height: 56, enabled: model.ready) { model.openDevices(firstInstall: true) }
                .accessibilityIdentifier("first-install")
            PillButton(title: "裝置管理", width: 400, height: 56, enabled: model.ready) { model.openDevices(firstInstall: false) }
                .padding(.top, 20).accessibilityIdentifier("manage-devices")
            Button("查看 Mac 環境") { model.navigate(.environment) }
                .buttonStyle(.plain).font(GoFlyStyle.font(12)).underline().padding(.top, 22).disabled(model.busy)
            if let failure = model.failure {
                Text(failure.title).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted).padding(.top, 12)
            }
            Spacer(minLength: 60)
            HStack {
                Text(model.isPreview ? "GoFly Mac · 介面預覽" : "GoFly Mac · 唯讀檢查，不安裝手機 App")
                Spacer()
                Button(model.isPreview ? "返回唯讀檢查" : "預覽操作流程") { model.switchMode(preview: !model.isPreview) }
                    .buttonStyle(.plain).underline().accessibilityIdentifier("switch-mode")
            }.font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted).padding(30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DesignAsset("WingedArrow", width: 42)
                Text("GoFly").font(GoFlyStyle.font(24, bold: true))
            }.padding(.horizontal, 24).padding(.top, 24)
            if model.selected != nil {
                PillButton(title: "切換裝置", width: 176, height: 28, enabled: !model.busy) { model.openDevices(firstInstall: model.firstInstall) }
                    .padding(.horizontal, 24).padding(.top, 4)
            }
            Text(model.page == .environment ? "開始前準備" : model.firstInstall ? "首次安裝" : "裝置管理")
                .font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.muted)
                .padding(.horizontal, 24).padding(.top, model.selected == nil ? 32 : 12).padding(.bottom, 20)
            ForEach(Array(sidebarItems.enumerated()), id: \.offset) { index, item in
                Button { model.navigate(item.1) } label: {
                    HStack(spacing: 12) {
                        if model.page != .environment {
                            Text("\(index + 1)").font(GoFlyStyle.font(12, bold: true))
                                .frame(width: 20, height: 20).overlay(Circle().strokeBorder(selectedSidebar == item.1 ? .white : GoFlyStyle.line))
                        }
                        Text(item.0).font(GoFlyStyle.font(14, bold: true)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(height: 46)
                    .foregroundStyle(selectedSidebar == item.1 ? .white : .black)
                    .background(selectedSidebar == item.1 ? Color.black : .clear, in: Capsule())
                    .contentShape(Capsule())
                }.buttonStyle(.plain).disabled(model.busy).padding(.horizontal, 12).padding(.bottom, 12)
            }
            Spacer()
            Text(model.isPreview ? "操作流程使用示意資料\n不會安裝或變更手機" : "目前版本僅提供唯讀檢查\n安裝與修復操作尚未開放")
                .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted).lineSpacing(4)
                .padding(.horizontal, 24).padding(.bottom, 40)
        }.frame(width: 224).frame(maxHeight: .infinity).background(GoFlyStyle.sidebar)
    }

    private var sidebarItems: [(String, MacPage)] {
        if model.page == .environment { return [("Mac 環境", .environment)] }
        if model.firstInstall { return [("連接 iPhone", .devices), ("安裝 GoFly", .install), ("LocalDevVPN", .vpn), ("手機內完成設定", .handoff)] }
        return [(model.selected?.displayName ?? "我的 iPhone", .device), ("簽名與重新簽名", .signing), ("連接與修復", .repair)]
    }
    private var selectedSidebar: MacPage {
        switch model.page {
        case .reinstall, .backups: .signing
        case .channel: .repair
        default: model.page
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.page == .environment ? "GoFly  /  Mac 環境" : (model.firstInstall ? "首次安裝" : model.selected?.displayName ?? "裝置管理") + "  /  " + pageTitle)
                    .font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.muted)
                Spacer()
                PillButton(title: "首頁", width: 86, height: 36, enabled: !model.busy) { model.navigate(.home) }
            }
            Text(model.failure?.title ?? pageTitle).font(GoFlyStyle.font(30, bold: true)).padding(.top, 6)
            Text(model.failure?.detail ?? pageSubtitle).font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorCard(_ error: CheckFailure) -> some View {
        StatusCard {
            StatusRow(title: error.title, detail: error.detail)
            Rule()
            StatusRow(title: "裝置狀態待確認", detail: "檢查失敗後不沿用先前結果。完成手機上的必要設定後，請手動重新檢查。")
            Rule()
            StatusRow(title: model.isPreview ? "目前是介面預覽" : "目前是唯讀檢查", detail: "沒有安裝 App、簽署、建立配對或變更手機資料。")
        }
    }

    private var footer: some View {
        VStack(spacing: 20) {
            Rule()
            HStack(spacing: 24) {
                if model.busy {
                    ProgressView().controlSize(.small)
                    Text("正在檢查，請保持手機連接…").font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    Spacer()
                    PillButton(title: "取消檢查") { model.cancel() }
                } else { pageActions }
            }
            HStack {
                Text(model.isPreview ? "GoFly Mac · 介面預覽，操作不會套用至裝置" : "GoFly Mac · 唯讀檢查")
                Spacer()
                if !model.isPreview {
                    Button("預覽此流程") { model.switchMode(preview: true) }
                        .buttonStyle(.plain).underline()
                }
            }.font(GoFlyStyle.font(11)).foregroundStyle(Color(white: 0.55))
        }
    }

    private var pageTitle: String {
        switch model.page {
        case .home: "GoFly"
        case .environment: model.environment?.ready == true ? "Mac 環境已就緒" : "Mac 環境設定"
        case .devices: "選擇要連接的裝置"
        case .device: model.selected?.displayName ?? "我的 iPhone"
        case .signing: "簽名與重新簽名"
        case .repair: "連接與修復"
        case .channel: "在 iPhone 修復本機通道"
        case .install: "確認 GoFly 簽名與安裝"
        case .vpn: "在 iPhone 安裝 LocalDevVPN"
        case .handoff: "在 iPhone 完成最後設定"
        case .reinstall: "選擇重新安裝後保留的資料"
        case .backups: "備份管理"
        }
    }
    private var pageSubtitle: String {
        switch model.page {
        case .home: ""
        case .environment: "背景檢測通過後，開放首次安裝介面與裝置管理檢查。"
        case .devices: model.firstInstall ? "只列出 USB 連接的裝置，請選擇要檢查的 iPhone。" : "列出目前可偵測的 USB 與 Wi-Fi 裝置；相同裝置優先顯示 USB。"
        case .device: "查看這部 iPhone 的裝置、安裝與連接狀態。"
        case .signing: "簽名狀態須有可核對的實際證據；未取得時保留為待確認。"
        case .repair: "查看這部 iPhone 的連接狀態與需要手動完成的設定。"
        case .channel: "裝置連接與配對正常時，依手機提示確認 LocalDevVPN 與服務。"
        case .install: model.isPreview ? "使用 Xcode 中已設定的開發團隊（介面預覽）。" : "本版僅檢查，不會簽名或安裝手機 App。"
        case .vpn: "GoFly 安裝完成後，接著在手機 App Store 安裝 LocalDevVPN。"
        case .handoff: "Mac 安裝與配對資料匯入完成後，才可拔除 USB，接著在手機操作。"
        case .reinstall: "備份完成 → 重新安裝 → 自動匯入；目前為介面預覽。"
        case .backups: "成功匯入後保留七天；未完成匯入的備份不自動刪除。"
        }
    }
}
