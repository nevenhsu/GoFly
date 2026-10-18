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

struct GoFlyTransferCommand: Sendable, Equatable {
    let action: TransferAction
    let transferID: UUID
    let nonce: UUID

    init(_ link: TransferControlURL) {
        action = link.action
        transferID = link.transferID
        nonce = link.nonce
    }

    init(control: TransferControlRequest) {
        action = control.action
        transferID = control.transferID
        nonce = control.nonce
    }
}

extension GoFlySetupBootstrap {
    func handle(url: URL) {
        if let management = GoFlyManagementControlURL(url: url) {
            handleManagement(management)
            return
        }
        guard let link = try? TransferControlURL(url: url) else { return }
        handleTransfer(GoFlyTransferCommand(link), captured: nil, observation: nil)
    }

    func handleTransfer(_ command: GoFlyTransferCommand,
                        captured: TransferControlInput?,
                        observation: GoFlyMacCommandObservation?) {
        guard !phase.isManagementLocked else { return }
        // URL ingress has no observer snapshot. Capture the exact request and
        // control bytes before waiting for startup or a prior physical task;
        // the later body can only revalidate this immutable pairing.
        let capturedSnapshot: TransferControlInput
        if let captured {
            capturedSnapshot = captured
        } else {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let store = TransferExportStore(applicationSupport: support)
            do {
                // Normalize the supported AFC ingress permissions before the
                // strict raw-pair snapshot. Preparation is metadata-only and
                // never admits the command or acquires transfer owners.
                try store.prepareIncomingFiles()
            } catch {
                return
            }
            guard let value = try? store.readControlInput() else { return }
            capturedSnapshot = value
        }
        guard capturedSnapshot.control.action == command.action,
              capturedSnapshot.control.transferID == command.transferID,
              capturedSnapshot.control.nonce == command.nonce,
              capturedSnapshot.input.request.transferID == command.transferID,
              capturedSnapshot.input.request.nonce == command.nonce else { return }
        // A live physical export is never canceled by a duplicate URL. A
        // release/seal waits for the existing physical body to return before
        // observing the durable root.
        if command.action == .export, transferTask != nil { return }
        let prior = command.action == .export ? nil : transferTask
        let id = UUID()
        transferTaskID = id
        let startup = startupTask
        transferTask = Task { [weak self] in
            if let startup { await startup.value }
            if let prior { await prior.value }
            guard let self else { return }
            defer { self.transferDidFinish(id) }
            guard self.commandObservationIsCurrent(observation),
                  !self.phase.isManagementLocked else { return }
            await self.processTransfer(command, captured: capturedSnapshot, observation: observation)
        }
    }

