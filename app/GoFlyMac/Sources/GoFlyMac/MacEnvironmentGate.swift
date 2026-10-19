import AppKit
import SwiftUI
import GoFlyMacCore

struct MacEnvironmentGate: View {
    @Bindable var model: MacAppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 18) {
                        DesignAsset("WingedArrow", width: 64)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("GoFly").font(GoFlyStyle.font(30, bold: true))
                            Text("開始前準備").font(GoFlyStyle.font(14)).foregroundStyle(GoFlyStyle.muted)
                        }
                    }
                    content
                    HStack {
                        Spacer()
                        PillButton(title: "重新檢查", primary: true, enabled: !model.isChecking) {
                            model.checkEnvironment()
                        }
                        .accessibilityIdentifier("environment-recheck")
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 40).padding(.vertical, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoFlyStyle.canvas).foregroundStyle(GoFlyStyle.ink)
    }

    @ViewBuilder private var content: some View {
        if !model.hasCheckedEnvironment || (model.isChecking && model.environment == nil) {
            StatusCard {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("正在檢查 Mac 環境").font(GoFlyStyle.font(18, bold: true))
                }
                StatusRow(title: "檢查項目", detail: "Xcode、首次啟動、Apple 帳號、Python、專案與裝置清單。")
            }
        } else if let failure = model.failure, model.environment == nil {
            StatusCard {
                StatusRow(title: failure.title, detail: failure.detail)
                Rule()
                StatusRow(title: "不會自動變更系統", detail: "GoFly 不會使用 sudo、接受授權條款或替使用者安裝 Xcode 元件。")
            }
        } else if let environment = model.environment {
            if let failed = firstFailedCheck(environment) {
                stepCard(for: failed, environment: environment)
            } else if model.selectedTeam == nil {
                teamCard(environment)
            } else {
                StatusCard {
                    StatusRow(title: "Mac 環境已就緒", detail: "可以開始首次安裝或裝置管理。")
                }
            }
        } else {
            StatusCard {
                StatusRow(title: "正在檢查 Mac 環境", detail: "請稍候。")
            }
        }
    }

    private func firstFailedCheck(_ environment: MacEnvironment) -> EnvironmentCheck? {
        for id in ["developer-tools", "xcode-first-launch", "apple-account"] {
            if let check = environment.checks.first(where: { $0.id == id }), !check.passed { return check }
        }
        if environment.teams.isEmpty {
            return environment.checks.first { $0.id == "apple-account" }
                ?? EnvironmentCheck(id: "apple-account", title: "Apple 開發者帳號", detail: "請在 Xcode → Settings → Apple Accounts 登入。", passed: false)
        }
        if model.selectedTeam == nil { return nil }
        for id in ["python-runtime", "project", "device-discovery"] {
            if let check = environment.checks.first(where: { $0.id == id }), !check.passed { return check }
        }
        return environment.checks.first { !$0.passed }
    }

    @ViewBuilder private func stepCard(for check: EnvironmentCheck, environment: MacEnvironment) -> some View {
        StatusCard {
            StatusRow(title: check.title, detail: check.detail)
            Rule()
            switch check.id {
            case "developer-tools":
                StatusRow(title: "取得 Xcode", detail: "從 App Store 安裝 Xcode，完成後回到這裡重新檢查。")
                HStack {
                    Spacer()
                    PillButton(title: "在 App Store 取得 Xcode", primary: true) {
                        if let url = URL(string: "macappstore://apps.apple.com/app/id497799835") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            case "xcode-first-launch":
                StatusRow(title: "完成 Xcode 初次啟動", detail: "開啟 Xcode，讓 Xcode 自己顯示並完成元件安裝與授權。GoFly 不會代替你執行。")
                HStack {
                    Spacer()
                    PillButton(title: "開啟 Xcode 安裝元件", primary: true) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
                    }
                }
            case "apple-account":
                StatusRow(title: "登入 Apple 開發者帳號", detail: "請在 Xcode → Settings → Apple Accounts 按 + 登入。GoFly 不會要求或儲存 Apple ID 密碼。")
                HStack {
                    Spacer()
                    PillButton(title: "開啟 Xcode", primary: true) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Xcode.app"))
                    }
                }
            default:
                StatusRow(title: "修正後重新檢查", detail: "GoFly 只顯示本機檢查結果，不會自動變更系統設定。")
            }
        }
    }

    private func teamCard(_ environment: MacEnvironment) -> some View {
        StatusCard {
            StatusRow(title: "選擇開發團隊", detail: "偵測到 \(environment.teams.count) 個 Team。選擇後會保存在這台 Mac，安裝與 renew 都使用它。")
            Rule()
            ForEach(environment.teams) { team in
                Button {
                    model.selectTeam(team.teamID)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: team.isFreeProvisioningTeam ? "person.crop.circle" : "person.3")
                            .font(.system(size: 20)).frame(width: 26)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(team.teamName).font(GoFlyStyle.font(15, bold: true))
                            Text("\(team.teamID) · \(team.kind)").font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(GoFlyStyle.muted).accessibilityHidden(true)
                    }
                    .padding(14).frame(maxWidth: .infinity)
                    .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(GoFlyStyle.line, lineWidth: 0.75))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).goFlyRowFocus()
                    .accessibilityIdentifier("team-\(team.teamID)")
                if team.id != environment.teams.last?.id { Rule() }
            }
        }
    }
}
