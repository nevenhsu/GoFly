import AppKit
import SwiftUI
import UniformTypeIdentifiers
import GoFlyMacCore

struct MacSetupPage: View {
    @Bindable var setup: MacSetupModel
    let deviceID: String?
    let vpnInstalled: Bool?
    let vpnConfirmed: Bool
    let checkingDevice: Bool
    let verifyDevice: () -> Void
    @State private var source = MacSetupSource.project
    @State private var teamID = ""
    @State private var artifactPath = ""
    @State private var allowProvisioningUpdates = false
    @State private var validationMessage: String?

    var body: some View {
        StatusCard {
            StatusRow(title: setup.snapshot?.isComplete == true ? (vpnConfirmed ? "Mac 安裝完成" : "確認 LocalDevVPN") : "首次安裝 GoFly",
                      detail: "裝置識別：…\((setup.continuation?.deviceID ?? deviceID ?? "未選擇").suffix(6))")
            Rule()
            if setup.snapshot?.isComplete == true, let result = setup.snapshot {
                StatusRow(title: "GoFly build \(result.appBuild ?? "")", detail: "App 安裝、本次配對資料匯入及裝置支援狀態均已確認。")
                Rule()
                StatusRow(title: "簽名", detail: "Team \(result.teamID ?? "")\n到期：\(result.expiresAt ?? "")")
                Rule()
                StatusRow(title: "LocalDevVPN", detail: vpnConfirmed ? "已確認安裝。開啟 iPhone 內的 LocalDevVPN 連線，再回 GoFly 依正常流程操作。" : vpnInstalled == false ? "尚未安裝。請先在 iPhone 的 App Store 安裝 LocalDevVPN，再重新核對。" : "正在等待原 iPhone 的安裝狀態核對。")
                if !vpnConfirmed {
                    HStack {
                        Link("在 App Store 查看 LocalDevVPN", destination: URL(string: "https://apps.apple.com/app/id6755608044")!)
                        Spacer()
                        PillButton(title: "重新核對", enabled: !checkingDevice, action: verifyDevice)
                    }
                }
                Text("安裝完成不代表 VPN 已連線、GPS 已取得或定位服務已啟動。")
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            } else if setup.hasRecordedTransaction {
                StatusRow(title: "繼續原交易", detail: "使用原本的 iPhone。查詢不會重新安裝；不確定的步驟會保留待確認狀態。")
                progress
            } else {
                form.disabled(setup.isBusy || setup.options != nil)
                if setup.options != nil {
                    Button("修改安裝選項") { setup.resetSelection() }.disabled(setup.isBusy)
                    progress
                }
            }
            if let message = validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.ink)
                    .fixedSize(horizontal: false, vertical: true).goFlyInset()
            }
            if let failure = setup.failure {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 18))
                        .accessibilityHidden(true)
                    StatusRow(title: "尚未完成", detail: failure.detail)
                }.goFlyInset()
            }
            Rule()
            actions
        }
        .accessibilityIdentifier("setup.page")
        .task(id: setup.snapshot?.isComplete == true && !setup.isBusy) {
            if setup.snapshot?.isComplete == true && !setup.isBusy { verifyDevice() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("安裝來源", systemImage: "shippingbox")
                    .font(GoFlyStyle.font(13, bold: true))
                Picker("安裝來源", selection: $source) {
                    Text("從本機 GoFly 專案建置").tag(MacSetupSource.project)
                    Text("選擇已簽署的 GoFly.app").tag(MacSetupSource.signedApp)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .accessibilityLabel("安裝來源")
                if source == .signedApp {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 22)).foregroundStyle(GoFlyStyle.muted)
                            .accessibilityHidden(true)
                        Text(artifactPath.isEmpty ? "尚未選擇 GoFly.app" : artifactPath)
                            .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                            .lineLimit(3).truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("選擇 App…", action: chooseApp)
                            .controlSize(.large)
                    }
                    .goFlyInset()
                }
            }
            Rule()
            VStack(alignment: .leading, spacing: 12) {
                Label("開發簽署", systemImage: "signature")
                    .font(GoFlyStyle.font(13, bold: true))
                VStack(alignment: .leading, spacing: 6) {
                    Text("開發團隊 Team ID")
                        .font(GoFlyStyle.font(12, bold: true))
                    TextField("輸入 10 碼 Team ID", text: $teamID)
                        .goFlyInput().accessibilityIdentifier("setup.team")
                        .accessibilityLabel("開發團隊 Team ID（10 碼）")
                        .frame(maxWidth: 360)
                }
                if source == .project {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("允許 Xcode 連線 Apple 更新開發簽署資料", isOn: $allowProvisioningUpdates)
                            .toggleStyle(.checkbox)
                        Text("只有勾選並開始安裝後，才允許這次建置更新簽署資料。")
                            .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .goFlyInset()
                }
            }
        }
        .foregroundStyle(GoFlyStyle.ink)
    }

    @ViewBuilder private var progress: some View {
        if setup.isBusy, let stage = setup.progressStage {
            StatusRow(title: stage == .complete ? "正在核對最後回報" : stage.title,
                      detail: "已讀取原交易紀錄，等待目前程序結束。")
        }
        if let result = setup.snapshot {
            StatusRow(title: result.stage.title,
                      detail: result.outcome == .unknown ? "結果待確認；請查詢原交易，再依提示繼續。" :
                        result.stage == .preflight && result.outcome == .ready ? "檢查通過。按「開始安裝」才會簽署、配對或安裝。" : "已取得本次交易回報。")
            if setup.hasRecordedTransaction && !result.isComplete && !result.canResume {
                Text("目前只能查詢原交易；未確認的操作不會重新送出。")
                    .foregroundStyle(GoFlyStyle.muted)
            }
        }
        if setup.isBusy {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(setup.cancellationRequested ? "正在取消，等待程序結束…" : "正在處理，請保持原裝置連接…")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack {
            if setup.isBusy {
                Spacer()
                PillButton(title: "取消", enabled: !setup.cancellationRequested) { setup.cancel() }
            } else if setup.hasRecordedTransaction && setup.snapshot?.isComplete != true {
                PillButton(title: "查詢原交易") { setup.status() }
                Spacer()
                if setup.canResume {
                    PillButton(title: "繼續原交易", primary: true) { setup.resume() }
                }
            } else if setup.snapshot?.isComplete != true {
                PillButton(title: "唯讀檢查", enabled: setup.isRestored && deviceID != nil) { preflight() }
                Spacer()
                PillButton(title: "開始安裝", primary: true, enabled: setup.canApply) { setup.apply() }
                    .accessibilityIdentifier("setup.apply")
            }
        }
    }

    private func preflight() {
        validationMessage = nil
        do {
            guard let deviceID else { return }
            if setup.options == nil {
                let options = try MacSetupOptions(source: source, artifactPath: source == .signedApp ? artifactPath : nil,
                                                  teamID: teamID, allowProvisioningUpdates: source == .project && allowProvisioningUpdates)
                try setup.configure(deviceID: deviceID, options: options)
            }
            setup.preflight()
        } catch { validationMessage = "請確認 10 碼 Team ID 與安裝來源。" }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "選擇已簽署的 GoFly.app"
        if panel.runModal() == .OK, let url = panel.url, url.pathExtension == "app" { artifactPath = url.path }
    }
}

