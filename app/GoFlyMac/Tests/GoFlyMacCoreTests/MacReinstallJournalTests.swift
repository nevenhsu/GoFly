import Foundation
import GoFlyMacCore
import Testing

@Suite struct MacReinstallJournalTests {
    private func fixture() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Reinstall/journal-source.json"))
    }

    private func directory() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-mac-reinstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }

    private func write(_ data: Data, at root: URL) throws {
        let file = root.appendingPathComponent("reinstall-journal.json")
        try data.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    @Test func actualPythonJournalSuppliesOnlyFrozenContinuationIdentity() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = try fixture()
        try write(bytes, at: root)
        let reader = MacReinstallJournalReader(stateRoot: root)
        let actual = try await reader.readContinuation()
        #expect(actual?.transferID == UUID(uuidString: "11111111-1111-4111-8111-111111111111"))
        #expect(actual?.deviceID == "01234567-89abcdef01234567")
        #expect(actual?.categories == [.favorites, .routes])
        #expect(try Data(contentsOf: root.appendingPathComponent("reinstall-journal.json")) == bytes)
    }

    @Test func missingJournalIsReadOnlyAndDoesNotCreateAStateDirectory() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly-missing-journal-\(UUID().uuidString)")
        #expect(try await MacReinstallJournalReader(stateRoot: root).readContinuation() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func invalidSelectionDuplicateKeysAndVersionCoercionAreRejected() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let raw = String(decoding: try fixture(), as: UTF8.self)
        let mutations = [raw.replacingOccurrences(of: "\"version\":1", with: "\"version\":1.0"),
            raw.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1"),
            raw.replacingOccurrences(of: "[\"favorites\",\"routes\"]", with: "[\"routes\",\"favorites\"]"),
            raw.replacingOccurrences(of: "[\"favorites\",\"routes\"]", with: "[\"favorites\",\"favorites\"]"),
            raw.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"extra\":true")]
        for mutation in mutations {
            try write(Data(mutation.utf8), at: root)
            await #expect(throws: MacReinstallFailure.invalidResponse) {
                try await MacReinstallJournalReader(stateRoot: root).readContinuation()
            }
        }
    }

    @Test func privateModesHardLinksAndSymlinkAncestorsCannotBeRepairedByReading() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(fixture(), at: root)
        let file = root.appendingPathComponent("reinstall-journal.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        await #expect(throws: MacReinstallFailure.invalidResponse) {
            try await MacReinstallJournalReader(stateRoot: root).readContinuation()
        }
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.linkItem(at: file, to: alias)
        await #expect(throws: MacReinstallFailure.invalidResponse) {
            try await MacReinstallJournalReader(stateRoot: root).readContinuation()
        }
        try FileManager.default.removeItem(at: alias)
        let link = root.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        await #expect(throws: MacReinstallFailure.invalidResponse) {
            try await MacReinstallJournalReader(stateRoot: link).readContinuation()
        }
    }
}
