import AppKit
import GoFlyMacCore
import SwiftUI
import UniformTypeIdentifiers

struct MacReinstallPage: View {
    @Bindable var reinstall: MacReinstallModel
    let device: ConnectedDevice?
    let finish: () async -> Void
    @State private var source = MacSetupSource.project
    @State private var teamID = ""
    @State private var artifactPath = ""
    @State private var allowProvisioningUpdates = false
    @State private var favorites = true
    @State private var routes = true
    @State private var settings = true
    @State private var validationMessage: String?

    var body: some View {
        StatusCard {
            StatusRow(title: title, detail: "原裝置：…\((reinstall.continuation?.deviceID ?? device?.id ?? "未選擇").suffix(6))")
            Rule()
            if reinstall.hasRecordedTransaction {
                recordedTransaction
            } else {
                form.disabled(reinstall.isBusy || reinstall.options != nil)
                if reinstall.options != nil {
                    Button("修改保留資料與安裝選項") { reinstall.resetSelection() }.disabled(reinstall.isBusy)
                }
            }
            if let result = reinstall.snapshot {
                StatusRow(title: result.stage.title, detail: result.detail)
                ForEach(result.categories, id: \.category) { category in
                    StatusRow(title: category.category.title, detail: category.state.title)
                }
                if let counts = result.counts {
                    Text("最愛 \(counts.favorites) · 匯入路線 \(counts.importedRoutes) · 最愛路線 \(counts.favoriteRoutes) · 草稿節點 \(counts.draftNodes) · GPX 點 \(counts.gpxPoints)")
                        .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                }
            }
            if let failure = reinstall.failure {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 18))
                        .accessibilityHidden(true)
                    StatusRow(title: "尚未完成", detail: failure.detail)
                }.goFlyInset()
            }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.circle")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.ink)
                    .fixedSize(horizontal: false, vertical: true).goFlyInset()
            }
            if reinstall.isBusy {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(reinstall.cancellationRequested ? "正在中止程序，等待實際返回…" : reinstall.progressStage?.title ?? "正在處理原交易…")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rule()
            actions
        }
        .accessibilityIdentifier("reinstall.page")
    }

    private var title: String {
        if reinstall.snapshot?.isComplete == true { return "重新安裝與資料匯入完成" }
        if reinstall.snapshot?.isAbandoned == true { return "本次重新安裝已放棄" }
        return reinstall.hasRecordedTransaction ? "繼續原重新安裝交易" : "選擇重新安裝後要保留的資料"
    }

    private var recordedTransaction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("保留項目：\(selectedDescription)")
            Text("使用原本的 iPhone。查詢只讀取交易紀錄；未確認的安裝不會自動重試。")
                .foregroundStyle(GoFlyStyle.muted)
            if reinstall.snapshot?.isComplete == true {
                Text("安裝、配對匯入、必要裝置支援及所有所選資料回報均已確認。請回 iPhone 繼續正常流程。")
            } else if reinstall.snapshot?.isAbandoned == true {
                Text("已收到原 App 的釋放回報。這筆交易不會再移除或安裝 App。")
            } else {
                Text("放棄只限移除意圖提交前，且需等待手機回報。中止 Mac 程序不等於放棄交易或恢復原 App。")
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            }
        }
    }

    private var selectedDescription: String {
        let categories = reinstall.continuation?.categories ?? []
        return categories.isEmpty ? "全部不保留（全新安裝）" : categories.map(\.title).joined(separator: "、")
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("保留資料", systemImage: "square.stack.3d.up")
                    .font(GoFlyStyle.font(13, bold: true))
                Text("只保留已儲存、已接受的資料。請先在 iPhone 停止移動並確認裝置清除完成，關閉未結束的編輯，再開始。")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    preservationToggle("最愛地點與標籤", symbol: "star", selection: $favorites)
                    preservationToggle("路線、GPX、目前已接受的草稿與路線速度", symbol: "point.topleft.down.to.point.bottomright.curvepath", selection: $routes)
                    preservationToggle("語言、外觀、模式與操作設定", symbol: "slider.horizontal.3", selection: $settings)
                }.goFlyInset()
                Label(favorites || routes || settings ? "未勾選的資料會隨重新安裝清除。移動任務與目前位置不會還原。" : "全部不選代表全新安裝；原 App 的所有使用者資料會清除。", systemImage: "info.circle")
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rule()
            VStack(alignment: .leading, spacing: 12) {
                Label("安裝來源", systemImage: "shippingbox")
                    .font(GoFlyStyle.font(13, bold: true))
                Picker("安裝來源", selection: $source) {
                    Text("從本機 GoFly 專案建置").tag(MacSetupSource.project)
                    Text("選擇已簽署的 GoFly.app").tag(MacSetupSource.signedApp)
                }
                .pickerStyle(.radioGroup).labelsHidden()
                .accessibilityLabel("安裝來源")
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
                    Text("開發團隊 Team ID").font(GoFlyStyle.font(12, bold: true))
                    TextField("輸入 10 碼 Team ID", text: $teamID)
                        .goFlyInput().accessibilityIdentifier("reinstall.team")
                        .accessibilityLabel("開發團隊 Team ID（10 碼）")
                        .frame(maxWidth: 360)
                }
                if source == .project {
                    Toggle("允許 Xcode 連線 Apple 更新本次開發簽署資料", isOn: $allowProvisioningUpdates)
                        .toggleStyle(.checkbox).goFlyInset()
                }
            }
            Text("本流程使用 USB，先在 Mac 完整驗證備份，再同機移除、安裝及匯入。舊版 App 若沒有資料接收功能，會保留原 App 並提示需要更新。")
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GoFlyStyle.ink)
    }

    private func preservationToggle(_ title: String, symbol: String, selection: Binding<Bool>) -> some View {
        Toggle(isOn: selection) {
            Label(title, systemImage: symbol)
                .font(GoFlyStyle.font(13))
                .fixedSize(horizontal: false, vertical: true)
        }.toggleStyle(.checkbox)
    }

    @ViewBuilder private var actions: some View {
        HStack {
            if reinstall.isBusy {
                Spacer()
                PillButton(title: "中止 Mac 程序", enabled: !reinstall.cancellationRequested) { reinstall.cancel() }
            } else if reinstall.hasRecordedTransaction {
                if reinstall.snapshot?.isComplete == true || reinstall.snapshot?.isAbandoned == true {
                    Spacer()
                    PillButton(title: "完成", primary: true) { Task { await finish() } }
                } else {
                    PillButton(title: "查詢原交易", width: 144, enabled: reinstall.canStatus) { reinstall.status() }
                    if reinstall.canAbandon { PillButton(title: "放棄本次重裝", width: 160) { reinstall.abandon() } }
                    Spacer()
                    if reinstall.canResume { PillButton(title: "繼續原交易", primary: true, width: 160) { reinstall.resume() } }
                }
            } else {
                PillButton(title: "唯讀檢查", enabled: reinstall.isRestored && device?.transport == .usb) { preflight() }
                Spacer()
                PillButton(title: "備份並重新安裝", primary: true, enabled: reinstall.canApply) { reinstall.apply() }
                    .accessibilityIdentifier("reinstall.apply")
            }
        }
    }

    private func preflight() {
        validationMessage = nil
        do {
            guard let device, device.transport == .usb else { return }
            if reinstall.options == nil {
                let selected: [MacReinstallCategory] = [favorites ? .favorites : nil, routes ? .routes : nil, settings ? .settings : nil].compactMap { $0 }
                let options = try MacReinstallOptions(source: source, artifactPath: source == .signedApp ? artifactPath : nil,
                    teamID: teamID, allowProvisioningUpdates: source == .project && allowProvisioningUpdates, categories: selected)
                try reinstall.configure(deviceID: device.id.lowercased(), options: options)
            }
            reinstall.preflight()
        } catch { validationMessage = "請確認 USB 裝置、10 碼 Team ID 與安裝來源。" }
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

private extension MacReinstallCategory {
    var title: String { switch self { case .favorites: "最愛地點與標籤"; case .routes: "路線"; case .settings: "設定" } }
}
private extension MacReinstallCategoryState {
    var title: String { switch self { case .waiting: "等待匯入"; case .validating: "正在驗證"; case .committed: "已提交並取得回報"; case .failed: "未完成，保留原交易" } }
}
private extension MacReinstallStage {
    var title: String {
        switch self {
        case .preflight: "重新安裝前檢查"
        case .artifact: "建置與簽名驗證"
        case .source: "等待原 App 準備資料"
        case .backup: "備份與驗證資料"
        case .seal: "封存原 App 資料"
        case .uninstall: "移除原 App"
        case .install: "安裝 GoFly"
        case .support: "準備裝置支援"
        case .restore: "匯入並核對所選資料"
        case .complete: "重新安裝與資料匯入完成"
        case .abandon: "放棄本次重新安裝"
        }
    }
}
private extension MacReinstallPayload {
    var detail: String {
        if isComplete { return "所有安裝與資料條件均已確認。" }
        if isAbandoned { return "原 App 已確認釋放，不會再執行本次安裝。" }
        if outcome == .unknown { return "結果尚未確認；請查詢原交易。未確認的安裝不會自動重試。" }
        if stage == .preflight && outcome == .ready { return "檢查通過。按「備份並重新安裝」才會開始寫入或移除。" }
        return "已取得原交易回報，尚未完成全部條件。"
    }
}
private extension MacReinstallFailure {
    var detail: String {
        switch self {
        case .cancelled: "Mac 程序已中止。請查詢原交易；取消程序不代表手機已解除鎖定。"
        case .timeout: "等待逾時。請保持原裝置連接，查詢或繼續原交易。"
        case .unavailable: "重新安裝元件尚未就緒，請確認 Mac 環境。"
        case .invalidRequest: "請確認原裝置與安裝選項。"
        case .invalidResponse: "無法驗證交易資料，保留操作鎖定。可查詢時請先查詢原交易；讀取仍失敗請重新開啟 Mac App。"
        case .service(let code):
            switch code {
            case "app-running": "請在 iPhone 多工畫面將 GoFly 向上滑掉，保持手機解鎖，再繼續原交易。已完成項目與備份會保留。"
            case "source-busy": "請先在 iPhone 停止移動並完成裝置清除，關閉未結束的編輯，再繼續。"
            case "update-required": "原 App 或安裝來源尚不支援這個資料交接流程。原 App 與資料不會因此被移除。"
            case "backup-invalid": "備份尚未通過完整驗證；不會進入新的移除步驟。"
            case "device-disconnected": "請連接原本的 USB iPhone，再查詢原交易。"
            case "trust-required": "請解鎖原 iPhone 並確認信任此 Mac。"
            case "developer-mode-required": "請確認原 iPhone 的開發者模式已開啟。"
            case "removal-unknown", "transaction-unknown", "commit-unknown": "操作結果仍待確認。請查詢原交易，不會盲目重送移除或安裝。"
            case "restore-unknown": "安裝或資料匯入尚未完整確認，備份仍保留。"
            case "signing-required", "signature-invalid", "artifact-mismatch": "簽名或 App 驗證未通過，請確認原安裝來源與開發團隊。"
            case "storage-unavailable": "無法安全讀寫交易或備份資料，已停止後續步驟。"
            default: "本次交易尚未完成，請查詢原交易後依狀態繼續。"
            }
        }
    }
}
