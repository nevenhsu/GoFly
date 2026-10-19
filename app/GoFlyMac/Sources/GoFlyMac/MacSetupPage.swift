import SwiftUI
import GoFlyMacCore

struct MacSetupPage: View {
    @Bindable var setup: MacSetupModel
    let deviceID: String?
    let detectedTeamID: String?
    let selectedDevice: ConnectedDevice?
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepBar
            StatusCard {
                if setup.snapshot?.isComplete == true {
                    completion
                } else if setup.hasRecordedTransaction {
                    continuation
                } else {
                    confirmation
                }
                if let message = validationMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.ink)
                        .fixedSize(horizontal: false, vertical: true).goFlyInset()
                }
                if let failure = setup.failure, setup.snapshot?.isComplete != true {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 18))
                            .accessibilityHidden(true)
                        StatusRow(title: "尚未完成", detail: failure.detail)
                    }.goFlyInset()
                }
                Rule()
                actions
            }
        }
        .accessibilityIdentifier("setup.page")
        .task(id: preflightKey) { await autoPreflight() }
    }

    private var stepBar: some View {
        HStack(spacing: 10) {
            ForEach(1...4, id: \.self) { step in
                HStack(spacing: 8) {
                    Text("\(step)")
                        .font(GoFlyStyle.font(11, bold: true))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(step <= currentStep ? GoFlyStyle.surface : GoFlyStyle.muted)
                        .background(step <= currentStep ? GoFlyStyle.ink : GoFlyStyle.secondarySurface, in: Circle())
                    Text(stepTitle(step)).font(GoFlyStyle.font(12, bold: step == currentStep))
                        .foregroundStyle(step == currentStep ? GoFlyStyle.ink : GoFlyStyle.muted)
                }
                if step != 4 {
                    Rectangle().fill(GoFlyStyle.line).frame(height: 0.75).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityIdentifier("install-steps")
    }

    private var currentStep: Int {
        if setup.snapshot?.isComplete == true { return 4 }
        if setup.isBusy, setup.progressStage != nil { return 3 }
        return 2
    }

    private func stepTitle(_ step: Int) -> String {
        switch step {
        case 1: "選擇 iPhone"
        case 2: "確認"
        case 3: "安裝進度"
        default: "完成"
        }
    }

    @ViewBuilder private var confirmation: some View {
        StatusRow(title: "確認安裝", detail: "確認這部 iPhone 後再開始安裝。")
        Rule()
        HStack {
            Text("裝置").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            Spacer()
            Text(selectedDevice?.displayName ?? "原 iPhone").font(GoFlyStyle.font(14, bold: true))
        }
        HStack {
            Text("iOS 版本").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            Spacer()
            Text(selectedDevice?.osVersion.map { "iOS \($0)" } ?? "待確認").font(GoFlyStyle.font(14, bold: true))
        }
        HStack {
            Text("Team").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            Spacer()
            Text(detectedTeamID ?? "尚未選擇 Team").font(GoFlyStyle.font(14, bold: true))
        }
    }

    @ViewBuilder private var continuation: some View {
        StatusRow(title: "繼續上次安裝",
                  detail: "使用原本的 iPhone。查詢不會重新安裝；不確定的步驟會保留待確認狀態。")
        progress
    }

    @ViewBuilder private var completion: some View {
        StatusRow(title: "Mac 安裝完成", detail: "手機上的資料和設定已保留。")
        Rule()
        StatusRow(title: "簽名到期日", detail: expiryText)
        Rule()
        StatusRow(title: "手機上的下一步", detail: "1. 開啟 LocalDevVPN\n2. 開啟 GoFly")
    }

    private var expiryText: String {
        guard let raw = setup.snapshot?.expiresAt else { return "待確認" }
        guard let date = ISO8601DateFormatter().date(from: raw) else { return raw }
        return date.formatted(Date.FormatStyle(date: .numeric, time: .shortened)
            .locale(Locale(identifier: "zh_TW")))
    }

    @ViewBuilder private var progress: some View {
        if setup.isBusy {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(setup.cancellationRequested ? "正在取消，等待程序結束…" :
                        setup.progressStage.map { $0 == .complete ? "正在核對最後回報…" : "\($0.title)…" } ??
                        "正在確認裝置與簽名，請保持 USB 連接…")
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
            } else if setup.hasRecordedTransaction {
                PillButton(title: "查詢上次安裝") { setup.status() }
                Spacer()
                if setup.canResume {
                    PillButton(title: "繼續上次安裝", primary: true) { setup.resume() }
                }
            } else if setup.canApply {
                Spacer()
                PillButton(title: "開始安裝", primary: true) { setup.apply() }
                    .accessibilityIdentifier("setup.apply")
            } else {
                Spacer()
                PillButton(title: "重新檢查", primary: true) { retryPreflight() }
            }
        }
    }

    private var preflightKey: String {
        "\(setup.isRestored)-\(setup.isBusy)-\(setup.hasRecordedTransaction)-\(setup.snapshot?.stage.rawValue ?? "none")-\(deviceID ?? "")-\(detectedTeamID ?? "")"
    }

    private func autoPreflight() async {
        guard setup.isRestored, !setup.isBusy, !setup.hasRecordedTransaction,
              setup.snapshot == nil, let deviceID, let teamID = detectedTeamID else { return }
        do {
            if setup.options == nil {
                try setup.configure(deviceID: deviceID,
                                    options: try MacSetupOptions(teamID: teamID))
            }
            setup.preflight()
        } catch {
            validationMessage = "無法建立安裝選項，請確認 Mac 環境的 Team。"
        }
    }

    private func retryPreflight() {
        validationMessage = nil
        do {
            guard let deviceID, let teamID = detectedTeamID else {
                validationMessage = "尚未選擇 Team，請回到 Mac 環境設定。"
                return
            }
            if setup.options == nil {
                try setup.configure(deviceID: deviceID,
                                    options: try MacSetupOptions(teamID: teamID))
            }
            setup.preflight()
        } catch {
            validationMessage = "無法建立安裝選項，請確認 Mac 環境的 Team。"
        }
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
        case .cancelled: "操作已取消。未確認的步驟不會當成已回復；請查詢上次安裝。"
        case .timeout: "等待逾時。請保持原裝置連接並查詢交易狀態。"
        case .unavailable: "Mac 安裝元件尚未就緒，請確認本機開發環境。"
        case .invalidRequest: "請確認裝置與安裝選項。"
        case .invalidResponse: "無法驗證交易資料；操作已保留，請勿開始另一筆安裝。"
        case .service(let code):
            switch code {
            case "app-already-installed": "已偵測到 GoFly。首次安裝不會覆蓋現有 App。"
            case "app-running": "請在 iPhone 多工畫面將 GoFly 向上滑掉，保持手機解鎖，再按「繼續上次安裝」。已完成的安裝與配對會保留。"
            case "developer-mode-required": "請在 iPhone 開啟開發者模式，再查詢上次安裝。"
            case "trust-required": "請解鎖 iPhone 並確認已信任此 Mac。"
            case "device-disconnected": "未連接原本的 USB iPhone。"
            case "signing-required", "signature-invalid": "簽名或描述檔未通過驗證，請檢查開發團隊與 App。"
            case "transaction-unknown", "pairing-unknown", "handoff-unknown", "commit-unknown": "此步驟的結果尚未確認。請查詢或繼續上次安裝；不會重複安裝。"
            default: "安裝尚未完成（\(code)）。請查詢上次安裝並依環境或裝置提示處理。"
            }
        }
    }
}
