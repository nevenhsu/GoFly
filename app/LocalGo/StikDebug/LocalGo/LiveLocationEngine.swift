import Foundation

/// The production adapter always uses the device developer service. There is
/// intentionally no map-only or simulated-success fallback.
final class LiveLocationEngine: LocationEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var prepared = false
    private var statusCode: Int32 = 0

    var isPrepared: Bool { lock.withLock { prepared } }
    var lastStatusCode: Int32 { lock.withLock { statusCode } }

    func invalidate() {
        lock.withLock { prepared = false }
    }

    func prepareDevice() throws {
        invalidate()
        do {
            try LocalGoPairingIdentity.verifyCurrentDevice()
        } catch {
            record(-20)
            throw EngineFailure.identity
        }
        do {
            try DevicePreparationPolicy.ensureMounted(
                isMounted: { checkMountStatus() == .mounted },
                filesReady: { DeveloperDiskImageService.filesAreReady },
                attemptMount: {
                    _ = mountDeveloperDiskImage(from: DeveloperDiskImageService.directoryURL.path)
                }
            )
        } catch DevicePreparationPolicy.Failure.filesMissing {
            record(-21)
            throw EngineFailure.diskImage
        } catch {
            record(-22)
            throw EngineFailure.diskImage
        }
        lock.withLock {
            prepared = true
            statusCode = 0
        }
    }

    func set(latitude: Double, longitude: Double) throws {
        guard isPrepared else {
            record(-10)
            throw EngineFailure.notPrepared
        }
        do {
            try LocalGoPairingIdentity.verifyCurrentDevice()
        } catch {
            invalidate()
            record(-20)
            throw EngineFailure.identity
        }
        let code = simulate_location(
            DeviceConnectionContext.targetIPAddress,
            latitude,
            longitude,
            PairingFileStore.prepareURL().path
        )
        record(code)
        guard code == 0 else { throw EngineFailure.apply }
    }

    func clear() throws {
        // Restoration must remain callable after a setup/set failure.
        do {
            try LocalGoPairingIdentity.verifyCurrentDevice()
        } catch {
            record(-20)
            throw EngineFailure.identity
        }
        let code = clear_paired_simulated_location(
            DeviceConnectionContext.targetIPAddress,
            PairingFileStore.prepareURL().path
        )
        record(code)
        guard code == 0 else { throw EngineFailure.clear }
    }

    private func record(_ code: Int32) {
        lock.withLock { statusCode = code }
    }

    private enum EngineFailure: Error {
        case notPrepared, identity, diskImage, apply, clear
    }
}
