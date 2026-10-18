import Foundation
import Testing
import GoFlyMacCore

@Suite
struct MacManagementProtocolTests {
    private let device = "00008110-001234567890abcd"
    private let profile = String(repeating: "a", count: 64)
    private let executable = String(repeating: "b", count: 64)

    @Test
    func requestUsesProtocolFiveAndRejectsLooseFields() throws {
        let options = try MacManagementOptions(source: .project, teamID: "ABCDE12345")
        let request = try MacManagementRequest(
            action: .apply, managementID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            deviceID: device.uppercased(), selectionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .renew, transport: .usb, connectionRevision: 0, options: options,
            requestID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        let wire = try request.encoded()
        let object = try #require(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        #expect(object["protocol"] as? Int == 5)
        #expect(object["transport"] as? String == "USB")
        #expect(object["deviceID"] as? String == device)
        #expect((object["options"] as? [String: Any])?["artifactPath"] is NSNull)
        #expect(throws: MacManagementFailure.invalidRequest) {
            try MacManagementOptions(source: .signedApp, artifactPath: "/tmp/../GoFly.app",
                                     teamID: "ABCDE12345")
        }
        #expect(throws: MacManagementFailure.invalidRequest) {
            try MacManagementRequest(action: .apply, managementID: UUID(), deviceID: device,
                                     selectionID: UUID(), kind: .renew, transport: .usb,
                                     connectionRevision: 1, options: options)
        }
    }

    @Test
    func completeReceiptBindsToRequestAndSafeErrorsDoNotLeakPayload() throws {
        let request = try MacManagementRequest(
            action: .query, managementID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            deviceID: device, selectionID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .renew, transport: .usb, connectionRevision: 2,
            requestID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        let sourceApp = try MacManagementAppIdentity(bundleID: "com.neven.gofly", build: "19",
                                                      profileSHA256: profile, executableSHA256: executable)
        let targetApp = try MacManagementAppIdentity(bundleID: "com.neven.gofly", build: "20",
                                                      profileSHA256: profile, executableSHA256: executable)
        let receipt = try MacManagementAdoptionReceipt(
            managementID: request.managementID, nonce: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            requestSHA256: String(repeating: "c", count: 64),
            sourceSetupID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            targetSetupID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            sourceApp: sourceApp, targetApp: targetApp, expectedDeviceUDID: device,
            teamID: "ABCDE12345", sourceActivationSHA256: String(repeating: "d", count: 64),
            sourceRestoreRootSHA256: nil, targetActivationSHA256: String(repeating: "e", count: 64))
        let proof = MacManagementProof(sourceBound: true, sourceQuiescent: true, mutationSealed: true,
                                       updateConfirmed: true, pairingImported: true,
                                       supportObserved: true, adoptionCommitted: true)
        let payload = try MacManagementPayload(
            stage: .complete, outcome: .confirmed, canResume: false, canRelease: false,
            sourceAdmission: .live, connectionRevision: 2, currentTransport: .network,
            proof: proof, app: targetApp, teamID: "ABCDE12345",
            expiresAt: "2026-10-25T00:00:00Z", adoptionReceipt: receipt, request: request)
        let response = try encodeResponse(payload, for: request)
        let decoded = try MacManagementResponseDecoder.decode(response, for: request)
        #expect(decoded.isComplete)
        #expect(decoded.adoptionReceipt?.canonicalSHA256 == decoded.adoptionReceipt?.receiptSHA256)
        let waiting = try MacManagementPayload(stage: .source, outcome: .unknown, canResume: true, canRelease: true,
            sourceAdmission: .live, connectionRevision: 2, currentTransport: .network,
            proof: MacManagementProof(sourceBound: true, sourceQuiescent: false, mutationSealed: false,
                updateConfirmed: false, pairingImported: false, supportObserved: false, adoptionCommitted: false),
            app: nil, teamID: nil, expiresAt: nil, adoptionReceipt: nil, request: request)
        #expect(try MacManagementResponseDecoder.decode(encodeResponse(waiting, for: request), for: request).canRelease)

        let error = try errorResponse(for: request, code: "source-busy")
        #expect(throws: MacManagementFailure.service("source-busy")) {
            try MacManagementResponseDecoder.decode(error, for: request)
        }
        let malformedWire = String(decoding: response, as: UTF8.self)
            .replacingOccurrences(of: "\"connectionRevision\":2", with: "\"connectionRevision\":2.0")
        #expect(throws: MacManagementFailure.invalidResponse) {
            try MacManagementResponseDecoder.decode(Data(malformedWire.utf8), for: request)
        }
    }
}
