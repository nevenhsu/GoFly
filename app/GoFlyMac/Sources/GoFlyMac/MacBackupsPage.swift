import GoFlyMacCore
import SwiftUI

/// Local backup rows are rendered from the protocol response only.  The page
/// never invents a completed row and delegates pending M2 continuation to the
/// existing transaction page supplied by the root model.
struct MacBackupsPage: View {
    @Bindable var backup: MacBackupModel
    let continuePending: (MacBackupEntry) -> Void
    @State private var pendingDelete: MacBackupEntry?

    var body: some View {
        StatusCard {
            StatusRow(title: "本機備份管理", detail: "成功匯入的備份保留七天後自動清理；尚未完成匯入的備份會繼續保留。")
            Rule()
            if backup.pendingDeletion {
                StatusRow(title: "上次整理尚未完成", detail: "備份狀態仍保留。按「繼續整理」核對並完成本機刪除。")
                Rule()
            }
            if backup.entries.isEmpty {
                StatusRow(title: "沒有本機備份", detail: "重新安裝時保留的資料會顯示在這裡。")
            } else {
                ForEach(backup.entries) { entry in
                    backupRow(entry)
                    if entry.id != backup.entries.last?.id { Rule() }
                }
            }
            if let failure = backup.failure {
                Rule()
                StatusRow(title: failure.title, detail: failure.detail)
            }
            if backup.isBusy {
                Rule()
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(backup.cancellationRequested ? "正在中止程序，等待實際返回…" : "正在讀取本機備份…")
                        .font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                    Spacer()
                    PillButton(title: "中止", width: 120, enabled: !backup.cancellationRequested) {
                        backup.cancel()
                    }
                }
            }
            Rule()
            HStack {
                PillButton(title: "重新整理", enabled: !backup.isBusy) { backup.list() }
                if backup.pendingDeletion || backup.failure != nil {
                    PillButton(title: "繼續整理", enabled: !backup.isBusy) { backup.maintain() }
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("backups.page")
        .confirmationDialog(
            "刪除這份已完成備份？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let entry = pendingDelete {
                Button("刪除備份", role: .destructive) {
                    pendingDelete = nil
                    backup.deleteExact(entry)
                }
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("只刪除此 Mac 上的副本，手機已匯入的資料不變。刪除後無法再用這份備份還原。")
        }
    }

    @ViewBuilder
    private func backupRow(_ entry: MacBackupEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusRow(title: "iPhone · …\(entry.deviceID.suffix(6))", detail: entry.kind.title)
            StatusRow(title: "保留項目", detail: categoriesText(entry))
            if let counts = entry.counts {
                StatusRow(title: "實際數量", detail: countsText(counts))
            }
            if let observed = entry.completedObservedAt {
                StatusRow(title: "完成確認", detail: displayDate(observed))
            }
            if let deleteAfter = entry.deleteAfter {
                StatusRow(title: "自動清理日期", detail: displayDate(deleteAfter))
            }
            HStack {
                if entry.canContinue {
                    PillButton(title: "繼續原交易", primary: true, width: 160) {
                        continuePending(entry)
                    }
                } else if entry.kind == .incomplete {
                    Text("未完成備份會保留；只有目前原交易可繼續。")
                        .font(GoFlyStyle.font(12)).foregroundStyle(GoFlyStyle.muted)
                }
                Spacer()
                if entry.canDelete {
                    PillButton(title: "刪除", width: 120) { pendingDelete = entry }
                }
            }
        }
    }

    private func categoriesText(_ entry: MacBackupEntry) -> String {
        guard !entry.categories.isEmpty else { return "未選擇保留資料" }
        return entry.categories.map(\.title).joined(separator: "、")
    }

    private func countsText(_ counts: MacBackupCounts) -> String {
        "最愛地點 \(counts.favorites) · 匯入路線 \(counts.importedRoutes) · 儲存路線 \(counts.favoriteRoutes) · 草稿地點 \(counts.draftNodes) · GPX 點 \(counts.gpxPoints)"
    }

    private func displayDate(_ value: String) -> String {
        ISO8601DateFormatter().date(from: value)?.formatted(date: .numeric, time: .shortened) ?? value
    }
}

private extension MacBackupKind {
    var title: String {
        switch self {
        case .completed: return "已成功匯入 · 保留七天"
        case .incomplete: return "尚未完成 · 備份保留"
        case .missing: return "已完成記錄 · 備份檔案目前不存在"
        case .deleted: return "本機副本已刪除"
        }
    }
}

private extension MacBackupCategory {
    var title: String {
        switch self {
        case .favorites: return "最愛地點"
        case .routes: return "路線"
        case .settings: return "設定"
        }
    }
}
