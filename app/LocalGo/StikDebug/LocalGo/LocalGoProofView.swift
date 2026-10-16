import Combine
import SwiftUI

enum LocalGoReadiness: Equatable {
    case unconfigured, preparing, ready, failed
}

@MainActor
final class LocalGoProofModel: ObservableObject {
    let engine = LiveLocationEngine()
    let commands: LocationCommandCoordinator
    @Published var isPreparing = false
    @Published var setupStatus = "尚未啟動"
    @Published var pairingImported = false
    @Published private(set) var readiness: LocalGoReadiness = .unconfigured
    private var commandChanges: AnyCancellable?
    private let setupHandoff = LocalGoSetupHandoff(importSetupData: { data, target in
        try PairingFileStore.importSetupData(data, expectedDeviceUDID: target)
    })

    init() {
        commands = LocationCommandCoordinator(engine: engine)
        pairingImported = PairingFileStore.isReady
        commandChanges = commands.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        consumeMacSetup()
    }

    var canConfigure: Bool { !isPreparing && commands.phase == .idle }
    var canSend: Bool { readiness == .ready && engine.isPrepared && !isPreparing }

    func consumeMacSetup() {
        guard canConfigure else { return }
        do { try setupHandoff.prepare() }
        catch {
            setupStatus = "無法儲存裝置設定，請稍後再試"
            return
        }
        switch setupHandoff.consume(commandsIdle: commands.phase == .idle, isPreparing: isPreparing) {
        case .noPayload: break
        case .imported:
            engine.invalidate()
            readiness = .unconfigured
            pairingImported = PairingFileStore.isReady
            setupStatus = "配對已完成；開啟 LocalDevVPN 後即可啟動"
        case .rejected:
            setupStatus = "配對未完成，請在 Mac 重新設定"
        case .storageFailure:
            engine.invalidate()
            readiness = .unconfigured
            pairingImported = PairingFileStore.isReady
            setupStatus = "配對未完成，請重新設定"
        }
    }

    func runtimeConnectionFailed() {
        engine.invalidate()
        readiness = .failed
        setupStatus = "連線中斷；請先停止並清除，再重新啟動"
    }

    func completeStop() {
        engine.invalidate()
        readiness = .unconfigured
        setupStatus = "已停止；可再次啟動"
    }

    func importPairing(_ url: URL, expectedDeviceUDID: String) {
        guard canConfigure else { return }
        engine.invalidate()
        readiness = .unconfigured
        do {
            try PairingFileStore.importFromPicker(url, expectedDeviceUDID: expectedDeviceUDID)
            pairingImported = true
            setupStatus = "配對已儲存，請按啟動"
        } catch {
            pairingImported = PairingFileStore.isReady
            setupStatus = "配對匯入失敗；請重新核對原有配對狀態"
        }
    }

    func prepare() {
        guard canConfigure, pairingImported else { return }
        isPreparing = true
        readiness = .preparing
        setupStatus = "正在啟動定位服務…"
        Task {
            do {
                try await DeveloperDiskImageService.shared.downloadMissingFiles()
                let engine = engine
                try await Task.detached(priority: .userInitiated) {
                    try engine.prepareDevice()
                }.value
                readiness = .ready
                setupStatus = "已啟動；尚未設定位置"
            } catch {
                engine.invalidate()
                readiness = .failed
                setupStatus = "啟動失敗；請檢查配對、Wi-Fi 與 LocalDevVPN"
            }
            isPreparing = false
        }
    }

    func deleteLocalPairing() {
        guard !isPreparing, commands.phase == .idle || commands.phase == .unknownFailure else { return }
        engine.invalidate()
        readiness = .unconfigured
        do {
            try PairingFileStore.remove()
            pairingImported = false
            setupStatus = "已刪除本 App 的配對；不代表已恢復定位或撤銷裝置信任"
        } catch {
            setupStatus = "本機配對刪除失敗"
        }
    }
}

@MainActor
struct LocalGoProofView: View {
    @ObservedObject private var model: LocalGoProofModel
    private let stop: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var expectedUDID = ""
    @State private var showImporter = false
    @State private var showDeleteConfirmation = false

    init(model: LocalGoProofModel, stop: @escaping () -> Void) {
        self.model = model
        self.stop = stop
    }