    private func processTransfer(_ command: GoFlyTransferCommand,
                                 captured: TransferControlInput,
                                 observation: GoFlyMacCommandObservation?) async {
        var bodyAdmitted = false
        do {
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { return }
            let store = TransferExportStore(applicationSupport: support)
            try await Task.detached(priority: .utility, operation: {
                try store.prepareIncomingFiles()
            }).value
            let currentApp = try await Task.detached(priority: .utility, operation: {
                try GoFlySetupIdentityReader.read()
            }).value
            // This is the final bounded synchronous mailbox recheck after
            // every await and immediately before the token/phase admission.
            try store.requireCurrentControlInput(captured)
            guard commandObservationIsCurrent(observation),
                  !phase.isManagementLocked else { return }
            bodyAdmitted = true

            switch command.action {
            case .export:
                if await performExport(captured: captured, currentApp: currentApp,
                                       support: support, store: store) {
                    completedTransferControl = captured
                }
            case .seal:
                let receipt = try await Task.detached(priority: .utility) {
                    try store.seal(captured.control, currentApp: currentApp)
                }.value
                setTransferPhase(.exportLocked(receipt))
                let readback = try await writeReadback(store: store, input: captured,
                                                       currentApp: currentApp)
                if successful(readback, for: captured) { completedTransferControl = captured }
            case .release:
                let receipt = try await Task.detached(priority: .utility) {
                    try store.release(captured.control, input: captured.input, currentApp: currentApp)
                }.value
                if let lease = activeDataLease {
                    guard lease.releaseAll() else { return }
                    activeDataLease = nil
                }
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
                // Physical release and SessionRecovery handling are complete
                // before publication. A replaced mailbox must be rejected by
                // the captured-input writer without reblocking this terminal
                // release or attributing a response to the replacement.
                do {
                    let readback = try await writeReadback(store: store, input: captured,
                                                           currentApp: currentApp)
                    if successful(readback, for: captured) { completedTransferControl = captured }
                } catch {
                    // Publication remains retryable; completion is cached
                    // only after an exact durable readback succeeds.
                }
            }
        } catch let failure as TransferFailure {
            // A stale/replaced snapshot may fail the final bounded recheck;
            // it must not publish a readback or mutate the current phase.
            guard bodyAdmitted else { return }
            if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let store = Optional(TransferExportStore(applicationSupport: support)),
               let currentApp = try? GoFlySetupIdentityReader.read() {
                _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: failure)
                if let receipt = try? store.readExport(),
                   [.preparing, .ready, .removalSealed].contains(receipt.phase) {
                    setTransferPhase(.exportLocked(receipt))
                } else if activeDataLease == nil {
                    setTransferPhase(.transferBlocked(failure))
                }
            }
        } catch {
            if bodyAdmitted,
               let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
               let currentApp = try? GoFlySetupIdentityReader.read() {
                let store = TransferExportStore(applicationSupport: support)
                _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp,
                                         failure: .storageUnavailable)
                setTransferPhase(.transferBlocked(.storageUnavailable))
            }
        }
    }

    private func performExport(captured: TransferControlInput,
                               currentApp: SetupAppIdentity, support: URL,
                               store: TransferExportStore) async -> Bool {
        let input = captured.input
        guard let runtime else {
            return await performColdExport(captured: captured, currentApp: currentApp,
                                           support: support, store: store)
        }
        if activeDataLease != nil {
            // A prior export may already own the physical sources and have a
            // durable ready receipt while its publication was interrupted.
            // Retry only that exact receipt's readback; never reacquire owners
            // or treat the lease as a success cache.
            let existing: TransferExportReceipt?
            do {
                existing = try await Task.detached(priority: .utility) {
                    try store.readExport()
                }.value
            } catch {
                return false
            }
            guard let existing,
                  existing.request == input.request,
                  existing.requestSHA256 == input.rawSHA256,
                  existing.sourceApp == currentApp else { return false }
            if existing.phase == .preparing {
                guard let lease = activeDataLease else { return false }
                return await resumePreparingExport(captured: captured, currentApp: currentApp,
                                                   store: store, runtime: runtime,
                                                   lease: lease)
            }
            guard existing.phase == .ready else { return false }
            do {
                let readback = try await writeReadback(store: store, input: captured,
                                                       currentApp: currentApp)
                return successful(readback, for: captured)
            } catch {
                return false
            }
        }
        let priorPhase = phase
        guard runtime.movement.canExportFromMap else {
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: .sourceBusy)
            return false
        }
        guard let lease = GoFlyDataLease.acquire(runtime: runtime) else {
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: .sourceBusy)
            setTransferPhase(priorPhase)
            return false
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
            return false
        }

        setTransferPhase(.transferWaiting(.export))
        var preparingCommitted = false
        do {
            let preparation = try await Task.detached(priority: .utility) {
                try store.beginPreparation(input: input, currentApp: currentApp, cutline: cutline)
            }.value
            preparingCommitted = true
            activeDataLease = lease
            return await finishPreparedExport(captured: captured, currentApp: currentApp,
                                              store: store, runtime: runtime,
                                              lease: lease, preparation: preparation)
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
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: failure)
            return false
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
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp,
                                     failure: .storageUnavailable)
            return false
        }
    }

    /// Continue a preparing root with the lease that created it. A retry may
    /// finish staging after an interrupted publication, but it never reacquires
    /// owners or treats the preparing receipt as a completed export.
    private func resumePreparingExport(captured: TransferControlInput,
                                       currentApp: SetupAppIdentity,
                                       store: TransferExportStore,
                                       runtime: GoFlyRuntimeAssembly,
                                       lease: GoFlyDataLease) async -> Bool {
        let input = captured.input
        do {
            let preparation = try await Task.detached(priority: .utility) {
                try store.reopenPreparation(input: input, currentApp: currentApp)
            }.value
            return await finishPreparedExport(captured: captured, currentApp: currentApp,
                                              store: store, runtime: runtime,
                                              lease: lease, preparation: preparation)
        } catch let failure as TransferFailure {
            await recoverPreparedExportFailure(store: store, lease: lease)
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: failure)
            return false
        } catch {
            await recoverPreparedExportFailure(store: store, lease: lease)
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp,
                                     failure: .storageUnavailable)
            return false
        }
    }

    private func finishPreparedExport(captured: TransferControlInput,
                                      currentApp: SetupAppIdentity,
                                      store: TransferExportStore,
                                      runtime: GoFlyRuntimeAssembly,
                                      lease: GoFlyDataLease,
                                      preparation: TransferPreparation) async -> Bool {
        let input = captured.input
        do {
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
            let readback = try await writeReadback(store: store, input: captured, currentApp: currentApp)
            return successful(readback, for: captured)
        } catch let failure as TransferFailure {
            await recoverPreparedExportFailure(store: store, lease: lease)
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: failure)
            return false
        } catch {
            await recoverPreparedExportFailure(store: store, lease: lease)
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp,
                                     failure: .storageUnavailable)
            return false
        }
    }

    private func recoverPreparedExportFailure(store: TransferExportStore,
                                              lease: GoFlyDataLease) async {
        let actual: TransferExportReceipt?
        do {
            actual = try await Task.detached(priority: .utility, operation: {
                try store.readExport()
            }).value
        } catch {
            activeDataLease = lease
            setTransferPhase(.transferBlocked(.commitUnknown))
            return
        }
        if let actual, [.preparing, .ready, .removalSealed].contains(actual.phase) {
            activeDataLease = lease
            setTransferPhase(.exportLocked(actual))
        }
    }

    private func performColdExport(captured: TransferControlInput,
                                   currentApp: SetupAppIdentity, support: URL,
                                   store: TransferExportStore) async -> Bool {
        let input = captured.input
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
            let readback = try await writeReadback(store: store, input: captured, currentApp: currentApp)
            return successful(readback, for: captured)
        } catch let failure as TransferFailure {
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp, failure: failure)
            return false
        } catch {
            _ = try? await writeReadback(store: store, input: captured, currentApp: currentApp,
                                     failure: .storageUnavailable)
            return false
        }
    }

    private func writeReadback(store: TransferExportStore, input: TransferControlInput,
                               currentApp: SetupAppIdentity, failure: TransferFailure? = nil) async throws -> TransferReadback {
        let pid = Int32(getpid())
        return try await Task.detached(priority: .utility) {
            try store.writeReadback(input: input, currentApp: currentApp, pid: pid, failure: failure)
        }.value
    }

    private func successful(_ readback: TransferReadback, for captured: TransferControlInput) -> Bool {
        guard readback.version == 1,
              readback.commandID == captured.control.commandID,
              readback.action == captured.control.action,
              readback.transferID == captured.control.transferID,
              readback.nonce == captured.control.nonce,
              readback.requestSHA256 == captured.input.rawSHA256,
              readback.errorCode == nil else { return false }
        switch captured.control.action {
        case .export: return readback.phase == .ready
        case .seal: return readback.phase == .removalSealed
        case .release: return readback.phase == .released || readback.phase == .releasedNoSnapshot
        }
    }
}
