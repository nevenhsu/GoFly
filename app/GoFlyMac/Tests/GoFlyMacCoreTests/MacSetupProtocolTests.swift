import Foundation
import Testing
import GoFlyMacCore

@Suite struct MacSetupProtocolTests {
    private let device = "00008110-001234567890abcd"

    @Test func projectRequestContainsTheClosedWireIdentityAndExplicitNullArtifact() throws {
        let options = try MacSetupOptions(source: .project, teamID: "ABCDE12345")
        let id = UUID()
        let request = try MacSetupRequest(action: .preflight, setupID: id, deviceID: device, options: options)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(Set(object.keys) == ["protocol", "operation", "requestID", "setupID", "deviceID", "action", "options"])
        #expect(object["protocol"] as? Int == 2)
        #expect(object["operation"] as? String == "setup")
        #expect(object["setupID"] as? String == id.uuidString)
        let encodedOptions = try #require(object["options"] as? [String: Any])
        #expect(encodedOptions["artifactPath"] is NSNull)
        #expect(encodedOptions["allowProvisioningUpdates"] as? Bool == false)
    }

    @Test func invalidAuthorityCannotBecomeARequest() throws {
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupOptions(source: .project, teamID: "")
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupOptions(source: .project, artifactPath: "/tmp/GoFly.app", teamID: "ABCDE12345")
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupOptions(source: .signedApp, artifactPath: "/tmp/GoFly.app", teamID: "ABCDE12345",
                                allowProvisioningUpdates: true)
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupOptions(source: .signedApp, artifactPath: "relative.app", teamID: "ABCDE12345")
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupRequest(action: .apply, setupID: UUID(), deviceID: device)
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupRequest(action: .status, setupID: UUID(), deviceID: "other")
        }
        let options = try MacSetupOptions(source: .project, teamID: "ABCDE12345")
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupRequest(action: .resume, setupID: UUID(), deviceID: device, options: options)
        }
    }

    @Test func matchingCompleteReceiptCanFinishButPartialEvidenceCannot() throws {
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        let snapshot = try MacSetupResponseDecoder.decode(response(for: request), for: request)
        #expect(snapshot.isComplete)
        #expect(snapshot.appBuild == "19")
        var partial = payload()
        partial["stage"] = "handoff"
        partial["outcome"] = "unknown"
        partial["proof"] = ["installationConfirmed": true, "pairingImported": false, "supportObserved": true]
        let unknown = try MacSetupResponseDecoder.decode(response(for: request, payload: partial), for: request)
        #expect(!unknown.isComplete)
        #expect(unknown.outcome == .unknown)
    }

    @Test func staleForeignOrMalformedResponsesCannotFinish() throws {
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        let other = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: other), for: request)
        }
        var noProof = payload()
        noProof.removeValue(forKey: "proof")
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: request, payload: noProof), for: request)
        }
        var extra = payload()
        extra["vpnConnected"] = true
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: request, payload: extra), for: request)
        }
        for bytes in [Data(), Data("{}{}".utf8), Data(repeating: 65, count: 262_145)] {
            #expect(throws: MacSetupFailure.invalidResponse) {
                try MacSetupResponseDecoder.decode(bytes, for: request)
            }
        }
    }

    @Test func duplicateEscapedKeysAndCoercedProtocolCannotCreateCompletion() throws {
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        let valid = String(decoding: try response(for: request), as: UTF8.self)
        let invalid = [
            "{\"protocol\":1," + valid.dropFirst(),
            "{\"\\u0070rotocol\":2," + valid.dropFirst(),
            valid.replacingOccurrences(of: "\"proof\":{", with: "\"proof\":{\"supportObserved\":false,"),
            valid.replacingOccurrences(of: "\"supportObserved\":true", with: "\"supportObserved\":true,\"supportObserved\":false"),
            valid.replacingOccurrences(of: "\"protocol\":2", with: "\"protocol\":2.0")
        ]
        for wire in invalid {
            #expect(throws: MacSetupFailure.invalidResponse) {
                try MacSetupResponseDecoder.decode(Data(wire.utf8), for: request)
            }
        }
    }

    @Test func actualErrorRetainsItsUnknownStageWithoutLeakingArbitraryDiagnostics() throws {
        let request = try MacSetupRequest(action: .resume, setupID: UUID(), deviceID: device)
        var progress = payload()
        progress["stage"] = "install"
        progress["outcome"] = "unknown"
        progress["canResume"] = true
        progress["proof"] = ["installationConfirmed": false, "pairingImported": false, "supportObserved": false]
        var root = try #require(JSONSerialization.jsonObject(with: response(for: request, payload: progress)) as? [String: Any])
        root["status"] = "error"
        root["code"] = "transaction-unknown"
        let unknown = try MacSetupResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request)
        #expect(unknown.outcome == .unknown)
        #expect(unknown.stage == .install)
        #expect(!unknown.isComplete)
        #expect(unknown.failure == .service("transaction-unknown"))
        root["code"] = "untrusted diagnostic text"
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request)
        }
    }

    @Test func readOnlyPreflightCannotReportAnInstallCompletion() throws {
        let request = try MacSetupRequest(action: .preflight, setupID: UUID(), deviceID: device,
                                         options: MacSetupOptions(source: .project, teamID: "ABCDE12345"))
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: request), for: request)
        }
        let ready: [String: Any] = [
            "stage": "preflight", "outcome": "ready", "canResume": false,
            "proof": ["installationConfirmed": false, "pairingImported": false, "supportObserved": false]
        ]
        let checked = try MacSetupResponseDecoder.decode(response(for: request, payload: ready), for: request)
        #expect(!checked.isComplete)
        #expect(checked.stage == .preflight)
        #expect(checked.outcome == .ready)
    }

    @Test func completeStageUnknownAndSafeErrorRemainResumableWithoutCompletion() throws {
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        var progress = payload()
        progress["outcome"] = "unknown"
        progress["canResume"] = true
        progress.removeValue(forKey: "receiptSHA256")
        for isError in [false, true] {
            var root = try #require(JSONSerialization.jsonObject(with: response(for: request, payload: progress)) as? [String: Any])
            if isError { root["status"] = "error"; root["code"] = "commit-unknown" }
            let snapshot = try MacSetupResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request)
            #expect(snapshot.stage == .complete)
            #expect(snapshot.outcome == .unknown)
            #expect(snapshot.canResume)
            #expect(!snapshot.isComplete)
            #expect(snapshot.errorCode == (isError ? "commit-unknown" : nil))
        }
        var confirmedError = try #require(JSONSerialization.jsonObject(with: response(for: request)) as? [String: Any])
        confirmedError["status"] = "error"
        confirmedError["code"] = "busy"
        let snapshot = try MacSetupResponseDecoder.decode(JSONSerialization.data(withJSONObject: confirmedError), for: request)
        #expect(snapshot.outcome == .confirmed)
        #expect(snapshot.errorCode == "busy")
        #expect(!snapshot.isComplete)
    }

    @Test func identityAndDigestFieldsRejectControlSuffixes() throws {
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupOptions(source: .project, teamID: "ABCDE12345\n")
        }
        #expect(throws: MacSetupFailure.invalidRequest) {
            try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device + "\n")
        }
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        for key in ["teamID", "receiptSHA256"] {
            var bad = payload()
            bad[key] = try #require(bad[key] as? String) + "\n"
            #expect(throws: MacSetupFailure.invalidResponse) {
                try MacSetupResponseDecoder.decode(response(for: request, payload: bad), for: request)
            }
        }
        var bad = payload()
        var app = try #require(bad["app"] as? [String: Any])
        app["profileSHA256"] = String(repeating: "a", count: 64) + "\n"
        bad["app"] = app
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: request, payload: bad), for: request)
        }
    }

    @Test func appBuildUsesTheSharedOneHundredTwentyEightByteLimit() throws {
        let request = try MacSetupRequest(action: .status, setupID: UUID(), deviceID: device)
        var value = payload()
        var app = try #require(value["app"] as? [String: Any])
        app["build"] = String(repeating: "b", count: 128)
        value["app"] = app
        let snapshot = try MacSetupResponseDecoder.decode(response(for: request, payload: value), for: request)
        #expect(snapshot.appBuild?.utf8.count == 128)
        app["build"] = String(repeating: "b", count: 129)
        value["app"] = app
        #expect(throws: MacSetupFailure.invalidResponse) {
            try MacSetupResponseDecoder.decode(response(for: request, payload: value), for: request)
        }
    }

    private func payload() -> [String: Any] {
        ["stage": "complete", "outcome": "confirmed", "canResume": false,
         "app": ["bundleID": "com.neven.gofly", "build": "19",
                 "profileSHA256": String(repeating: "a", count: 64),
                 "executableSHA256": String(repeating: "b", count: 64)],
         "teamID": "ABCDE12345", "expiresAt": "2026-10-25T00:00:00Z",
         "receiptSHA256": String(repeating: "c", count: 64),
         "proof": ["installationConfirmed": true, "pairingImported": true, "supportObserved": true]]
    }

    private func response(for request: MacSetupRequest, payload: [String: Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocol": 2, "operation": "setup", "action": request.action.rawValue,
            "requestID": request.requestID.uuidString, "setupID": request.setupID.uuidString,
            "deviceID": request.deviceID, "status": "ok", "payload": payload ?? self.payload()
        ])
    }
}
