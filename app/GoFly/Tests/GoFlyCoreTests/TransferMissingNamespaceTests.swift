import Foundation
import XCTest
@testable import GoFlyCore

final class TransferMissingNamespaceTests: XCTestCase {
    func testAbsentNamespaceCanRemainAbsentBeforeAncestorWalk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let missing = alias.appendingPathComponent("GoFlyTransfer")
        XCTAssertNil(try TransferFileIO.openDirectory(missing, allowMissing: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("GoFlyTransfer").path))
        XCTAssertThrowsError(try TransferFileIO.openDirectory(missing, allowMissing: false))
    }

    func testExistingNamespaceStillRejectsSymlinkAncestor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target/GoFlyTransfer")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("target"))
        XCTAssertThrowsError(try TransferFileIO.openDirectory(alias.appendingPathComponent("GoFlyTransfer"), allowMissing: true))
    }

    func testDanglingNamespaceSymlinkIsNotTreatedAsAbsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let alias = root.appendingPathComponent("GoFlyTransfer")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try TransferFileIO.openDirectory(alias, allowMissing: true))
    }
}