private extension MacSetupStage {
    var title: String {
        switch self {
        case .preflight: "安裝前檢查"
        case .artifact: "建置與簽名驗證"
        case .pairing: "準備本次配對"
        case .install: "安裝 GoFly"
        case .support: "準備裝置支援"
        case .handoff: "匯入並核對配對資料"
        case .complete: "Mac 安裝完成"
        }
    }
}

private extension MacSetupFailure {
    var detail: String {
        switch self {
        case .cancelled: "操作已取消。未確認的步驟不會當成已回復；請查詢原交易。"
        case .timeout: "等待逾時。請保持原裝置連接並查詢交易狀態。"
        case .unavailable: "Mac 安裝元件尚未就緒，請確認本機開發環境。"
        case .invalidRequest: "請確認裝置與安裝選項。"
        case .invalidResponse: "無法驗證交易資料；操作已保留，請勿開始另一筆安裝。"
        case .service(let code):
            switch code {
            case "app-already-installed": "已偵測到 GoFly。首次安裝不會覆蓋現有 App。"
            case "app-running": "請在 iPhone 多工畫面將 GoFly 向上滑掉，保持手機解鎖，再按「繼續原交易」。已完成的安裝與配對會保留。"
            case "developer-mode-required": "請在 iPhone 開啟開發者模式，再查詢原交易。"
            case "trust-required": "請解鎖 iPhone 並確認已信任此 Mac。"
            case "device-disconnected": "未連接原本的 USB iPhone。"
            case "signing-required", "signature-invalid": "簽名或描述檔未通過驗證，請檢查開發團隊與 App。"
            case "transaction-unknown", "pairing-unknown", "handoff-unknown", "commit-unknown": "此步驟的結果尚未確認。請查詢或繼續原交易；不會重複安裝。"
            default: "安裝尚未完成（\(code)）。請查詢原交易並依環境或裝置提示處理。"
            }
        }
    }
}
