import SwiftUI
import GoFlyMacCore

extension MacRootView {
    @ViewBuilder var pageContent: some View {
        switch model.page {
        case .environment:
            StatusCard {
                if let environment = model.environment {
                    ForEach(environment.checks) { check in
                        HStack(alignment: .top, spacing: 12) {
                            if check.passed { DesignAsset("EnvironmentPassed", width: 24) }
                            else {
                                Image(systemName: "exclamationmark.circle").font(.system(size: 19))
                                    .foregroundStyle(GoFlyStyle.muted).frame(width: 24, height: 24).accessibilityHidden(true)
                            }
                            StatusRow(title: check.title, detail: check.detail)
                        }
                        if check.id != environment.checks.last?.id { Rule() }
                    }
                } else {
                    StatusRow(title: "正在檢查 Xcode 與必要元件", detail: "不會自動安裝元件或接受系統條款。")
                }
            }
        case .devices: devicePicker
        case .device:
            StatusCard {
                StatusRow(title: model.installStatus, detail: versionDetail)
                Rule()
                StatusRow(title: "裝置連接", detail: connectionDetail)
                Rule()
                StatusRow(title: "簽名狀態", detail: signatureDetail)
                Rule()
                StatusRow(title: "LocalDevVPN", detail: vpnDetail)
            }
        case .install:
            if !model.isPreview, let setup = model.setup {
                MacSetupPage(setup: setup, deviceID: model.selectedID,
                             vpnInstalled: model.inspection?.vpnInstalled,
                             vpnConfirmed: model.setupVPNConfirmed,
                             checkingDevice: model.isChecking,
                             verifyDevice: { model.verifySetupDevice() })
                    .disabled(model.isChecking)
            } else {
            StatusCard {
                StatusRow(title: "目標裝置", detail: connectionDetail)
                Rule()
                if model.inspection?.developerMode != true {
                    StatusRow(title: "開發者模式", detail: developerDetail)
                    Rule()
                }
                StatusRow(title: "簽名身分", detail: model.isPreview ? "Personal Team · 已選取（預覽）" : model.environment?.teamID.map { "Xcode Personal Team · \($0)；尚未用於簽署" } ?? "尚未選取。可至 Xcode → Settings → Apple Accounts 查看。")
                Rule()
                StatusRow(title: "有效期限", detail: "安裝後須依實際核發的描述檔確認。本版不會申請描述檔或簽署 App。")
                if !model.isPreview {
                    Rule()
                    StatusRow(title: "目前僅提供介面與檢查", detail: "正式 iOS flow 仍在討論。安裝、簽名與配對寫入尚未開放。")
                }
            }
            }
        case .signing:
            if !model.isPreview, let management = model.management {
                MacManagementPage(management: management, kind: .renew, device: model.selected,
                    selection: model.managementSelection, defaultTeam: model.environment?.teamID,
                    finish: { await model.finishManagement() }, cancel: { model.cancelManagement() })
                    .disabled(model.isChecking)
            } else {
            StatusCard {
                StatusRow(title: "目前簽名", detail: signatureDetail)
                Rule()
                StatusRow(title: "重新簽名", detail: "沿用相容的簽名身分，更新 App 的簽署有效性。現有資料與設定應保留。")
                Rule()
                StatusRow(title: "簽名身分不符？", detail: "重新安裝前先選擇保留資料；只有安裝與選取資料匯入都完成，才顯示整體完成。")
                if !model.isPreview {
                    Rule()
                    StatusRow(title: "重新安裝與資料保留", detail: "簽名相容性尚未確認時，可明確選擇資料保留流程。備份完整驗證後才會移除原 App。")
                }
            }
            }
        case .repair:
            if !model.isPreview, let management = model.management {
                MacManagementPage(management: management, kind: .repair, device: model.selected,
                    selection: model.managementSelection, defaultTeam: model.environment?.teamID,
                    finish: { await model.finishManagement() }, cancel: { model.cancelManagement() })
                    .disabled(model.isChecking)
            } else {
            StatusCard {
                StatusRow(title: model.selected?.displayName ?? "尚未選擇 iPhone", detail: connectionDetail)
                Rule()
                StatusRow(title: "開發者模式", detail: developerDetail)
                Rule()
                Button { model.navigate(.channel) } label: {
                    StatusRow(title: "手機 App 仍無法啟動或連線？  ›", detail: "查看 LocalDevVPN 與手機端服務檢查步驟。")
                }.buttonStyle(.plain).goFlyRowFocus()
                Rule()
                StatusRow(title: "裝置配對", detail: model.isPreview ? "裝置身分已核對（預覽）" : "這次只用既有信任進行唯讀核對，不建立、重建或交付配對資料。")
            }
            }
        case .channel:
            StatusCard {
                StatusRow(title: "1  在 iPhone 開啟 LocalDevVPN", detail: "按 Connect，確認 App 顯示連線狀態。Mac 無法據此確認手機本機通道可用。")
                Rule()
                StatusRow(title: "2  返回手機 App", detail: "在手機重新檢查本機通道與裝置服務；成功後再手動繼續。")
                Rule()
                StatusRow(title: "3  仍然失敗？", detail: "確認信任、開發者模式與裝置配對。手機內的設定流程尚在討論，本次不修改。")
            }
        case .handoff:
            StatusCard {
                StatusRow(title: model.isPreview ? "Mac 已完成（預覽）" : "Mac 交接條件待確認",
                          detail: model.isPreview ? "App 安裝、本次配對匯入與必要裝置支援完成（示意）。本次沒有寫入手機。" : "必須驗證 App 安裝與本次配對匯入回報；唯讀檢查不會產生安裝成功結果。")
                Rule()
                StatusRow(title: "可以拔除 USB", detail: "首次安裝流程到此結束。VPN 與定位操作依 iPhone 內的正常提示完成。")
                Rule()
                StatusRow(title: "簽名到期日", detail: signatureDetail)
            }
        case .reinstall:
            if !model.isPreview, let reinstall = model.reinstall {
                MacReinstallPage(reinstall: reinstall, device: model.selected) { await model.finishReinstall() }
                    .disabled(model.isChecking)
            } else {
            StatusCard {
                StatusRow(title: "選擇重新安裝後要保留的資料", detail: "只備份勾選項目；重新安裝後自動匯入。這裡僅預覽資料選擇，不讀取或移除手機資料。")
                Toggle(isOn: $model.preserveFavorites) {
                    StatusRow(title: "最愛地點與標籤", detail: "儲存的地點、自訂名稱與標籤")
                }.toggleStyle(.checkbox)
                Toggle(isOn: $model.preserveRoutes) {
                    StatusRow(title: "路線", detail: "儲存的路線、途經點與路線選項")
                }.toggleStyle(.checkbox)
                Toggle(isOn: $model.preserveSettings) {
                    StatusRow(title: "設定", detail: "速度與操作偏好；移動任務不會自動恢復")
                }.toggleStyle(.checkbox)
                Rule()
                Text("未勾選資料將不保留。所有項目取消時，代表全新安裝的預覽情境。")
                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
            }
            }
        case .backups:
            if !model.isPreview, let backups = model.backups {
                MacBackupsPage(backup: backups) { model.openBackup($0) }
                    .disabled(model.isChecking)
                    .task { if !model.busy { backups.list() } }
            } else {
            StatusCard {
                StatusRow(title: model.isPreview ? "我的 iPhone · 最愛、路線、設定（預覽）" : "沒有讀取手機備份",
                          detail: model.isPreview ? "已成功匯入 · 七天後可刪除（示意）" : "本版不建立備份、不讀取既有備份，也不刪除任何備份。")
                Rule()
                StatusRow(title: "尚未完成匯入", detail: model.isPreview ? "測試 iPhone · 上次未完成（預覽）\n保留備份，重新確認原裝置後再由使用者繼續。" : "正式資料格式、原裝置綁定與手機回報協定，待 iOS flow 確認後再接入。")
            }
            }
        case .home: EmptyView()
        }
    }

