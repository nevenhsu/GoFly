import Foundation
import Testing
import GoFlyMacCore

@Suite struct MacSetupJournalTests {
    private let device = "00008110-001234567890abcd"

    @Test func absentJournalIsReadOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(try await MacSetupJournalReader(stateRoot: root).readContinuation() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func actualJournalRecoversOnlyOriginalTransactionAndDevice() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try write(header(id: id), to: root)
        let continuation = try #require(await MacSetupJournalReader(stateRoot: root).readContinuation())
        #expect(continuation.setupID == id)
        #expect(continuation.deviceID == device)
    }

    @Test func malformedVersionDuplicateAndForeignOperationStayBlocked() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = String(decoding: try header(), as: UTF8.self)
        for bad in [
            Data(good.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.0").utf8),
            Data(("{\"version\":1," + good.dropFirst()).utf8),
            Data(good.replacingOccurrences(of: "\"setup\"", with: "\"reinstall\"").utf8),
            Data("{\"version\":1,\"operation\":\"setup\",\"setupID\":\"\(UUID().uuidString)\",\"deviceID\":\"\(device)\",\"stages\":NaN}".utf8),
            Data("{".utf8), Data(repeating: 65, count: 262_145)
        ] {
            try write(bad, to: root)
            do {
                _ = try await MacSetupJournalReader(stateRoot: root).readContinuation()
                Issue.record("An unsafe journal cannot be treated as no transaction")
            } catch { #expect(error as? MacSetupFailure == .invalidResponse) }
        }
    }

    @Test func symlinkAndPubliclyReadableStateAreRejected() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("other.json")
        try header().write(to: external)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: external.path)
        let journal = root.appendingPathComponent("journal.json")
        try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: external)
        do {
            _ = try await MacSetupJournalReader(stateRoot: root).readContinuation()
            Issue.record("A journal symlink must be rejected")
        } catch { #expect(error as? MacSetupFailure == .invalidResponse) }
        try FileManager.default.removeItem(at: journal)
        try write(header(), to: root)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: journal.path)
        do {
            _ = try await MacSetupJournalReader(stateRoot: root).readContinuation()
            Issue.record("A nonprivate journal must be rejected")
        } catch { #expect(error as? MacSetupFailure == .invalidResponse) }
    }

    @Test func exactPrivateModesAreRequiredWithoutRepairingPermissions() async throws {
        let root = try directory()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root) }
        try write(header(), to: root)
        let journal = root.appendingPathComponent("journal.json")
        for (path, mode) in [(root, 0o500), (journal, 0o700)] {
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path.path)
            do {
                _ = try await MacSetupJournalReader(stateRoot: root).readContinuation()
                Issue.record("Noncanonical private state must stay blocked")
            } catch { #expect(error as? MacSetupFailure == .invalidResponse) }
            let observed = try #require(FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)
            #expect(observed.intValue == mode)
            try FileManager.default.setAttributes([.posixPermissions: path == root ? 0o700 : 0o600], ofItemAtPath: path.path)
        }
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return root
    }

    private func header(id: UUID = UUID()) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "version": 1, "operation": "setup", "setupID": id.uuidString.lowercased(), "deviceID": device,
            "stages": ["install": ["outcome": "unknown"]]
        ])
    }

    private func write(_ data: Data, to root: URL) throws {
        let path = root.appendingPathComponent("journal.json")
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}
