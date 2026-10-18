import CryptoKit
import Foundation
import XCTest
import GoFlyCore

final class ManagementCodecTests: XCTestCase {
    private let device = String(repeating: "a", count: 40)
    private let digest = String(repeating: "1", count: 64)

    func testRequestCanonicalBytesRetainRawDigestAndReceiptBindsToThem() throws {
        let request = try makeRequest()
        let expected = "{\"expectedDeviceUDID\":\"\(device)\",\"kind\":\"renew\",\"managementID\":\"11111111-1111-1111-1111-111111111111\",\"nonce\":\"22222222-2222-2222-2222-222222222222\",\"sourceActivationSHA256\":\"\(digest)\",\"sourceApp\":{\"build\":\"18\",\"bundleID\":\"com.neven.gofly\",\"executableSHA256\":\"\(digest)\",\"profileSHA256\":\"\(digest)\"},\"sourceRestoreRootSHA256\":null,\"sourceSetupID\":\"33333333-3333-3333-3333-333333333333\",\"targetApp\":{\"build\":\"19\",\"bundleID\":\"com.neven.gofly\",\"executableSHA256\":\"\(digest)\",\"profileSHA256\":\"\(digest)\"},\"targetSetupID\":\"44444444-4444-4444-4444-444444444444\",\"teamID\":\"ABCDE12345\",\"version\":1}"
        let raw = try ManagementCodec.encodeRequest(request)
        XCTAssertEqual(String(decoding: raw, as: UTF8.self), expected)

        let input = try ManagementInput(data: raw)
        XCTAssertEqual(input.request, request)
        XCTAssertEqual(input.rawRequest, raw)
        XCTAssertEqual(input.rawRequestSHA256, SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(try ManagementCodec.decodeRequest(raw), request)

        let receipt = try ManagementSourceReceipt(
            managementID: request.managementID, nonce: request.nonce,
            requestSHA256: input.rawRequestSHA256, phase: .ready, pid: 42,
            app: request.sourceApp, sourceSetupID: request.sourceSetupID,
            activationSHA256: request.sourceActivationSHA256, restoreRootSHA256: nil)
        XCTAssertNoThrow(try receipt.bound(to: input))
        XCTAssertEqual(try ManagementCodec.decodeSourceReceipt(ManagementCodec.encodeSourceReceipt(receipt)), receipt)
    }

    func testSourceBindingRejectsChangedRawRequest() throws {
        let request = try makeRequest()
        let input = try ManagementInput(data: ManagementCodec.encodeRequest(request))
        var changed = Data([0x20])
        changed.append(input.rawRequest)
        let changedInput = try ManagementInput(data: changed)
        let receipt = try ManagementSourceReceipt(
            managementID: request.managementID, nonce: request.nonce,
            requestSHA256: input.rawRequestSHA256, phase: .preparing, pid: 42,
            app: request.sourceApp, sourceSetupID: request.sourceSetupID,
            activationSHA256: request.sourceActivationSHA256, restoreRootSHA256: nil)
        XCTAssertThrowsError(try receipt.bound(to: changedInput)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
    }

    func testStrictBoundaryRejectsKeyAndScalarMutations() throws {
        let request = try makeRequest()
        let valid = String(decoding: try ManagementCodec.encodeRequest(request), as: UTF8.self)
        let mutations = [
            valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.0"),
            valid.replacingOccurrences(of: "\"version\":1", with: "\"version\":true"),
            valid.replacingOccurrences(of: "11111111-1111-1111-1111-111111111111", with: "11111111-1111-1111-1111-11111111111A"),
            valid.replacingOccurrences(of: "\"sourceActivationSHA256\":\"\(digest)\"", with: "\"sourceActivationSHA256\":\"\(String(repeating: "A", count: 64))\""),
            valid.replacingOccurrences(of: "\"sourceApp\":{", with: "\"sourceApp\":{\"extra\":true,"),
            valid.replacingOccurrences(of: "\"version\":1}", with: "\"version\":1,\"version\":1}")
        ]
        var escapedDuplicate = valid
        escapedDuplicate.removeLast()
        escapedDuplicate.append(contentsOf: ",\"\\u0076ersion\":1}")
        for mutation in mutations + [escapedDuplicate] {
            XCTAssertThrowsError(try ManagementCodec.decodeRequest(Data(mutation.utf8)), "accepted mutation: \(mutation)")
        }

        let input = try ManagementInput(data: try ManagementCodec.encodeRequest(request))
        let control = try ManagementControlCommand(managementID: request.managementID,
                                                    nonce: request.nonce,
                                                    requestSHA256: input.rawRequestSHA256,
                                                    action: .seal)
        let controlBytes = try ManagementCodec.encodeControl(control)
        XCTAssertEqual(try ManagementCodec.decodeControl(controlBytes), control)
        XCTAssertNoThrow(try control.bound(to: input))
        let controlText = String(decoding: controlBytes, as: UTF8.self)
        let controlMutations = [
            controlText.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.0"),
            controlText.replacingOccurrences(of: "\"action\":\"seal\"", with: "\"action\":\"unknown\""),
            controlText.replacingOccurrences(of: "\"version\":1}", with: "\"version\":1,\"version\":1}")
        ]
        for mutation in controlMutations {
            XCTAssertThrowsError(try ManagementCodec.decodeControl(Data(mutation.utf8)),
                                 "accepted control mutation: \(mutation)")
        }
    }

    func testRepairRequiresTheSameTargetAppAndReceiptPidIsBounded() throws {
        let source = try makeApp(build: "18")
        let target = try makeApp(build: "19")
        XCTAssertThrowsError(try ManagementRequest(
            managementID: UUID(), nonce: UUID(), kind: .repair, expectedDeviceUDID: device,
            sourceSetupID: UUID(), sourceApp: source, sourceActivationSHA256: digest,
            sourceRestoreRootSHA256: nil, teamID: "ABCDE12345", targetSetupID: UUID(), targetApp: target)) { error in
            XCTAssertEqual(error as? ManagementFailure, .identityMismatch)
        }
        XCTAssertThrowsError(try ManagementSourceReceipt(
            managementID: UUID(), nonce: UUID(), requestSHA256: digest, phase: .ready,
            pid: 0, app: source, sourceSetupID: UUID(), activationSHA256: digest,
            restoreRootSHA256: nil))
        XCTAssertNoThrow(try ManagementSourceReceipt(
            managementID: UUID(), nonce: UUID(), requestSHA256: digest, phase: .ready,
            pid: Int32.max, app: source, sourceSetupID: UUID(), activationSHA256: digest,
            restoreRootSHA256: nil))
    }

    private func makeRequest() throws -> ManagementRequest {
        try ManagementRequest(
            managementID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            nonce: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            kind: .renew, expectedDeviceUDID: device,
            sourceSetupID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            sourceApp: try makeApp(build: "18"), sourceActivationSHA256: digest,
            sourceRestoreRootSHA256: nil, teamID: "ABCDE12345",
            targetSetupID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            targetApp: try makeApp(build: "19"))
    }

    private func makeApp(build: String) throws -> SetupAppIdentity {
        try SetupAppIdentity(bundleID: SetupAppIdentity.formalBundleID, build: build,
                             profileSHA256: digest, executableSHA256: digest)
    }
}
