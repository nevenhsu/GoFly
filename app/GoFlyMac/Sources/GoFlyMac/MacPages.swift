import SwiftUI
import GoFlyMacCore

extension MacRootView {
    @ViewBuilder var pageContent: some View {
        switch model.page {
        case .environment:
            VStack(alignment: .leading, spacing: 20) {
                if let environment = model.environment, !environment.teams.isEmpty {
                    StatusCard {
                        StatusRow(title: "Apple 開發者帳號",
                                  detail: "已找到 \(environment.teams.count) 個 Team。安裝與 renew 使用目前選擇的 Team。")
                        Rule()
                        HStack {
                            Text("目前 Team").font(GoFlyStyle.font(13, bold: true))
                            Spacer()
                            Picker("目前 Team", selection: Binding(
                                get: { model.selectedTeamID ?? environment.teams[0].teamID },
                                set: { model.selectTeam($0) })) {
                                ForEach(environment.teams) { team in
                                    Text(team.displayName).tag(team.teamID)
                                }
                            }.frame(maxWidth: 420)
                        }
                        Text("更換 Team 只影響之後的安裝與 renew；不會修改手機上既有 App。")
                            .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
            if model.installedOnFirstInstall {
                StatusCard {
                    StatusRow(title: "此 iPhone 已安裝 GoFly，請到裝置管理重新簽名",
                              detail: "首次安裝不會覆蓋現有 App。請前往這部 iPhone 的裝置頁，確認目前簽名狀態後再選擇「重新簽名」。")
                    Rule()
                    HStack {
                        Spacer()
                        PillButton(title: "前往裝置頁", primary: true,
                                   enabled: !model.busy && !model.setupLocksDevice) {
                            model.openSelectedDevicePage()
                        }.accessibilityIdentifier("manage-installed-device")
                    }
                }
            } else if let setup = model.setup {
                MacSetupPage(setup: setup, deviceID: model.selectedID,
                             detectedTeamID: model.selectedTeam?.teamID,
                             vpnInstalled: model.inspection?.vpnInstalled,
                             vpnConfirmed: model.setupVPNConfirmed,
                             checkingDevice: model.isChecking,
                             verifyDevice: { model.verifySetupDevice() })
                    .disabled(model.isChecking)
            } else {
                EmptyView()
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
        if model.failure != nil && !(model.page == .install && model.setup != nil) {
            PillButton(title: "返回裝置清單") { model.returnToDevices() }
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
                if model.inspection?.installed == true {
                    PillButton(title: "重新簽名") { model.startRenew() }
                        .accessibilityIdentifier("renew-signing")
                }
                Spacer(minLength: 0)
                PillButton(title: "重新檢查狀態", primary: true, enabled: model.selected != nil) { model.inspectSelected() }
            case .install:
                Spacer()
                if model.installedOnFirstInstall {
                    PillButton(title: "返回裝置清單", enabled: !model.busy) { model.returnToDevices() }
                } else if let setup = model.setup {
                    PillButton(title: setup.snapshot?.isComplete == true ? "前往裝置管理" : "返回裝置清單",
                               enabled: !model.busy && !setup.locksDevice && (setup.snapshot?.isComplete != true || model.setupVPNConfirmed)) { model.openDevices(firstInstall: setup.snapshot?.isComplete != true) }
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
