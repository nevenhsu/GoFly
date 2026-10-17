import Foundation
import Testing
@testable import GoFlyCore

struct SecureArchiveDirectoryTests {
    @Test(arguments: [false, true])
    func anExclusiveCreateCollisionPreservesTheExistingStagingAndTarget(stagingIsSymlink: Bool) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("archive.json")
        let staging = directory.appendingPathComponent("chosen.staging")
        let sentinel = directory.appendingPathComponent("sentinel")
        let oldTarget = Data("authoritative archive".utf8)
        let oldStaging = Data("existing staging must survive".utf8)
        try oldTarget.write(to: target)
        if stagingIsSymlink {
            try oldStaging.write(to: sentinel)
            try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: sentinel)
        } else { try oldStaging.write(to: staging) }
        let archive = try #require(try SecureArchiveDirectory.open(directory, create: false, secureDirectory: true))

        #expect(throws: SecureArchiveFailure.self) {
            try archive.replaceAtomically(Data("replacement".utf8), target: "archive.json", staging: "chosen.staging", checkpoint: { _ in })
        }

        #expect(try Data(contentsOf: target) == oldTarget)
        // Reading through a missing link would throw, so check the directory
        // entry before any content read and preserve the link itself as well.
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(names.contains("chosen.staging"))
        if names.contains("chosen.staging") {
            #expect(try Data(contentsOf: staging) == oldStaging)
            if stagingIsSymlink {
                #expect(try FileManager.default.destinationOfSymbolicLink(atPath: staging.path) == sentinel.path)
            }
        }
        if stagingIsSymlink { #expect(try Data(contentsOf: sentinel) == oldStaging) }
    }

    @Test(arguments: ["secured", "written", "flushed"])
    func aCheckpointFailureAfterCreatingOurOwnStagingStillCleansIt(point: String) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("archive.json")
        let original = Data("authoritative archive".utf8)
        try original.write(to: target)
        let archive = try #require(try SecureArchiveDirectory.open(directory, create: false, secureDirectory: true))

        #expect(throws: CocoaError.self) {
            try archive.replaceAtomically(Data("replacement".utf8), target: "archive.json", staging: "owned.staging") { reached in
                if String(describing: reached) == point { throw CocoaError(.fileWriteUnknown) }
            }
        }

        #expect(try Data(contentsOf: target) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["archive.json"])
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/private/tmp/gofly10-primitive-\(UUID().uuidString)", isDirectory: true)
    }
}
