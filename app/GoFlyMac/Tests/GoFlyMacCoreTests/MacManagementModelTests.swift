import Foundation
import Testing
import GoFlyMacCore

private actor AutomaticFlowRunner: MacManagementRunning {
    private(set) var actions: [MacManagementAction] = []

    func run(_ request: MacManagementRequest) async throws -> Data {
        actions.append(request.action)
        if request.action == .preflight {
            let proof = MacManagementProof(sourceBound: false, sourceQuiescent: false,
                                            mutationSealed: false, updateConfirmed: false,
                                            pairingImported: false, supportObserved: false,
                                            adoptionCommitted: false)
            let payload = try MacManagementPayload(
                stage: .preflight, outcome: .ready, canResume: false, canRelease: false,
                sourceAdmission: nil, connectionRevision: request.connectionRevision,
                currentTransport: request.transport, proof: proof, app: nil, teamID: nil,
                expiresAt: nil, adoptionReceipt: nil, request: request)
            return try encodeResponse(payload, for: request)
        }
        return try errorResponse(for: request, code: "environment-not-ready")
    }
}

private actor AutomaticFlowJournal: MacManagementJournalReading {
    private var consumed: MacManagementContinuation?
    private(set) var lookupCount = 0

    func readContinuation() async throws -> MacManagementContinuation? { nil }

    func findSelection(_ selectionID: UUID) async throws -> MacManagementContinuation? {
        lookupCount += 1
        return consumed
    }

    func record(_ continuation: MacManagementContinuation) {
        consumed = continuation
    }
}

@Suite
struct MacManagementModelTests {
    @Test
    func privateJournalReopensAndAssociatesSameRevisionSelection() async throws {
        let root = URL(fileURLWithPath: "/private/tmp")
            .appendingPathComponent("gofly-management-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }

        let managementID = "11111111-1111-4111-8111-111111111111"
        let initialSelection = "22222222-2222-4222-8222-222222222222"
        let resumedSelection = "33333333-3333-4333-8333-333333333333"
        let header: [String: Any] = [
            "managementID": managementID,
            "nonce": "44444444-4444-4444-8444-444444444444",
            "targetSetupID": "55555555-5555-4555-8555-555555555555",
            "setupNonce": "66666666-6666-4666-8666-666666666666",
            "deviceID": "00008110-001234567890abcd",
            "selectionID": initialSelection,
            "kind": "repair",
            "transport": "USB",
            "options": NSNull()
        ]
        let journal: [String: Any] = [
            "version": 1, "operation": "management", "header": header,
            "revisions": [[
                "number": 0, "selectionID": initialSelection, "transport": "USB",
                "previous": NSNull(), "resolvedThroughSHA256": NSNull()
            ]],
            "selections": [
                ["selectionID": initialSelection, "revision": 0],
                ["selectionID": resumedSelection, "revision": 0]
            ],
            "stages": [:], "evidence": [:], "outcome": "inProgress", "errorCode": NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys])
        let path = root.appendingPathComponent("management-journal.json")
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)

        let reader = MacManagementJournalReader(stateRoot: root)
        let continuation = try await reader.readContinuation()
        #expect(continuation?.managementID == UUID(uuidString: managementID))
        #expect(continuation?.connectionRevision == 0)
        #expect(continuation?.currentTransport == .usb)
        let associated = try await reader.findSelection(UUID(uuidString: resumedSelection)!)
        #expect(associated == continuation)
    }

    @Test
    func automaticRenewRunsPreflightThenBlocksConsumedSelectionAfterApplyRejection() async throws {
        let runner = AutomaticFlowRunner()
        let journal = AutomaticFlowJournal()
        let model = await MacManagementModel(runner: runner, journal: journal)
        await model.restore()

        let selection = MacManagementSelection(
            selectionID: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!,
            transport: .usb)
        let options = try MacManagementOptions(source: .project, teamID: "ABCDE12345",
                                                allowProvisioningUpdates: false)
        let deviceID = "00008110-001234567890abcd"

        let first = Task { @MainActor in
            await model.automaticRenew(deviceID: deviceID, selection: selection, options: options)
        }
        let second = Task { @MainActor in
            await model.automaticRenew(deviceID: deviceID, selection: selection, options: options)
        }
        await first.value
        await second.value
        let firstActions = await runner.actions
        let firstFailure = await model.failure
        #expect(firstActions == [.preflight, .apply])
        #expect(firstFailure == .service("environment-not-ready"))
        #expect(await model.locksDevice == false)

        let cancelledRunner = AutomaticFlowRunner()
        let cancelled = await MacManagementModel(runner: cancelledRunner, journal: AutomaticFlowJournal())
        await cancelled.restore()
        try await MainActor.run {
            try cancelled.configure(deviceID: deviceID, kind: .renew, selection: selection, options: options)
            cancelled.preflight()
            #expect(cancelled.isBusy)
            cancelled.cancel()
            cancelled.resetSelection()
            #expect(cancelled.continuation != nil)
        }
        for _ in 0..<100 {
            if await !cancelled.isBusy { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await cancelledRunner.actions.isEmpty)
        #expect(await cancelled.isBusy == false)

        guard let continuation = await model.continuation else {
            throw MacManagementFailure.invalidResponse
        }
        await journal.record(continuation)
        await model.automaticRenew(deviceID: deviceID, selection: selection, options: options)

        let finalActions = await runner.actions
        let lookupCount = await journal.lookupCount
        let finalFailure = await model.failure
        #expect(finalActions == [.preflight, .apply])
        #expect(lookupCount == 2)
        #expect(finalFailure == .service("transaction-conflict"))
        #expect(await model.locksDevice)
    }
}
