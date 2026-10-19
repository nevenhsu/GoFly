import SwiftUI
import GoFlyMacCore

struct MacRootView: View {
    @Bindable var model: MacAppModel
    var body: some View {
        VStack(spacing: 0) {
            if model.isPreview {
                HStack(spacing: 16) {
                    Label("介面預覽", systemImage: "eye").font(GoFlyStyle.font(12, bold: true))
                    Text("示意資料，不會操作手機").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                    Spacer()
                    Picker("預覽情境", selection: $model.previewScenario) {
                        ForEach(PreviewScenario.allCases) { Text($0.title).tag($0) }
                    }.frame(width: 230).onChange(of: model.previewScenario) { model.applyScenario() }
                }.padding(.horizontal, 24).frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
                    .background(GoFlyStyle.secondarySurface)
                Rule()
            }
            if model.page == .home { home }
            else {
                HStack(spacing: 0) {
                    sidebar
                    VStack(alignment: .leading, spacing: 0) {
                        header.padding(.bottom, 24)
                        if let failure = pageCheckFailure { errorCard(failure) }
                        else { pageContent }
                        if let message = model.previewMessage {
                            Text(message).font(GoFlyStyle.font(13, bold: true)).padding(.top, 12)
                                .accessibilityIdentifier("preview-result")
                        }
                        footer.padding(.top, 28)
                    }
                    .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(GoFlyStyle.canvas).foregroundStyle(GoFlyStyle.ink)
        .tint(GoFlyStyle.ink)
        .font(GoFlyStyle.font(14))
    }

    private var home: some View {
        VStack(spacing: 0) {
            ScrollView {
            VStack(spacing: 0) {
            DesignAsset("WingedArrow", width: 112)
            Text("GoFly").font(GoFlyStyle.font(38, bold: true)).padding(.top, 4)
            Text("在 Mac 安裝與管理 iPhone 上的 GoFly")
                .font(GoFlyStyle.font(15)).foregroundStyle(GoFlyStyle.muted).padding(.top, 10)
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) }
                else if model.environment?.ready == true { DesignAsset("EnvironmentPassed", width: 24) }
                Text(model.busy ? "正在檢查 Mac 環境…" : model.environment?.ready == true ? "Mac 環境已就緒" : "Mac 環境尚未就緒")
                    .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
            }.padding(.horizontal, 14).padding(.vertical, 8)
                .background(GoFlyStyle.secondarySurface, in: Capsule())
                .padding(.top, 20).padding(.bottom, 28)
            PillButton(title: "首次安裝", primary: true, width: 360, height: 48, enabled: model.ready) { model.openDevices(firstInstall: true) }
                .accessibilityIdentifier("first-install")
            Text("USB 連接 iPhone，完成首次安裝與裝置準備")
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted).padding(.top, 8)
            if !model.isPreview, model.setup?.hasRecordedTransaction == true || model.setupLocksDevice {
                Button("查看安裝狀態") { model.openRecordedOperation() }
                    .padding(.top, 12).disabled(model.busy)
            }
            PillButton(title: "裝置管理", width: 360, height: 48, enabled: model.ready) { model.openDevices(firstInstall: false) }
                .padding(.top, 20).accessibilityIdentifier("manage-devices")
            Text("查看裝置狀態、簽名、連線與保留資料")
                .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted).padding(.top, 8)
            Button("查看 Mac 環境") { model.navigate(.environment) }
                .buttonStyle(.link).font(GoFlyStyle.font(12)).padding(.top, 22).disabled(model.busy)
            if let failure = model.failure {
                Text(failure.title).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted).padding(.top, 12)
            }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 24)
            }
            HStack {
                Text(model.isPreview ? "GoFly Mac · 介面預覽" : "GoFly Mac · 本機開發版")
                Spacer()
                Button(model.isPreview ? "返回實際操作" : "預覽操作流程") { model.switchMode(preview: !model.isPreview) }
                    .buttonStyle(.link).accessibilityIdentifier("switch-mode")
                    .disabled(model.setupLocksDevice)
            }.font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted).padding(24)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                DesignAsset("WingedArrow", width: 42)
                Text("GoFly").font(GoFlyStyle.font(24, bold: true))
            }.padding(.horizontal, 24).padding(.top, 24)
            if model.selected != nil {
                PillButton(title: "切換裝置", width: 176, height: 28, enabled: !model.busy && !model.setupLocksDevice) { model.openDevices(firstInstall: model.firstInstall) }
                    .padding(.horizontal, 24).padding(.top, 4)
            }
            Text(model.page == .environment ? "開始前準備" : model.firstInstall ? "首次安裝" : "裝置管理")
                .font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.muted)
                .padding(.horizontal, 24).padding(.top, model.selected == nil ? 32 : 12).padding(.bottom, 20)
            ForEach(Array(sidebarItems.enumerated()), id: \.offset) { index, item in
                Button { model.navigate(item.1) } label: {
                    HStack(spacing: 12) {
                        if model.firstInstall && model.page != .environment {
                            Text("\(index + 1)").font(GoFlyStyle.font(12, bold: true))
                                .frame(width: 20, height: 20)
                                .overlay(Circle().strokeBorder(selectedSidebar == item.1 ? GoFlyStyle.surface : GoFlyStyle.line))
                        } else {
                            Image(systemName: sidebarSymbol(item.1))
                                .font(.system(size: 16, weight: .medium)).frame(width: 22)
                                .accessibilityHidden(true)
                        }
                        Text(item.0).font(GoFlyStyle.font(14, bold: true)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .foregroundStyle(selectedSidebar == item.1 ? GoFlyStyle.surface : GoFlyStyle.ink)
                    .background(selectedSidebar == item.1 ? GoFlyStyle.ink : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).goFlyRowFocus().disabled(model.busy).help(item.0)
                    .accessibilityAddTraits(selectedSidebar == item.1 ? .isSelected : [])
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }
            Spacer()
            Text(model.isPreview ? "操作流程使用示意資料\n不會安裝或變更手機" : model.firstInstall ? "先確認裝置，再開始安裝\n中斷時接續原裝置交易" : "核對目前連接的 iPhone\n操作與結果以實際回報為準")
                .font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted).lineSpacing(4)
                .padding(.horizontal, 24).padding(.bottom, 40)
        }.frame(width: 240).frame(maxHeight: .infinity).background(GoFlyStyle.sidebar)
            .overlay(alignment: .trailing) {
                Rectangle().fill(GoFlyStyle.divider).frame(width: 0.5).allowsHitTesting(false)
            }
    }

    private func sidebarSymbol(_ page: MacPage) -> String {
        switch page {
        case .home: GoFlyMacSymbols.home
        case .environment: GoFlyMacSymbols.environment
        case .devices, .device: GoFlyMacSymbols.device
        case .install: GoFlyMacSymbols.install
        case .handoff: GoFlyMacSymbols.completed
        }
    }

    private var sidebarItems: [(String, MacPage)] {
        if model.page == .environment { return [("Mac 環境", .environment)] }
        if model.firstInstall {
            if !model.isPreview { return [("連接 iPhone", .devices), ("安裝 GoFly", .install)] }
            return [("連接 iPhone", .devices), ("安裝 GoFly", .install), ("Mac 安裝完成", .handoff)]
        }
        return [(model.selected?.displayName ?? "我的 iPhone", .device)]
    }
    private var selectedSidebar: MacPage { model.page }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(model.page == .environment ? "GoFly  /  Mac 環境" : (model.firstInstall ? "首次安裝" : model.selected?.displayName ?? "裝置管理") + "  /  " + pageTitle)
                    .font(GoFlyStyle.font(12, bold: true)).foregroundStyle(GoFlyStyle.muted)
                Spacer()
                PillButton(title: "首頁", width: 86, height: 36, enabled: !model.busy) { model.navigate(.home) }
            }
            Text(pageCheckFailure?.title ?? pageTitle).font(GoFlyStyle.font(28, bold: true)).padding(.top, 6)
            Text(pageCheckFailure?.detail ?? pageSubtitle).font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
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
                if !model.isPreview && !model.isChecking && model.page == .install && model.setup != nil {
                    pageActions
                } else if model.busy {
                    ProgressView().controlSize(.small)
                    Text(model.isCancellingCheck ? "正在結束檢查…" : "正在檢查，請保持手機連接…").font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    Spacer()
                    PillButton(title: "取消檢查", enabled: !model.isCancellingCheck) { model.cancel() }
                } else { pageActions }
            }
            HStack {
                Text(model.isPreview ? "GoFly Mac · 介面預覽，操作不會套用至裝置" : "GoFly Mac · 本機開發版")
                Spacer()
                if !model.isPreview {
                    Button("預覽此流程") { model.switchMode(preview: true) }
                        .buttonStyle(.link)
                        .disabled(model.setupLocksDevice)
                }
            }.font(GoFlyStyle.font(11)).foregroundStyle(GoFlyStyle.muted)
        }
    }

    private var pageTitle: String {
        switch model.page {
        case .home: "GoFly"
        case .environment: model.environment?.ready == true ? "Mac 環境已就緒" : "Mac 環境設定"
        case .devices: "選擇要連接的裝置"
        case .device: model.selected?.displayName ?? "我的 iPhone"
        case .install: "確認 GoFly 簽名與安裝"
        case .handoff: "Mac 安裝完成"
        }
    }
    private var pageSubtitle: String {
        switch model.page {
        case .home: ""
        case .environment: "背景檢測通過後，開放首次安裝介面與裝置管理檢查。"
        case .devices: model.firstInstall ? "只列出 USB 連接的裝置，請選擇要檢查的 iPhone。" : "相同 iPhone 只列一次並預設 USB；有兩種通道時，可明確選擇本次使用的連線。"
        case .device: "查看這部 iPhone 的裝置、安裝與連接狀態。"
        case .install: model.isPreview ? "使用 Xcode 中已設定的開發團隊（介面預覽）。" : "先檢查原裝置與簽名來源，再明確開始本次安裝。"
        case .handoff: "App、配對匯入及必要裝置支援均已確認；可拔除 USB。"
        }
    }

    private var pageCheckFailure: CheckFailure? {
        !model.isPreview && model.page == .install && model.setup != nil ? nil : model.failure
    }
}