    var body: some View {
        NavigationStack {
            Form {
                deviceSection
                connectionSection
                locationSection
                advancedSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(LocalGoStyle.paper)
            .tint(LocalGoStyle.accent)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LocalGoStyle.paper, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .buttonStyle(LocalGoButtonStyle(.quiet))
                }
                ToolbarItem(placement: .topBarLeading) {
                    if model.canSend || model.commands.phase != .idle {
                        Button(role: .destructive) { stop() } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(LocalGoIconButtonStyle(destructive: true))
                        .disabled(model.isPreparing || model.commands.phase == .clearing)
                        .accessibilityLabel("停止並清除位置")
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: PairingFileStore.supportedContentTypes) { result in
            if case .success(let url) = result {
                model.importPairing(url, expectedDeviceUDID: expectedUDID)
                expectedUDID = ""
            }
        }
        .confirmationDialog("只刪除本機配對資料？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("刪除本機配對", role: .destructive) { model.deleteLocalPairing() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("這只會移除 App 內的配對資料；iPhone 信任與來源檔案仍由系統和你管理。")
        }
    }

    private var deviceSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(LocalGoStyle.accent)
                    .frame(width: 44, height: 44)
                    .background(LocalGoStyle.recessed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("LocalGo")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(LocalGoStyle.ink)
                    Text("iOS 26／27 · 個人裝置")
                        .font(.footnote)
                        .foregroundStyle(LocalGoStyle.muted)
                }

                Spacer(minLength: 8)
                Image(systemName: model.pairingImported ? "checkmark.circle.fill" : "cable.connector")
                    .foregroundStyle(model.pairingImported ? LocalGoStyle.accent : LocalGoStyle.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 5)

            Text("先開啟 LocalDevVPN，再按啟動。首次設定完成後，日常使用不需要連接 Mac。")
                .font(.footnote)
                .foregroundStyle(LocalGoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("裝置")
        }
        .listRowBackground(LocalGoStyle.surface)
    }

    private var connectionSection: some View {
        Section {
            LocalGoVPNButton()
            HStack {
                Label(
                    model.pairingImported ? "配對已準備" : "需要配對",
                    systemImage: model.pairingImported ? "checkmark.shield.fill" : "cable.connector"
                )
                .foregroundStyle(LocalGoStyle.ink)
                Spacer(minLength: 8)
                Text(model.pairingImported ? "已就緒" : "尚未完成")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.pairingImported ? LocalGoStyle.accent : LocalGoStyle.muted)
            }

            Button(model.isPreparing ? "啟動中…" : (model.canSend ? "已啟動" : "啟動")) { model.prepare() }
                .buttonStyle(LocalGoButtonStyle(.primary))
                .frame(maxWidth: .infinity)
                .disabled(!model.canConfigure || !model.pairingImported || model.canSend)

            if model.isPreparing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在準備裝置…")
                        .font(.footnote)
                        .foregroundStyle(LocalGoStyle.muted)
                }
            }

            Text(model.setupStatus)
                .font(.footnote)
                .foregroundStyle(LocalGoStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("連線")
        }
        .listRowBackground(LocalGoStyle.surface)
    }

    private var locationSection: some View {
        Section {
            if let coordinate = model.commands.latestAcceptedCoordinate {
                VStack(alignment: .leading, spacing: 4) {
                    Text("目前位置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LocalGoStyle.ink)
                    Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(LocalGoStyle.accent)
                }
            } else {
                Label("尚未設定位置", systemImage: "location.slash")
                    .foregroundStyle(LocalGoStyle.muted)
            }

            Text(commandStatus)
                .font(.footnote)
                .foregroundStyle(model.commands.phase == .unknownFailure ? LocalGoStyle.danger : LocalGoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("切到背景時路線會暫停、搖桿會停止更新；返回後可手動繼續，最後位置會保留。")
                .font(.caption)
                .foregroundStyle(LocalGoStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("位置")
        }
        .listRowBackground(LocalGoStyle.surface)
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("進階設定") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("自動配對未完成時，可在這裡手動更新。配對資料只會留在 App 私有空間。")
                        .font(.footnote)
                        .foregroundStyle(LocalGoStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    SecureField("此 iPhone 的完整 UDID", text: $expectedUDID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(!model.canConfigure)

                    Button("選擇配對檔") { showImporter = true }
                        .buttonStyle(LocalGoButtonStyle(.secondary))
                        .disabled(!model.canConfigure || expectedUDID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Link("查看配對與簽署說明", destination: URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!)
                        .font(.footnote.weight(.semibold))

                    Button("刪除本機配對", role: .destructive) { showDeleteConfirmation = true }
                        .buttonStyle(LocalGoButtonStyle(.danger))
                        .disabled(model.isPreparing || (model.commands.phase != .idle && model.commands.phase != .unknownFailure))
                }
                .padding(.vertical, 6)
            }
            .foregroundStyle(LocalGoStyle.ink)
        }
        .listRowBackground(LocalGoStyle.surface)
    }

    private var aboutSection: some View {
        Section {
            Text("以 StikDebug／idevice 開源專案為基礎；保留 AGPL-3.0 授權。")
                .font(.caption)
                .foregroundStyle(LocalGoStyle.muted)

            Link("StikDebug 原始碼與授權", destination: URL(string: "https://github.com/StikDebug/StikDebug/tree/734361bb9d03817ed8dd82cb27cf8b2b3792b458")!)
            Link("idevice 原始碼", destination: URL(string: "https://github.com/jkcoxson/idevice")!)
        } header: {
            Text("關於")
        }
        .listRowBackground(LocalGoStyle.surface)
    }

    private var commandStatus: String {
        switch model.commands.phase {
        case .idle: return "尚未設定位置"
        case .preparing: return "正在準備位置更新…"
        case .applying: return "正在更新位置…"
        case .accepted: return "位置已送出"
        case .clearing: return "正在清除模擬位置…"
        case .unknownFailure: return "位置狀態未知；請先停止並清除"
        }
    }
}
