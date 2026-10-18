import Darwin
import Foundation
import GoFlyCore

/// The eight synchronous owners that form the source export admission. The
/// lease remains retained by the bootstrap while the durable export root is
/// preparing/ready/sealed; cancellation never drops a physical operation early.
@MainActor
final class GoFlyDataLease {
    private let runtime: GoFlyRuntimeAssembly
    var service: TransferHold?
    var route: TransferHold?
    var joystick: TransferHold?
    var favorites: TransferHold?
    var imported: TransferHold?
    var favoriteRoutes: TransferHold?
    var movementRecovery: TransferHold?
    var recovery: TransferHold?
    var preferences: UUID?

    init(runtime: GoFlyRuntimeAssembly) { self.runtime = runtime }

    static func acquire(runtime: GoFlyRuntimeAssembly) -> GoFlyDataLease? {
        let lease = GoFlyDataLease(runtime: runtime)
        guard let service = runtime.service.acquireTransferHold() else { return nil }
        lease.service = service
        guard let route = runtime.movement.route.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.route = route
        guard let joystick = runtime.movement.joystick.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.joystick = joystick
        guard let favorites = runtime.favorites.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.favorites = favorites
        guard let imported = runtime.importedRoutes.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.imported = imported
        guard let favoriteRoutes = runtime.favoriteRoutes.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.favoriteRoutes = favoriteRoutes
        guard let movementRecovery = runtime.movement.recovery.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.movementRecovery = movementRecovery
        guard let recovery = runtime.sessionRecovery.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.recovery = recovery
        guard let preferences = GoFlyPreferences.shared.acquireTransferHold() else { _ = lease.releaseAll(); return nil }
        lease.preferences = preferences
        return lease
    }

    @discardableResult
    func releaseAll() -> Bool {
        var released = true
        if let token = preferences {
            if GoFlyPreferences.shared.releaseTransferHold(token) { self.preferences = nil }
            else { released = false }
        }
        if let token = recovery {
            if runtime.sessionRecovery.releaseTransferHold(token) { self.recovery = nil }
            else { released = false }
        }
        if let token = movementRecovery {
            if runtime.movement.recovery.releaseTransferHold(token) { self.movementRecovery = nil }
            else { released = false }
        }
        if let token = favoriteRoutes {
            if runtime.favoriteRoutes.releaseTransferHold(token) { self.favoriteRoutes = nil }
            else { released = false }
        }
        if let token = imported {
            if runtime.importedRoutes.releaseTransferHold(token) { self.imported = nil }
            else { released = false }
        }
        if let token = favorites {
            if runtime.favorites.releaseTransferHold(token) { self.favorites = nil }
            else { released = false }
        }
        if let token = joystick {
            if runtime.movement.joystick.releaseTransferHold(token) { self.joystick = nil }
            else { released = false }
        }
        if let token = route {
            if runtime.movement.route.releaseTransferHold(token) { self.route = nil }
            else { released = false }
        }
        if let token = service {
            if runtime.service.releaseTransferHold(token) { self.service = nil }
            else { released = false }
        }
        return released
    }
}

extension GoFlySetupBootstrap {
    func handle(url: URL) {
        if let management = GoFlyManagementControlURL(url: url) {
            handleManagement(management)
            return
        }
        guard !phase.isManagementLocked,
              let link = try? TransferControlURL(url: url) else { return }
        // A live physical export is never canceled by a duplicate URL. A
        // release/seal waits for the existing physical body to return before
        // observing the durable root.
        if link.action == .export, transferTask != nil { return }
        let prior = link.action == .export ? nil : transferTask
        let id = UUID()
        transferTaskID = id
        let startup = startupTask
        transferTask = Task { [weak self] in
            if let startup { await startup.value }
            if let prior { await prior.value }
            guard let self else { return }
            defer { self.transferDidFinish(id) }
            await self.processTransfer(link)
        }
    }

