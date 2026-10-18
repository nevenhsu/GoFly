import AppKit
import GoFlyMacCore
import SwiftUI
import UniformTypeIdentifiers

struct MacManagementPage: View {
    @Bindable var management: MacManagementModel
    let kind: MacManagementKind
    let device: ConnectedDevice?
    let selection: MacManagementSelection?
    let defaultTeam: String?
    let finish: () async -> Void
    let cancel: () -> Void
    @State private var source = MacSetupSource.project
    @State private var teamID = ""
    @State private var artifactPath = ""
    @State private var allowProvisioningUpdates = false
    @State private var resumeTransport: MacManagementTransport?
    @State private var validationMessage: String?
    @State private var manualSelection: MacManagementSelection?

    private var released: Bool {
        management.snapshot?.stage == .release && management.snapshot?.outcome == .confirmed
    }

    var body: some View {
        StatusCard {
                StatusRow(title: title, detail: deviceDescription)
                Rule()
                if management.hasRecordedTransaction {
                    Text("接續同一部 iPhone 與原操作。已提交但尚未確認的更新或配對不會自動重送。")
                        .foregroundStyle(GoFlyStyle.muted)
                    if let identity = management.continuation {
                        StatusRow(title: "本次連線", detail: "\(transportName(identity.currentTransport)) · 第 \(identity.connectionRevision + 1) 次連線紀錄")
                    }
                } else {
                    form.disabled(management.isBusy || management.continuation != nil)
                    if management.continuation != nil {
                        Button("修改本次選項") { management.resetSelection() }.disabled(management.isBusy)
                    }
                }
                if let snapshot = management.snapshot {
                    Rule()
                    StatusRow(title: snapshot.stage.title, detail: detail(snapshot))
                    if let expiry = snapshot.expiresAt {
                        StatusRow(title: "已核對的簽名期限", detail: expiry)
                    }
                }
                if let failure = management.failure {
                    Rule()
                    StatusRow(title: failure.title, detail: failure.detail)
                }
                if let validationMessage { Text(validationMessage).foregroundStyle(GoFlyStyle.muted) }
                if management.isBusy {
                    HStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text(management.cancellationRequested ? "正在結束 Mac 程序，等待實際返回…" :
                                management.progressStage?.title ?? "正在核對原操作…")
                    }.font(GoFlyStyle.font(13))
                }
                Rule()
                actions
        }
        .task { if teamID.isEmpty { teamID = defaultTeam ?? "" } }
        .accessibilityIdentifier(kind == .renew ? "management.renew" : "management.repair")
    }

    private var title: String {
        if management.snapshot?.isComplete == true { return kind == .renew ? "重新簽名完成" : "裝置配對修復完成" }
        if released { return "本次操作已取消" }
        if management.hasRecordedTransaction { return "接續原操作" }
        return kind == .renew ? "更新 GoFly 簽名並保留資料" : "修復這部 iPhone 的配對"
    }

    private var deviceDescription: String {
        let identity = management.continuation
        let suffix = (identity?.deviceID ?? device?.id ?? "未選擇").suffix(6)
        let transport = identity?.currentTransport ?? selection?.transport
        return "iPhone · …\(suffix)" + (transport.map { " · \(transportName($0))" } ?? "")
    }

    @ViewBuilder private var form: some View {
        if kind == .renew {
            VStack(alignment: .leading, spacing: 20) {
                Text("沿用相同開發團隊更新 App，保留目前地點、路線、草稿與設定。請先結束 iPhone 上的編輯與移動操作。")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    Label("簽名來源", systemImage: "shippingbox")
                        .font(GoFlyStyle.font(13, bold: true))
                    Picker("簽名來源", selection: $source) {
                        Text("從本機 GoFly 專案建置").tag(MacSetupSource.project)
                        Text("選擇已簽署的 GoFly.app").tag(MacSetupSource.signedApp)
                    }
                    .pickerStyle(.radioGroup).labelsHidden()
                    .accessibilityLabel("簽名來源")
                    if source == .signedApp {
                        HStack(spacing: 12) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 22)).foregroundStyle(GoFlyStyle.muted)
                                .accessibilityHidden(true)
                            Text(artifactPath.isEmpty ? "尚未選擇 GoFly.app" : artifactPath)
                                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                                .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("選擇 App…", action: chooseApp).controlSize(.large)
                        }.goFlyInset()
                    }
                }
                Rule()
                VStack(alignment: .leading, spacing: 12) {
                    Label("開發簽署", systemImage: "signature")
                        .font(GoFlyStyle.font(13, bold: true))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("相同開發團隊 Team ID").font(GoFlyStyle.font(12, bold: true))
                        TextField("輸入 10 碼 Team ID", text: $teamID)
                            .goFlyInput()
                            .accessibilityLabel("相同開發團隊 Team ID（10 碼）")
                            .frame(maxWidth: 360)
                    }
                    if source == .project {
                        Toggle("允許 Xcode 連線 Apple 更新本次開發簽署資料", isOn: $allowProvisioningUpdates)
                            .toggleStyle(.checkbox).goFlyInset()
                    }
                }
            }.foregroundStyle(GoFlyStyle.ink)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("裝置配對", systemImage: "iphone")
                    .font(GoFlyStyle.font(13, bold: true)).foregroundStyle(GoFlyStyle.ink)
                Text("重新準備裝置配對與必要支援，並核對手機匯入回報。請保持原 iPhone 解鎖；App 與目前資料會保留。")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("若 GoFly 正在執行，請先停止移動並完成清除、結束編輯，再停留於地圖等待準備。")
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }.goFlyInset()
        }
    }

    @ViewBuilder private var actions: some View {
        if management.isBusy {
            HStack {
                Spacer()
                PillButton(title: "中止 Mac 程序", enabled: !management.cancellationRequested, action: cancel)
            }
        } else if management.hasRecordedTransaction {
            if management.snapshot?.isComplete == true || released {
                HStack { Spacer(); PillButton(title: "完成", primary: true) { Task { await finish() } } }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("接續使用的連線", selection: $resumeTransport) {
                        Text("沿用目前連線").tag(Optional<MacManagementTransport>.none)
                        Text("USB").tag(Optional(MacManagementTransport.usb))
                        Text("Wi-Fi").tag(Optional(MacManagementTransport.network))
                    }.frame(maxWidth: 320)
                    Text("變更連線前會先核對原操作。若舊操作結果仍未知，會保留原連線紀錄並等待確認。")
                        .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    HStack {
                        PillButton(title: "查詢原操作", width: 144, enabled: management.canQuery) { management.query() }
                        if management.canRelease { PillButton(title: "取消本次操作", width: 144) { management.release() } }
                        Spacer()
                        PillButton(title: "接續原操作", primary: true, width: 176, enabled: management.canResume) {
                            management.resume(using: resumeTransport.map { MacManagementSelection(selectionID: UUID(), transport: $0) })
                        }
                    }
                }
            }
        } else {
            HStack {
                PillButton(title: "唯讀檢查", enabled: management.isRestored && device != nil) { preflight() }
                Spacer()
                PillButton(title: kind == .renew ? "重新簽名" : "開始修復", primary: true, enabled: management.canApply) {
                    management.apply()
                }
            }
        }
    }

    private func preflight() {
        validationMessage = nil
        do {
            guard let device else { return }
            if management.continuation == nil {
                // A new manual action can follow a completed operation on
                // the same phone without generating another automatic event.
                let selected = selection ?? manualSelection ?? MacManagementSelection(selectionID: UUID(),
                    transport: device.transport == .usb ? .usb : .network)
                manualSelection = selected
                let options = kind == .renew ? try MacManagementOptions(source: source,
                    artifactPath: source == .signedApp ? artifactPath : nil, teamID: teamID,
                    allowProvisioningUpdates: source == .project && allowProvisioningUpdates) : nil
                try management.configure(deviceID: device.id, kind: kind, selection: selected, options: options)
            }
            management.preflight()
        } catch { validationMessage = "請確認原 iPhone、10 碼 Team ID 與簽名來源。" }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { artifactPath = url.path }
    }

    private func transportName(_ transport: MacManagementTransport) -> String { transport == .usb ? "USB" : "Wi-Fi" }
    private func detail(_ payload: MacManagementPayload) -> String {
        if payload.isComplete { return "App 身分、配對匯入、裝置支援與資料接續回報均已核對。回 iPhone 依正常提示繼續。" }
        if released { return "本次操作已結束，已保留原 App 資料與設定。" }
        if payload.outcome == .unknown { return "操作結果尚未確認。保持原 iPhone 連線，手動查詢或接續。" }
        if payload.stage == .preflight && payload.outcome == .ready { return "檢查通過，可以開始本次操作。" }
        return "本次操作尚未完成，已完成的進度會保留。"
    }
}

private extension MacManagementStage {
    var title: String {
        switch self {
        case .preflight: "檢查裝置與原 App"
        case .artifact: "建置與驗證簽名"
        case .source: "等待原 App 準備"
        case .seal: "確認原資料交接"
        case .update: "更新 GoFly"
        case .pairing: "準備裝置配對"
        case .support: "準備裝置支援"
        case .adoption: "核對 App 與資料接續"
        case .complete: "全部條件已確認"
        case .release: "取消本次操作"
        }
    }
}
