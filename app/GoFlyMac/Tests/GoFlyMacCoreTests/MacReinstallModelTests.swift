import Foundation
import GoFlyMacCore
import Testing

private struct NoReinstallJournal: MacReinstallJournalReading {
    func readContinuation() async throws -> MacReinstallContinuation? { nil }
}

private struct FixedReinstallJournal: MacReinstallJournalReading {
    let identity: MacReinstallContinuation
    func readContinuation() async throws -> MacReinstallContinuation? { identity }
}

private struct UnreadableSetupPredecessor: MacSetupJournalReading {
    func readContinuation() async throws -> MacSetupContinuation? { throw MacSetupFailure.invalidResponse }
}

private struct CompletedReinstallStatus: MacReinstallRunning {
    func run(_ request: MacReinstallRequest) async throws -> Data {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Reinstall/empty-response.json")
        var response = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        response["requestID"] = request.requestID.uuidString.lowercased()
        response["transferID"] = request.transferID.uuidString.lowercased()
        response["deviceID"] = request.deviceID
        response["action"] = request.action.rawValue
        return try JSONSerialization.data(withJSONObject: response)
    }
}

private struct MismatchedReinstallStatus: MacReinstallRunning {
    func run(_ request: MacReinstallRequest) async throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocol": 3, "operation": "reinstall", "requestID": request.requestID.uuidString.lowercased(),
            "transferID": request.transferID.uuidString.lowercased(), "deviceID": request.deviceID,
            "action": request.action.rawValue, "status": "ok", "payload": [
                "stage": "source", "outcome": "inProgress", "canResume": true, "canAbandon": true,
                "proof": ["backupValidated": false, "sourceSealed": false, "removalConfirmed": false,
                    "installationConfirmed": false, "pairingImported": false, "supportObserved": false, "restoreCommitted": false],
                "categories": [["category": "favorites", "state": "waiting", "receiptSHA256": NSNull()]],
                "counts": NSNull()
            ]
        ])
    }
}