    private func processTransfer(_ link: TransferControlURL) async {
        do {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { return }
            let store = TransferExportStore(applicationSupport: support)
            try await Task.detached(priority: .utility, operation: {
                try store.prepareIncomingFiles()
            }).value
            guard let input = try await Task.detached(priority: .utility, operation: {
                try store.readRequest()
            }).value, let control = try await Task.detached(priority: .utility, operation: {
                try store.readControl()
            }).value,
                  control.action == link.action,
                  control.transferID == link.transferID,
                  control.nonce == link.nonce,
                  input.request.transferID == link.transferID,
                  input.request.nonce == link.nonce else { return }
            let currentApp = try await Task.detached(priority: .utility, operation: {
                try GoFlySetupIdentityReader.read()
            }).value

            switch link.action {
            case .export:
                await performExport(input: input, control: control, currentApp: currentApp,
                                    support: support, store: store)
            case .seal:
                let receipt = try await Task.detached(priority: .utility) {
                    try store.seal(control, currentApp: currentApp)
                }.value
                setTransferPhase(.exportLocked(receipt))
                try await writeReadback(store: store, control: control, currentApp: currentApp)
            case .release:
                let receipt = try await Task.detached(priority: .utility) {
                    try store.release(control, input: input, currentApp: currentApp)
                }.value
                if let lease = activeDataLease {
                    guard lease.releaseAll() else { return }
                    activeDataLease = nil
                }
                try await writeReadback(store: store, control: control, currentApp: currentApp)
                if receipt.phase == .released || receipt.phase == .releasedNoSnapshot {
                    // Keep the existing RuntimeAssembly alive; the release
                    // receipt is the terminal boundary and later bootstrap
                    // reads the current SessionRecovery bytes.
                    if runtime == nil {
                        restartAfterTransfer()
                    } else {
                        if receipt.phase == .released, let currentRuntime = runtime,
                           !(await currentRuntime.captureCurrentRecoverySnapshotAndFlush()) {
                            setTransferPhase(.transferBlocked(.storageUnavailable))
                            return
                        }
                        setTransferPhase(.ordinaryStartup)
                    }
                } else {
                    setTransferPhase(.exportLocked(receipt))
                }
            }
        } catch let failure as TransferFailure {
            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let store = Optional(TransferExportStore(applicationSupport: support)),
               let input = try? store.readRequest(), let control = try? store.readControl(),
               let currentApp = try? GoFlySetupIdentityReader.read() {
                try? await writeReadback(store: store, control: control, currentApp: currentApp, failure: failure)
                if let receipt = try? store.readExport(),
                   [.preparing, .ready, .removalSealed].contains(receipt.phase) {
                    setTransferPhase(.exportLocked(receipt))
                } else if activeDataLease == nil {
                    setTransferPhase(.transferBlocked(failure))
                }
                _ = input
            }
        } catch {
            setTransferPhase(.transferBlocked(.storageUnavailable))
        }
    }

    private func performExport(input: TransferExportInput, control: TransferControlRequest,
                               currentApp: SetupAppIdentity, support: URL,
                               store: TransferExportStore) async {
        guard let runtime else {
            await performColdExport(input: input, control: control, currentApp: currentApp,
                                    support: support, store: store)
            return
        }
        guard activeDataLease == nil else { return }
        let priorPhase = phase
        guard runtime.movement.canExportFromMap else {
            try? await writeReadback(store: store, control: control, currentApp: currentApp, failure: .sourceBusy)
            return
        }
        guard let lease = GoFlyDataLease.acquire(runtime: runtime) else {
            try? await writeReadback(store: store, control: control, currentApp: currentApp, failure: .sourceBusy)
            setTransferPhase(priorPhase)
            return
        }

        let settings: TransferSettings
        let cutline: TransferExportCutline
        do {
            settings = try TransferSettings(
                language: GoFlyPreferences.shared.language.rawValue,
                appearance: GoFlyPreferences.shared.appearance.rawValue,
                mode: runtime.movement.presentationMode,
                roundTripEnabled: runtime.movement.route.roundTripEnabled,
                joystickSpeed: runtime.movement.joystick.speed
            )
            cutline = TransferExportCutline(draft: runtime.movement.route.draft,
                                            settings: settings, projection: runtime.projection)
        } catch {
            _ = lease.releaseAll()
            setTransferPhase(priorPhase)
            return
        }

        setTransferPhase(.transferWaiting(.export))
        var preparingCommitted = false
        do {
            let preparation = try await Task.detached(priority: .utility) {
                try store.beginPreparation(input: input, currentApp: currentApp, cutline: cutline)
            }.value
            preparingCommitted = true
            activeDataLease = lease
            if let receipt = try await Task.detached(priority: .utility, operation: {
                try store.readExport()
            }).value {
                setTransferPhase(.exportLocked(receipt))
            }

            let favorites: Data?
            if input.request.categories.contains(.favorites) {
                guard let token = lease.favorites else { throw TransferFailure.sourceBusy }
                favorites = try runtime.favorites.transferArchive(using: token)
            } else { favorites = nil }

            let imported: TransferArchiveSnapshot?
            let favoriteRoutes: TransferArchiveSnapshot?
            if input.request.categories.contains(.routes) {
                guard let importedToken = lease.imported, let favoriteToken = lease.favoriteRoutes else {
                    throw TransferFailure.sourceBusy
                }
                async let importedSnapshot = runtime.importedRoutes.transferArchive(using: importedToken)
                async let favoriteSnapshot = runtime.favoriteRoutes.transferArchive(using: favoriteToken)
                imported = try await importedSnapshot
                favoriteRoutes = try await favoriteSnapshot
            } else {
                imported = nil; favoriteRoutes = nil
            }

            let prepared = try await Task.detached(priority: .utility) {
                try store.stage(preparation: preparation, favorites: favorites,
                                importedRoutes: imported, favoriteRoutes: favoriteRoutes)
            }.value
            let receipt = try await Task.detached(priority: .utility) {
                try store.commitReady(prepared)
            }.value
            setTransferPhase(.exportLocked(receipt))
            try await writeReadback(store: store, control: control, currentApp: currentApp)
        } catch let failure as TransferFailure {
            do {
                let actual = try await Task.detached(priority: .utility, operation: {
                    try store.readExport()
                }).value
                if let actual, [.preparing, .ready, .removalSealed].contains(actual.phase) {
                    activeDataLease = lease
                    setTransferPhase(.exportLocked(actual))
                } else if !preparingCommitted {
                    _ = lease.releaseAll()
                    setTransferPhase(priorPhase)
                }
            } catch {
                activeDataLease = lease
                setTransferPhase(.transferBlocked(.commitUnknown))
            }
            try? await writeReadback(store: store, control: control, currentApp: currentApp, failure: failure)
        } catch {
            do {
                let actual = try await Task.detached(priority: .utility, operation: {
                    try store.readExport()
                }).value
                if let actual, [.preparing, .ready, .removalSealed].contains(actual.phase) {
                    activeDataLease = lease
                    setTransferPhase(.exportLocked(actual))
                } else if !preparingCommitted {
                    _ = lease.releaseAll()
                    setTransferPhase(priorPhase)
                }
            } catch {
                activeDataLease = lease
                setTransferPhase(.transferBlocked(.commitUnknown))
            }
            try? await writeReadback(store: store, control: control, currentApp: currentApp,
                                     failure: .storageUnavailable)
        }
    }

