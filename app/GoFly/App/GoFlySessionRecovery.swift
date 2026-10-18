import Foundation
import GoFlyCore

@MainActor
func goFlySessionRecoveryStore() -> SessionRecoveryStore {
    do {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        var directory = support.appendingPathComponent("SessionRecovery", isDirectory: true)
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let namespace = recoveryUITestArgument("-gofly-ui-session-store", in: arguments)
            .flatMap(UUID.init(uuidString:)) {
            directory = support.appendingPathComponent("UITests/SessionRecovery", isDirectory: true)
                .appendingPathComponent(namespace.uuidString, isDirectory: true)
            let persistence = FileSessionRecoveryPersistence(directory: directory)
            if let fixture = recoveryUITestArgument("-gofly-ui-session-fixture", in: arguments) {
                try seedRecoveryUITestArchiveIfMissing(fixture, persistence: persistence)
            }
        }
        #endif
        return SessionRecoveryStore(persistence: FileSessionRecoveryPersistence(directory: directory))
    } catch {
        return SessionRecoveryStore(persistence: UnavailableSessionRecoveryPersistence())
    }
}

/// Creates a recovery store from the already verified runtime projection.
/// Transfer projections are opaque to the App; this factory only consumes the
/// fixed directory supplied by Core and never resolves a path from wire data.
@MainActor
func goFlySessionRecoveryStore(directory: URL, allowUITestNamespace: Bool = false) -> SessionRecoveryStore {
    var resolved = directory
    #if DEBUG && targetEnvironment(simulator)
    if allowUITestNamespace,
       let namespace = recoveryUITestArgument("-gofly-ui-session-store", in: ProcessInfo.processInfo.arguments)
           .flatMap(UUID.init(uuidString:)) {
        let support = directory.deletingLastPathComponent()
        resolved = support.appendingPathComponent("UITests/SessionRecovery", isDirectory: true)
            .appendingPathComponent(namespace.uuidString, isDirectory: true)
        let persistence = FileSessionRecoveryPersistence(directory: resolved)
        if let fixture = recoveryUITestArgument("-gofly-ui-session-fixture", in: ProcessInfo.processInfo.arguments) {
            try? seedRecoveryUITestArchiveIfMissing(fixture, persistence: persistence)
        }
    }
    #endif
    return SessionRecoveryStore(persistence: FileSessionRecoveryPersistence(directory: resolved))
}

private struct UnavailableSessionRecoveryPersistence: SessionRecoveryPersistence {
    func read() throws -> Data? { throw SessionRecoveryFailure.unavailable }
    func replaceAtomically(with data: Data) throws { throw SessionRecoveryFailure.unavailable }
}

#if DEBUG && targetEnvironment(simulator)
private func recoveryUITestArgument(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

/// Data fixtures go through the actual private file adapter and production decoder.
/// They never create a native owner, acknowledge a command, or provide a GPS fix.
private func seedRecoveryUITestArchiveIfMissing(
    _ fixture: String, persistence: FileSessionRecoveryPersistence
) throws {
    let existing: Data?
    do { existing = try persistence.read() }
    catch { return } // Let the real store preserve and report the unreadable archive.
    guard existing == nil else { return }
    let data: Data
    switch fixture {
    case "corrupt":
        data = Data("An interrupted, unreadable checkpoint".utf8)
    case "unsupported":
        data = Data(#"{"schemaVersion":99}"#.utf8)
    default:
        guard let snapshot = recoveryUITestSnapshot(fixture) else { return }
        data = try SessionRecoveryCodec.encode(snapshot)
    }
    try persistence.replaceAtomically(with: data)
}

private func recoveryUITestSnapshot(_ fixture: String) -> SessionRecoverySnapshot? {
    let coordinate = GeoCoordinate(latitude: 25.033, longitude: 121.5654)!
    let destination = GeoCoordinate(latitude: 25.0478, longitude: 121.517)!
    let place = MapPlace(id: .coordinate(destination), title: "Saved destination",
                         coordinate: destination, address: "Saved address")
    let position = SessionDisplayPosition(coordinate: coordinate, source: .simulation)
    switch fixture {
    case "route":
        let draft = RouteDraft(values: [
            .place(MapPlace(id: .coordinate(coordinate), title: "Saved start", coordinate: coordinate)),
            .place(place)
        ])!
        return SessionRecoverySnapshot(
            mode: .route, draft: draft, roundTripEnabled: true, position: position,
            uncertainty: SessionMovementUncertainty(source: .route, requestedPlace: place)
        )
    case "wander":
        return SessionRecoverySnapshot(
            mode: .joystick, position: position,
            activeMovement: .wander(SessionWanderRecovery(
                target: WanderTarget(place: place), speed: .standard, history: [destination],
                lastAcknowledgedCoordinate: coordinate, lastAcknowledgedBearingDegrees: 90, state: .paused
            ))
        )
    case "manual":
        return SessionRecoverySnapshot(mode: .joystick, position: position, activeMovement: .manual)
    case "uncertainty":
        return SessionRecoverySnapshot(
            position: position, uncertainty: SessionMovementUncertainty(source: .point, requestedPlace: place)
        )
    default:
        return nil
    }
}
#endif