private actor HeldReinstallRunner: MacReinstallRunning {
    private var entered = false
    private var continuation: CheckedContinuation<Data, Error>?
    func run(_ request: MacReinstallRequest) async throws -> Data {
        entered = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func hasEntered() -> Bool { entered }
    func finish() {
        continuation?.resume(throwing: MacReinstallFailure.cancelled)
        continuation = nil
    }
}

private actor ChangingReinstallJournal: MacReinstallJournalReading {
    private var value: MacReinstallContinuation?
    init(_ value: MacReinstallContinuation? = nil) { self.value = value }
    func readContinuation() async throws -> MacReinstallContinuation? { value }
    func remove() { value = nil }
    func set(_ value: MacReinstallContinuation) { self.value = value }
}

private actor HeldReinstallProgressRunner: MacReinstallRunning {
    let journal: ChangingReinstallJournal
    private var operation: CheckedContinuation<Data, Error>?
    private var progress: CheckedContinuation<Data, Error>?
    private var operationReturned = false
    init(journal: ChangingReinstallJournal) { self.journal = journal }

    func run(_ request: MacReinstallRequest) async throws -> Data {
        if request.action == .preflight {
            let categories = (request.options?.categories ?? []).map {
                ["category": $0.rawValue, "state": "waiting", "receiptSHA256": NSNull()] as [String: Any]
            }
            return try JSONSerialization.data(withJSONObject: [
                "protocol": 3, "operation": "reinstall", "requestID": request.requestID.uuidString.lowercased(),
                "transferID": request.transferID.uuidString.lowercased(), "deviceID": request.deviceID,
                "action": "preflight", "status": "ok", "payload": [
                    "stage": "preflight", "outcome": "ready", "canResume": false, "canAbandon": false,
                    "proof": ["backupValidated": false, "sourceSealed": false, "removalConfirmed": false,
                        "installationConfirmed": false, "pairingImported": false, "supportObserved": false, "restoreCommitted": false],
                    "categories": categories, "counts": NSNull()
                ]
            ])
        }
        if request.action == .apply {
            let identity = try MacReinstallContinuation(transferID: request.transferID, deviceID: request.deviceID,
                categories: request.options?.categories ?? [])
            await journal.set(identity)
            defer { operationReturned = true }
            return try await withCheckedThrowingContinuation { operation = $0 }
        }
        return try await withCheckedThrowingContinuation { progress = $0 }
    }
    func progressEntered() -> Bool { progress != nil }
    func didReturnOperation() -> Bool { operationReturned }
    func finishOperation() { operation?.resume(throwing: MacReinstallFailure.cancelled); operation = nil }
    func finishProgress() { progress?.resume(throwing: MacReinstallFailure.cancelled); progress = nil }
}

@Suite @MainActor struct MacReinstallModelTests {
    @Test func cancellationWaitsForTheReadOnlyProgressProcessAsWell() async throws {
        let journal = ChangingReinstallJournal()
        let runner = HeldReinstallProgressRunner(journal: journal)
        let model = MacReinstallModel(runner: runner, journal: journal)
        await model.restore()
        try model.configure(deviceID: String(repeating: "a", count: 40),
            options: MacReinstallOptions(source: .project, teamID: "ABCDEFGHIJ", categories: []))
        model.preflight()
        for _ in 0..<200 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.canApply)
        model.apply()
        for _ in 0..<600 {
            if await runner.progressEntered() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await runner.progressEntered())
        model.cancel()
        await runner.finishOperation()
        for _ in 0..<200 {
            if await runner.didReturnOperation() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await runner.didReturnOperation())
        #expect(model.isBusy)
        #expect(model.cancellationRequested)
        #expect(!model.canStatus)
        await runner.finishProgress()
        for _ in 0..<200 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isBusy)
        #expect(model.hasRecordedTransaction)
        #expect(model.locksDevice)
        #expect(model.failure == .cancelled)
        #expect(model.canStatus)
    }

    @Test func reopeningReinstallKeepsTheDeviceAndBlocksOtherWorkflows() async throws {
        let identity = try MacReinstallContinuation(transferID: UUID(), deviceID: String(repeating: "a", count: 40), categories: [.routes])
        let reinstall = MacReinstallModel(runner: MismatchedReinstallStatus(), journal: FixedReinstallJournal(identity: identity))
        let setup = MacSetupModel(runner: UnavailableSetupRunner(), journal: UnreadableSetupPredecessor())
        let app = MacAppModel(live: UnavailableChecker(), setup: setup, reinstall: reinstall)
        await app.restoreSetup()
        #expect(!setup.isRestored)
        #expect(setup.failure == nil)
        #expect(app.page == .reinstall)
        #expect(app.selectedID == identity.deviceID)
        #expect(app.setupLocksDevice)
        app.navigate(.signing)
        #expect(app.page == .reinstall)
        app.switchMode(preview: true)
        #expect(!app.isPreview)
        app.openDevices(firstInstall: true)
        #expect(app.selectedID == identity.deviceID)
    }

    @Test func journalSelectionCannotBeReplacedByAResponseForOtherCategories() async throws {
        let identity = try MacReinstallContinuation(transferID: UUID(), deviceID: String(repeating: "a", count: 40), categories: [.routes])
        let model = MacReinstallModel(runner: MismatchedReinstallStatus(), journal: FixedReinstallJournal(identity: identity))
        await model.restore()
        model.status()
        for _ in 0..<200 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.continuation == identity)
        #expect(model.locksDevice)
        #expect(model.snapshot == nil)
        #expect(model.failure == .invalidResponse)
        #expect(!model.canResume)
        #expect(!model.canAbandon)
    }

    @Test func disappearingJournalCannotUnlockAnUnresolvedTransaction() async throws {
        let identity = try MacReinstallContinuation(transferID: UUID(), deviceID: String(repeating: "a", count: 40), categories: [])
        let journal = ChangingReinstallJournal(identity)
        let runner = HeldReinstallRunner()
        let model = MacReinstallModel(runner: runner, journal: journal)
        await model.restore()
        #expect(model.locksDevice)
        model.status()
        for _ in 0..<200 {
            if await runner.hasEntered() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await journal.remove()
        await runner.finish()
        for _ in 0..<200 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isBusy)
        #expect(model.locksDevice)
        #expect(model.hasRecordedTransaction)
        #expect(model.failure == .invalidResponse)
    }

    @Test func cancelKeepsAdmissionUntilTheActualRunnerReturns() async throws {
        let runner = HeldReinstallRunner()
        let model = MacReinstallModel(runner: runner, journal: NoReinstallJournal())
        await model.restore()
        let options = try MacReinstallOptions(source: .project, teamID: "ABCDEFGHIJ", categories: [.routes])
        try model.configure(deviceID: String(repeating: "a", count: 40), options: options)
        model.preflight()
        for _ in 0..<200 {
            if await runner.hasEntered() { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await runner.hasEntered())
        model.cancel()
        #expect(model.isBusy)
        #expect(model.locksDevice)
        #expect(!model.canApply)
        #expect(throws: MacReinstallFailure.invalidResponse) {
            try model.configure(deviceID: String(repeating: "b", count: 40), options: options)
        }
        model.resetSelection()
        #expect(model.continuation?.categories == [.routes])
        await runner.finish()
        for _ in 0..<200 {
            if !model.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isBusy)
        #expect(model.failure == .cancelled)
        #expect(model.snapshot == nil)
    }
}