    private func performColdExport(input: TransferExportInput, control: TransferControlRequest,
                                   currentApp: SetupAppIdentity, support: URL,
                                   store: TransferExportStore) async {
        do {
            let preparation = try await Task.detached(priority: .utility) {
                try store.reopenPreparation(input: input, currentApp: currentApp)
            }.value
            let projection = try await Task.detached(priority: .utility) {
                try TransferRestoreStore(applicationSupport: support).currentProjection()
            }.value
            let favorites: Data?
            if input.request.categories.contains(.favorites) {
                favorites = try FileFavoritePlacesPersistence(directory: projection.favoritesDirectory).transferSnapshot()
                    ?? TransferArchiveCodec.emptyFavoritePlaces()
            } else { favorites = nil }
            let imported: TransferArchiveSnapshot?
            let favoriteRoutes: TransferArchiveSnapshot?
            if input.request.categories.contains(.routes) {
                imported = try await FileImportedRoutesPersistence(directory: projection.importedRoutesDirectory).transferSnapshot()
                favoriteRoutes = try await FileFavoriteRoutesPersistence(directory: projection.favoriteRoutesDirectory).transferSnapshot()
            } else { imported = nil; favoriteRoutes = nil }
            let prepared = try await Task.detached(priority: .utility) {
                try store.stage(preparation: preparation, favorites: favorites,
                                importedRoutes: imported, favoriteRoutes: favoriteRoutes)
            }.value
            let receipt = try await Task.detached(priority: .utility) {
                try store.commitReady(prepared)
            }.value
            setTransferPhase(.exportLocked(receipt))
            try await writeReadback(store: store, control: control, currentApp: currentApp)
        } catch let failure as TransferFailure {
            try? await writeReadback(store: store, control: control, currentApp: currentApp, failure: failure)
        } catch {
            try? await writeReadback(store: store, control: control, currentApp: currentApp,
                                     failure: .storageUnavailable)
        }
    }

    private func writeReadback(store: TransferExportStore, control: TransferControlRequest,
                               currentApp: SetupAppIdentity, failure: TransferFailure? = nil) async throws {
        let pid = Int32(getpid())
        try await Task.detached(priority: .utility) {
            _ = try store.writeReadback(control: control, currentApp: currentApp, pid: pid, failure: failure)
        }.value
    }
}
