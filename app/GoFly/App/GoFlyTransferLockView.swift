import GoFlyCore
import SwiftUI

/// The source/restore gate is deliberately a small O10 surface. It exposes
/// only actual storage phase and bounded category counts; no normal map,
/// editor, Go, or task entry is attached while this view is shown.
struct GoFlyTransferLockView: View {
    let phase: GoFlySetupBootstrapPhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(goFlyString("setup.transfer.title"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .accessibilityIdentifier("setup.transfer.title")
                Text(goFlyString("setup.transfer.message"))
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setup.transfer.message")
                status
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .accessibilityIdentifier("setup.transfer")
    }

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .exportLocked(let receipt):
            statusRow("setup.transfer.phase", goFlyString(receipt.phase.transferStatusKey))
        case .restoreLocked(let restore):
            VStack(alignment: .leading, spacing: 8) {
                statusRow("setup.transfer.phase", goFlyString(restore.phase.transferStatusKey))
                ForEach(restore.categories, id: \.category) { category in
                    statusRow("setup.transfer.category.\(category.category.rawValue)",
                              goFlyString(category.state.transferStatusKey))
                }
                if let counts = restore.counts {
                    statusRow("setup.transfer.count.favorites", String(counts.favorites))
                    statusRow("setup.transfer.count.importedRoutes", String(counts.importedRoutes))
                    statusRow("setup.transfer.count.favoriteRoutes", String(counts.favoriteRoutes))
                    statusRow("setup.transfer.count.draftNodes", String(counts.draftNodes))
                    statusRow("setup.transfer.count.gpxPoints", String(counts.gpxPoints))
                }
            }
        case .transferWaiting(let reason):
            statusRow("setup.transfer.phase", goFlyString(reason.transferStatusKey))
        case .transferBlocked(let failure):
            statusRow("setup.transfer.phase", goFlyString(failure.transferStatusKey))
        default:
            EmptyView()
        }
    }

    private func statusRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(goFlyString(key))
                .font(.system(size: 14, weight: .semibold))
            Text(value)
                .font(.system(size: 14, design: .monospaced))
                .accessibilityValue(value)
        }
        .foregroundStyle(Color.primary)
    }
}

private extension TransferFailure {
    var transferStatusKey: String {
        switch self {
        case .busy, .sourceBusy, .exportConflict: return "setup.transfer.status.sourceBusy"
        default: return "setup.transfer.status.failed"
        }
    }
}

private extension GoFlyTransferWaitReason {
    var transferStatusKey: String {
        switch self {
        case .setup: return "setup.transfer.status.waitingMac"
        case .restore: return "setup.transfer.status.waitingRestore"
        case .export: return "setup.transfer.status.exporting"
        }
    }
}

private extension TransferExportPhase {
    var transferStatusKey: String {
        switch self {
        case .preparing: return "setup.transfer.status.exporting"
        case .ready, .removalSealed: return "setup.transfer.status.exported"
        case .released, .releasedNoSnapshot: return "setup.transfer.status.complete"
        }
    }
}

private extension TransferRestorePhase {
    var transferStatusKey: String {
        switch self {
        case .waiting: return "setup.transfer.status.waitingRestore"
        case .validating: return "setup.transfer.status.importing"
        case .committed: return "setup.transfer.status.complete"
        case .failed: return "setup.transfer.status.failed"
        }
    }
}

private extension TransferCategoryState {
    var transferStatusKey: String {
        switch self {
        case .waiting: return "setup.transfer.status.waiting"
        case .validating: return "setup.transfer.status.importing"
        case .committed: return "setup.transfer.status.complete"
        case .failed: return "setup.transfer.status.failed"
        }
    }
}
