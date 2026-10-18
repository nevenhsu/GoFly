import Darwin
import Foundation
import GoFlyCore

struct GoFlyManagementControlURL {
    enum Action: String { case quiesce, seal, release }
    let action: Action
    let managementID: UUID
    let nonce: UUID

    init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "gofly", parts.host == "management",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let action = Action(rawValue: String(parts.path.dropFirst())),
              parts.path == "/" + action.rawValue,
              let query = parts.queryItems, query.count == 2,
              Set(query.map(\.name)) == ["managementID", "nonce"],
              let idText = query.first(where: { $0.name == "managementID" })?.value,
              let nonceText = query.first(where: { $0.name == "nonce" })?.value,
              let id = UUID(uuidString: idText), id.uuidString.lowercased() == idText,
              let nonce = UUID(uuidString: nonceText), nonce.uuidString.lowercased() == nonceText else { return nil }
        self.action = action
        managementID = id
        self.nonce = nonce
    }
}

extension GoFlySetupBootstrap {
    func handleManagement(_ link: GoFlyManagementControlURL) {
        if link.action == .quiesce, transferTask != nil { return }
        let prior = transferTask
        let id = UUID()
        transferTaskID = id
        let startup = startupTask
        transferTask = Task { [weak self] in
            if let startup { await startup.value }
            if let prior { await prior.value }
            guard let self else { return }
            defer { transferDidFinish(id) }
            await processManagement(link)
        }
    }

    private func processManagement(_ link: GoFlyManagementControlURL) async {
        do {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask).first else { return }
            let store = ManagementStore(applicationSupport: support)
            try store.prepareIncomingFiles()
            guard let input = try store.readInput(),
                  input.request.managementID == link.managementID,
                  input.request.nonce == link.nonce else { return }
            let export = TransferExportStore(applicationSupport: support)
            if let receipt = try export.readExport(),
               [.preparing, .ready, .removalSealed].contains(receipt.phase) { return }
            let app = try GoFlySetupIdentityReader.read()
            let pid = Int32(getpid())
            let setup = SetupActivationStore(directory: try GoFlySetupPaths.directory())
            let restore = TransferRestoreStore(applicationSupport: support)
            switch link.action {
            case .quiesce:
                if activeDataLease != nil {
                    if let receipt = try store.readSourceReceipt(currentApp: app, pid: pid),
                       receipt.phase == .ready || receipt.phase == .mutationSealed {
                        _ = try store.writeSourceReadback(currentApp: app, pid: pid)
                    }
                    return
                }
                guard let runtime, runtime.movement.canExportFromMap,
                      let lease = GoFlyDataLease.acquire(runtime: runtime),
                      let sessionToken = lease.recovery else { return }
                let priorPhase = phase
                activeDataLease = lease
                // Every owner is synchronously held before this snapshot and
                // the first await. Nothing saves an editor or clears GPS.
                let snapshot = runtime.movement.recovery.snapshot(mode: runtime.movement.presentationMode)
                setTransferPhase(.managementWaiting)
                do {
                    let prepared = try await Task.detached(priority: .utility) {
                        try store.prepareSource(currentApp: app, pid: pid,
                                                setupStore: setup, restoreStore: restore)
                    }.value
                    guard runtime.sessionRecovery.capture(snapshot, using: sessionToken),
                          await runtime.sessionRecovery.flush(using: sessionToken) else {
                        throw ManagementFailure.storageUnavailable
                    }
                    _ = try store.commitSourceReady(prepared, currentApp: app, pid: pid)
                    if let status = try store.status() { setTransferPhase(.managementLocked(status)) }
                    _ = try store.writeSourceReadback(currentApp: app, pid: pid)
                } catch {
                    // A durable preparing root or an unreadable outcome keeps
                    // the actual holds. Only a proven absent root may release.
                    do {
                        if let status = try store.status(),
                           status.managementID == input.request.managementID,
                           status.requestSHA256 == input.rawRequestSHA256,
                           [.preparing, .ready, .mutationSealed].contains(status.phase) {
                            setTransferPhase(.managementLocked(status))
                        } else if lease.releaseAll() {
                            activeDataLease = nil
                            setTransferPhase(priorPhase)
                        } else {
                            setTransferPhase(.managementBlocked(.storageUnavailable))
                        }
                    } catch { setTransferPhase(.managementBlocked(.storageUnavailable)) }
                }
            case .seal:
                guard activeDataLease != nil else { return }
                if try store.readSourceReceipt(currentApp: app, pid: pid)?.phase != .mutationSealed {
                    _ = try store.sealSource(currentApp: app, pid: pid)
                }
                if let status = try store.status() { setTransferPhase(.managementLocked(status)) }
                _ = try store.writeSourceReadback(currentApp: app, pid: pid)
            case .release:
                _ = try store.releaseSource(currentApp: app, pid: pid,
                                            setupStore: setup, restoreStore: restore)
                if let lease = activeDataLease {
                    guard lease.releaseAll() else {
                        setTransferPhase(.managementBlocked(.storageUnavailable))
                        return
                    }
                    activeDataLease = nil
                }
                _ = try store.writeSourceReadback(currentApp: app, pid: pid)
                if runtime == nil { restartAfterTransfer() }
                else { setTransferPhase(.ordinaryStartup) }
            }
        } catch let failure as ManagementFailure {
            if activeDataLease != nil || phase.isManagementLocked {
                setTransferPhase(.managementBlocked(failure))
            }
        } catch {
            if activeDataLease != nil || phase.isManagementLocked {
                setTransferPhase(.managementBlocked(.storageUnavailable))
            }
        }
    }
}
