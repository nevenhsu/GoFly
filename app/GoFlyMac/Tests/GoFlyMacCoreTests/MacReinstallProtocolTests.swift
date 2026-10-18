import Foundation
import Testing
import GoFlyMacCore

@Suite struct MacReinstallProtocolTests {
    let device = "00008110-001234567890abcd"
    @Test func allEightSelectionsEncodeExplicitClosedAuthority() throws {
        for bits in 0..<8 {
            let categories = MacReinstallCategory.allCases.enumerated().compactMap { index, item in bits & (1 << index) != 0 ? item : nil }
            let options = try MacReinstallOptions(source: .project, teamID: "ABCDE12345", categories: categories)
            let request = try MacReinstallRequest(action: .apply, transferID: UUID(), deviceID: device, options: options)
            let root = try #require(JSONSerialization.jsonObject(with: request.encoded()) as? [String: Any])
            #expect(Set(root.keys) == ["protocol", "requestID", "operation", "action", "transferID", "deviceID", "options"])
            #expect(root["requestID"] as? String == request.requestID.uuidString.lowercased())
            #expect(root["transferID"] as? String == request.transferID.uuidString.lowercased())
            let encoded = try #require(root["options"] as? [String: Any])
            #expect(encoded["categories"] as? [String] == categories.map(\.rawValue))
            #expect(encoded["artifactPath"] is NSNull)
            #expect(encoded["allowProvisioningUpdates"] as? Bool == false)
        }
    }
    @Test func invalidOptionsOrChangedResumeAuthorityAreRejected() throws {
        for categories: [MacReinstallCategory] in [[.routes, .favorites], [.routes, .routes]] {
            #expect(throws: MacReinstallFailure.invalidRequest) {
                try MacReinstallOptions(source: .project, teamID: "ABCDE12345", categories: categories)
            }
        }
        let options = try MacReinstallOptions(source: .project, teamID: "ABCDE12345", categories: [])
        #expect(throws: MacReinstallFailure.invalidRequest) {
            try MacReinstallRequest(action: .resume, transferID: UUID(), deviceID: device, options: options)
        }
        #expect(throws: MacReinstallFailure.invalidRequest) {
            try MacReinstallRequest(action: .apply, transferID: UUID(), deviceID: device)
        }
        #expect(throws: MacReinstallFailure.invalidRequest) {
            try MacReinstallRequest(action: .status, transferID: UUID(), deviceID: device.uppercased())
        }
    }
    @Test func completeDataEnvelopeRequiresJointProofAndEverySelectedCategory() throws {
        let request = try request()
        let value = try MacReinstallResponseDecoder.decode(response(request), for: request, selectedCategories: [.favorites])
        #expect(value.isComplete)
        #expect(value.counts?.favorites == 2)
        for key in proof().keys {
            var payload = payload(); var partial = proof(); partial[key] = false; payload["proof"] = partial
            #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(response(request, payload), for: request, selectedCategories: [.favorites]) }
        }
        var pending = payload(); pending["categories"] = [["category":"favorites", "state":"waiting", "receiptSHA256":NSNull()]]
        #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(response(request, pending), for: request, selectedCategories: [.favorites]) }
    }
    @Test func omittedOrForeignSelectionCannotCreateCompletion() throws {
        let request = try request()
        #expect(throws: MacReinstallFailure.invalidResponse) {
            try MacReinstallResponseDecoder.decode(response(request), for: request, selectedCategories: [.routes])
        }
        var empty = payload(); empty["categories"] = []; empty["counts"] = ["favorites":0,"importedRoutes":0,"favoriteRoutes":0,"draftNodes":0,"gpxPoints":0]
        #expect(throws: MacReinstallFailure.invalidResponse) {
            try MacReinstallResponseDecoder.decode(response(request, empty), for: request, selectedCategories: [.favorites])
        }
    }
    @Test func incompleteInstallAndAbandonCannotBeComplete() throws {
        let request = try request()
        var unknown = payload(); unknown["stage"] = "install"; unknown["outcome"] = "unknown"; unknown["canResume"] = true
        var proofs = proof(); proofs["installationConfirmed"] = false; proofs["restoreCommitted"] = false; unknown["proof"] = proofs
        let value = try MacReinstallResponseDecoder.decode(response(request, unknown), for: request, selectedCategories: [.favorites])
        #expect(!value.isComplete); #expect(!value.canAbandon)
        var abandoned = payload(); abandoned["stage"] = "abandon"; abandoned["proof"] = proof(false)
        let closed = try MacReinstallResponseDecoder.decode(response(request, abandoned), for: request, selectedCategories: [.favorites])
        #expect(closed.isAbandoned); #expect(!closed.isComplete)
    }
    @Test func duplicateEscapedKeysAndLexicalCountsReject() throws {
        let request = try request(); let raw = String(decoding: try response(request), as: UTF8.self)
        let invalid = [
            "{\"\\u0070rotocol\":3," + raw.dropFirst(),
            raw.replacingOccurrences(of: "\"protocol\":3", with: "\"protocol\":3.0"),
            raw.replacingOccurrences(of: "\"favorites\":2", with: "\"favorites\":2.0"),
            raw.replacingOccurrences(of: "\"favorites\":2", with: "\"favorites\":2e0"),
            raw.replacingOccurrences(of: "\"favorites\":2", with: "\"favorites\":true"),
            raw.replacingOccurrences(of: "\"favorites\":2", with: "\"favorites\":2,\"favorites\":2")
        ]
        for wire in invalid {
            #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(Data(wire.utf8), for: request, selectedCategories: [.favorites]) }
        }
    }
    @Test func staleForeignUnknownOrOversizeCannotFinish() throws {
        let request = try request()
        let foreign = try self.request()
        #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(response(foreign), for: request, selectedCategories: [.favorites]) }
        for path in ["requestID", "transferID", "deviceID", "action", "operation"] {
            var root = try #require(JSONSerialization.jsonObject(with: response(request)) as? [String: Any]); root[path] = "other"
            #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request, selectedCategories: [.favorites]) }
        }
        var extra = payload(); extra["gpsReady"] = true
        #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(response(request, extra), for: request, selectedCategories: [.favorites]) }
        for bytes in [Data(), Data("{}{}".utf8), Data(repeating: 65, count: 262145)] {
            #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(bytes, for: request, selectedCategories: [.favorites]) }
        }
    }
    @Test func categoryCountsAndActualErrorAreBounded() throws {
        let request = try request()
        for count in [-1, 101] {
            var value = payload(); value["counts"] = ["favorites":count,"importedRoutes":0,"favoriteRoutes":0,"draftNodes":0,"gpxPoints":0]
            #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(response(request, value), for: request, selectedCategories: [.favorites]) }
        }
        var value = payload(); value["stage"] = "backup"; value["outcome"] = "failed"; value["proof"] = proof(false)
        var root = try #require(JSONSerialization.jsonObject(with: response(request, value)) as? [String: Any]); root["status"] = "error"; root["code"] = "backup-invalid"
        let actual = try MacReinstallResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request, selectedCategories: [.favorites])
        #expect(actual.errorCode == "backup-invalid"); #expect(!actual.isComplete)
        root["code"] = "raw secret subprocess stderr"
        #expect(throws: MacReinstallFailure.invalidResponse) { try MacReinstallResponseDecoder.decode(JSONSerialization.data(withJSONObject: root), for: request, selectedCategories: [.favorites]) }
    }
    @Test func actualPythonProducerFixturesMatchSwiftRequestAndResponse() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Reinstall")
        for name in ["all", "empty"] {
            let raw = try Data(contentsOf: directory.appendingPathComponent(name + "-request.json"))
            let object = try #require(JSONSerialization.jsonObject(with: raw) as? [String:Any])
            let values = try #require(object["options"] as? [String:Any])
            let names = try #require(values["categories"] as? [String])
            let categories = try names.map { try #require(MacReinstallCategory(rawValue: $0)) }
            let team = try #require(values["teamID"] as? String)
            let requestID = try #require((object["requestID"] as? String).flatMap(UUID.init(uuidString:)))
            let transferID = try #require((object["transferID"] as? String).flatMap(UUID.init(uuidString:)))
            let deviceID = try #require(object["deviceID"] as? String)
            let request = try MacReinstallRequest(action: .apply, transferID: transferID, deviceID: deviceID,
                options: MacReinstallOptions(source: .project, teamID: team, categories: categories), requestID: requestID)
            #expect(try request.encoded() == raw)
            let response = try Data(contentsOf: directory.appendingPathComponent(name + "-response.json"))
            let result = try MacReinstallResponseDecoder.decode(response, for: request, selectedCategories: categories)
            #expect(result.isComplete)
            #expect(result.categories.map(\.category) == categories)
            #expect(result.expiresAt == "2026-10-22T00:00:00.123Z")
        }
    }
    @Test func optionalValuesPathsAndUnicodeFormatBuildsUseClosedWireRules() throws {
        for path in ["/Go\0Fly.app", "/" + String(repeating: "x", count: 4_096) + ".app"] {
            #expect(throws: MacReinstallFailure.invalidRequest) {
                try MacReinstallOptions(source: .signedApp, artifactPath: path, teamID: "ABCDE12345", categories: [])
            }
        }
        let request = try request()
        for key in ["app", "teamID", "expiresAt", "receiptSHA256"] {
            var value = payload()
            value[key] = NSNull()
            #expect(throws: MacReinstallFailure.invalidResponse) {
                try MacReinstallResponseDecoder.decode(response(request, value), for: request, selectedCategories: [.favorites])
            }
        }
        // Unicode's format category is an independent specification of the
        // prohibited characters; do not assume Foundation omits it.
        let formatScalars = (UInt32(0)...UInt32(0x10ffff)).compactMap(Unicode.Scalar.init)
            .filter { $0.properties.generalCategory == .format }
        #expect(!formatScalars.isEmpty)
        for scalar in formatScalars {
            var value = payload()
            value["app"] = ["bundleID": "com.neven.gofly", "build": "20" + String(scalar),
                            "profileSHA256": String(repeating: "a", count: 64),
                            "executableSHA256": String(repeating: "b", count: 64)]
            #expect(throws: MacReinstallFailure.invalidResponse) {
                try MacReinstallResponseDecoder.decode(response(request, value), for: request, selectedCategories: [.favorites])
            }
        }
    }
    private func request() throws -> MacReinstallRequest { try MacReinstallRequest(action: .status, transferID: UUID(), deviceID: device) }
    private func proof(_ value: Bool = true) -> [String:Bool] {
        Dictionary(uniqueKeysWithValues: ["backupValidated","sourceSealed","removalConfirmed","installationConfirmed","pairingImported","supportObserved","restoreCommitted"].map { ($0,value) })
    }
    private func payload() -> [String:Any] {
        ["stage":"complete","outcome":"confirmed","canResume":false,"canAbandon":false,"proof":proof(),
         "categories":[["category":"favorites","state":"committed","receiptSHA256":String(repeating:"a",count:64)]],
         "counts":["favorites":2,"importedRoutes":0,"favoriteRoutes":0,"draftNodes":0,"gpxPoints":0],
         "receiptSHA256":String(repeating:"b",count:64)]
    }
    private func response(_ request: MacReinstallRequest, _ value: [String:Any]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["protocol":3,"operation":"reinstall","requestID":request.requestID.uuidString.lowercased(),
            "action":request.action.rawValue,"transferID":request.transferID.uuidString.lowercased(),"deviceID":request.deviceID,"status":"ok","payload":value ?? payload()], options:[.sortedKeys,.withoutEscapingSlashes])
    }
}