    private var devicePicker: some View {
        StatusCard {
            HStack {
                Text("可連接的裝置").font(GoFlyStyle.font(16, bold: true))
                Spacer()
                Text("\(Set(model.visibleDevices.map { $0.id.lowercased() }).count) 部裝置").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                Button("搜尋裝置") { model.refreshDevices() }.disabled(model.busy)
            }
            if model.visibleDevices.isEmpty {
                VStack(spacing: 14) {
                    DesignAsset("Device", width: 32, height: 44)
                    Text(model.busy ? "正在搜尋可連接裝置…" : "尚未偵測到 iPhone").font(GoFlyStyle.font(18, bold: true))
                    Text(model.firstInstall ? "請用 USB 連接並解鎖 iPhone，再按搜尋裝置。" : "請用 USB 連接，或確認裝置已透過既有配對出現在同一網路。")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 48)
            } else {
                ForEach(model.visibleDevices, id: \.connectionID) { device in
                    let selected = model.selectedID?.lowercased() == device.id.lowercased()
                    let displayed = selected ? model.selected ?? device : device
                    Button { model.select(device.id, transport: displayed.transport) } label: {
                        HStack(spacing: 16) {
                            DesignAsset("Device", width: 32, height: 44)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(device.displayName).font(GoFlyStyle.font(18, bold: true))
                                Text("可偵測 · 信任與安裝狀態待檢查").font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                                Text(device.osVersion.map { "iOS \($0)" } ?? "裝置識別：…\(device.id.suffix(6))")
                                    .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: displayed.transport == .usb ? GoFlyMacSymbols.usb : GoFlyMacSymbols.wifi)
                                    .accessibilityHidden(true)
                                Text(displayed.connectionName).font(GoFlyStyle.font(12, bold: true))
                            }.padding(.horizontal, 12).padding(.vertical, 8)
                                .background(GoFlyStyle.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(GoFlyStyle.line, lineWidth: 0.75))
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20)).foregroundStyle(selected ? GoFlyStyle.ink : GoFlyStyle.muted)
                                .accessibilityHidden(true)
                        }.padding(20).frame(minHeight: 112)
                            .background(selected ? GoFlyStyle.secondarySurface : GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? GoFlyStyle.ink : GoFlyStyle.line, lineWidth: selected ? 1.5 : 0.75))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).goFlyRowFocus().disabled(model.busy)
                        .accessibilityLabel("\(device.displayName)，\(displayed.connectionName)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    let connections = model.availableConnections.filter { $0.id.lowercased() == device.id.lowercased() }
                    if connections.count > 1 {
                        Picker("本次連線", selection: Binding(
                            get: { displayed.transport },
                            set: { model.select(device.id, transport: $0) })) {
                            ForEach(connections, id: \.connectionID) { connection in
                                Text(connection.connectionName).tag(connection.transport)
                            }
                        }.disabled(model.busy).padding(.bottom, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder var pageActions: some View {
        if model.failure != nil && !(!model.isPreview &&
            ((model.page == .install && model.setup != nil) || (model.page == .reinstall && model.reinstall != nil) ||
             ((model.page == .signing || model.page == .repair) && model.management != nil))) {
            PillButton(title: "返回裝置清單", enabled: model.environment?.ready == true) { model.openDevices(firstInstall: model.firstInstall) }
            Spacer(minLength: 0)
            PillButton(title: "重新檢查", primary: true) { retry() }
        } else {
            switch model.page {
            case .environment:
                Spacer()
                PillButton(title: "開啟 Xcode") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app")) }
                PillButton(title: "重新檢測", primary: true) { model.checkEnvironment() }
            case .devices:
                PillButton(title: "USB 連接指引") { showUSBGuide() }
                Spacer(minLength: 0)
                PillButton(title: "檢查裝置", primary: true, enabled: model.mayInspect) { model.inspectSelected() }
                    .accessibilityIdentifier("inspect-device")
            case .device:
                PillButton(title: "備份管理") { model.navigate(.backups) }
                Spacer(minLength: 0)
                PillButton(title: "重新檢查狀態", primary: true, enabled: model.selected != nil) { model.inspectSelected() }
            case .install:
                Spacer()
                if !model.isPreview, let setup = model.setup {
                    PillButton(title: setup.snapshot?.isComplete == true ? "前往裝置管理" : "返回裝置清單",
                               enabled: !model.busy && !setup.locksDevice && (setup.snapshot?.isComplete != true || model.setupVPNConfirmed)) { model.openDevices(firstInstall: setup.snapshot?.isComplete != true) }
                } else {
                    PillButton(title: "返回裝置清單") { model.openDevices(firstInstall: true) }
                    PillButton(title: "預覽簽名與安裝", primary: true,
                               enabled: model.isPreview && model.inspection?.developerMode == true) { model.previewAdvance() }
                }
            case .handoff:
                Spacer()
                PillButton(title: "前往裝置管理", primary: true) { model.openDevices(firstInstall: false) }
            case .signing:
                PillButton(title: "保留資料與重裝", enabled: !model.setupLocksDevice) { model.navigate(.reinstall) }
                Spacer(minLength: 0)
                if model.isPreview {
                    PillButton(title: "預覽重新簽名", primary: true) { model.previewAdvance() }
                }
            case .repair:
                if model.isPreview { PillButton(title: "預覽修復裝置配對") { model.previewAdvance() } }
                else { PillButton(title: "手機連線指引", enabled: !model.setupLocksDevice) { model.navigate(.channel) } }
                Spacer(minLength: 0)
                PillButton(title: "重新檢查連接", primary: true, enabled: model.selected != nil && !model.setupLocksDevice) { model.inspectSelected() }
            case .channel:
                Spacer()
                PillButton(title: "返回連接與修復", primary: true) { model.navigate(.repair) }
            case .reinstall:
                PillButton(title: "返回簽名管理") { model.navigate(.signing) }
                Spacer(minLength: 0)
                if model.isPreview {
                    PillButton(title: "預覽備份與重新安裝", primary: true) { model.previewAdvance() }
                }
            case .backups:
                PillButton(title: "返回裝置狀態") { model.navigate(.device) }
                Spacer(minLength: 0)
                if model.isPreview {
                    PillButton(title: "預覽待匯入資料", primary: true) { model.previewAdvance() }
                }
            case .home: EmptyView()
            }
        }
    }

    private var connectionDetail: String {
        guard let device = model.inspection?.device ?? model.selected else { return "尚未選擇並檢查裝置。" }
        let version = device.osVersion.map { " · iOS \($0)" } ?? ""
        return "\(device.displayName) · \(device.connectionName)\(version)\n\(model.inspection == nil ? "裝置狀態待確認" : "本次身分核對完成")"
    }
    private var versionDetail: String {
        model.inspection?.appVersion.map { "目前版本 \($0)" } ?? "沒有取得可核對的 App 版本資訊。"
    }
    private var signatureDetail: String {
        guard let inspection = model.inspection, let expiry = inspection.expiresAt else {
            return "待確認。尚未取得已安裝 App 的簽名身分與實際到期日。"
        }
        let date = ISO8601DateFormatter().date(from: expiry)
        let style = Date.FormatStyle(date: .numeric, time: .shortened).locale(Locale(identifier: "zh_TW"))
        let display = date?.formatted(style) ?? expiry
        return "到期：\(display)\(date.map { $0 < Date() ? " · 已過期" : "" } ?? "")\n\(inspection.teamID ?? "簽名身分待確認")"
    }
    private var developerDetail: String {
        switch model.inspection?.developerMode {
        case true: "已開啟。此狀態不代表手機內定位服務已準備完成。"
        case false: "尚未開啟。請至 iPhone 設定 → 隱私權與安全性 → 開發者模式完成設定。"
        default: "待確認。解鎖並信任此 Mac 後，再檢查裝置。"
        }
    }
    private var vpnDetail: String {
        switch model.inspection?.vpnInstalled {
        case true: "已偵測到 App。是否已 Connect 須在手機確認。"
        case false: "未偵測到 App。後續可在 iPhone App Store 安裝。"
        default: "安裝狀態待確認。本次沒有自動安裝或啟動 LocalDevVPN。"
        }
    }
    private func retry() {
        if model.environment == nil { model.checkEnvironment() }
        else if model.selected != nil { model.inspectSelected() }
        else { model.refreshDevices() }
    }
    private func showUSBGuide() {
        let alert = NSAlert()
        alert.messageText = "用 USB 連接 iPhone"
        alert.informativeText = "1. 使用可傳輸資料的 USB 線連接 Mac 與 iPhone。\n2. 解鎖手機，若已出現信任提示，請自行確認。\n3. 回到這裡按「搜尋裝置」。\n\n本版只讀取既有連接，不自動建立配對或寫入手機。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
