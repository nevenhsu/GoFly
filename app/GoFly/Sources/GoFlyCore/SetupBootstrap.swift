import Foundation

/// Data-only bootstrap boundary. It performs no native, movement, tunnel or
/// runtime construction; the App may assemble those owners only after the
/// returned result is ordinaryStartup or completed.
public final class SetupBootstrapCoordinator: @unchecked Sendable {
    private let store: SetupActivationStore
    private let pairing: any SetupPairingAccess

    public init(store: SetupActivationStore, pairing: any SetupPairingAccess) {
        self.store = store
        self.pairing = pairing
    }

    /// Launch gates bind only the bundle ID. Rebuilds change the executable
    /// hash, so binding launch to the full identity locks renew and direct
    /// Xcode installs. The full identity is read only for the Mac readback
    /// handshake, where the Mac verifies the exact installed product.
    public func prepare(bundleID: @Sendable () throws -> String,
                        identity: @Sendable () throws -> SetupAppIdentity) throws -> SetupBootstrapResult {
        do {
            let input = try store.readInput()
            let request = try store.readReadbackRequest()
            let activation = try store.activation()
            // This is deliberately checked before invoking either reader.
            // Existing installations and unsigned simulator launches have no
            // formal setup state and retain ordinary startup.
            guard input != nil || request != nil || activation != nil else { return .ordinaryStartup }

            if let input {
                let currentBundleID: String
                do { currentBundleID = try bundleID() }
                catch { return .blocked(.identityMismatch) }
                guard input.manifest.app.bundleID == currentBundleID else { return .blocked(.identityMismatch) }
                if let activation, let existing = activation.receipts.first(where: { $0.setupID == input.manifest.setupID }) {
                    guard existing.app.bundleID == currentBundleID else { return .blocked(.identityMismatch) }
                    guard existing.rawManifestSHA256 == input.rawManifestSHA256 else { return .blocked(.invalidInput) }
                    guard let activeID = activation.activeSetupID,
                          let activeReceipt = activation.receipts.first(where: { $0.setupID == activeID }) else {
                        return .blocked(.artifactMismatch)
                    }
                    guard activeReceipt.app.bundleID == currentBundleID else { return .blocked(.identityMismatch) }
                    do { _ = try store.activeSupportDirectory(method: activeReceipt.method) }
                    catch let failure as SetupFailure { return .blocked(failure) }
                    catch { return .blocked(.artifactMismatch) }
                    return .completed(existing)
                }
                // Reject a new transaction at the bounded history limit before
                // invoking any pairing preparation or observation. Identical
                // replay was handled above and remains allowed.
                if activation?.receipts.count ?? 0 >= SetupActivationRecord.maximumReceipts {
                    return .blocked(.receiptCapacity)
                }
                // The support package is validated before any pairing state is
                // consumed or written. A corrupt package must leave pairing
                // state untouched for a later retry.
                do { _ = try store.validateSupport(for: input) }
                catch let failure as SetupFailure { return .blocked(failure) }
                catch { return .blocked(.artifactMismatch) }
                try pairing.prepare()
                let firstEvidence = try pairing.observe(for: input)
                // Any malformed or mismatched v1 evidence wins over a
                // superficially verified stored pairing. A success receipt
                // cannot coexist with exact pending input.
                if firstEvidence.input == .malformedOrMismatched ||
                    firstEvidence.receipt == .rejectedOrMalformed ||
                    (firstEvidence.input == .exact && firstEvidence.receipt == .success) {
                    return .blocked(.pairingRejected)
                }
                let stored: SetupPairingObservation
                // An exact pending input is consumed once even when the first
                // stored observation is absent or invalid; the post-consume
                // observation is the evidence used for activation.
                if firstEvidence.input == .exact && firstEvidence.receipt == .absent {
                        try pairing.consumeExactPending(for: input)
                        stored = try pairing.observeStoredPairing(expectedDeviceUDID: input.manifest.expectedDeviceUDID)
                } else {
                    stored = firstEvidence.stored
                }
                guard case .verified(let device, let hash) = stored,
                      device.lowercased() == input.manifest.expectedDeviceUDID,
                      hash == input.manifest.pairingSHA256 else { return .blocked(.pairingUnknown) }
                do {
                    let receipt = try store.commit(input)
                    return .completed(receipt)
                } catch let failure as SetupFailure { return .blocked(failure) }
            }

            if let request {
                let current: SetupAppIdentity
                do { current = try identity() }
                catch { return .blocked(.identityMismatch) }
                guard request.app == current else { return .blocked(.identityMismatch) }
                if let prior = try store.readReadbackReceipt(),
                   (prior.setupID != request.setupID || prior.nonce != request.nonce ||
                    prior.expectedDeviceUDID != request.expectedDeviceUDID || prior.app != current) {
                    return .blocked(.identityMismatch)
                }
                try pairing.prepare()
                let observed = try pairing.observeStoredPairing(expectedDeviceUDID: request.expectedDeviceUDID)
                let receipt = try SetupReadbackReceipt(setupID: request.setupID, nonce: request.nonce,
                                                       expectedDeviceUDID: request.expectedDeviceUDID,
                                                       app: current, pairing: observed)
                try store.writeReadbackReceipt(receipt)
                return .waitingForMac(request)
            }

            if let activation, let active = activation.activeSetupID,
               let receipt = activation.receipts.first(where: { $0.setupID == active }) {
                let currentBundleID: String
                do { currentBundleID = try bundleID() }
                catch { return .blocked(.identityMismatch) }
                guard receipt.app.bundleID == currentBundleID else { return .blocked(.identityMismatch) }
                do { _ = try store.activeSupportDirectory(method: receipt.method) }
                catch let failure as SetupFailure { return .blocked(failure) }
                catch { return .blocked(.artifactMismatch) }
                return .completed(receipt)
            }
            return .blocked(.invalidInput)
        } catch let failure as SetupFailure {
            return .blocked(failure)
        } catch {
            return .blocked(.storageUnavailable)
        }
    }

}
