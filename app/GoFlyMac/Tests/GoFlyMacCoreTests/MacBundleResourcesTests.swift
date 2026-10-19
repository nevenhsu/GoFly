import CryptoKit
import Foundation
import GoFlyMacCore
import Testing

@Suite struct MacBundleResourcesTests {
    @Test func readsOnlyTheClosedManifestEntries() throws {
        let fixture = try BundleFixture()
        defer { fixture.remove() }
        let resources = try MacBundleResources(bundleURL: fixture.root)
        #expect(try resources.read(.checkScript) == Data("Contents/Resources/Bridge/bridge.py".utf8))
        _ = try resources.stamp()
        try resources.revalidate()
    }

    @Test func manifestKeySetMustMatchAllowlistExactly() throws {
        do {
            let fixture = try BundleFixture()
            defer { fixture.remove() }
            _ = try MacBundleResources(bundleURL: fixture.root)
        }
        do {
            let fixture = try BundleFixture()
            defer { fixture.remove() }
            var files = try fixture.manifestFiles()
            files["Contents/Resources/Bridge/extra.py"] = String(repeating: "0", count: 64)
            try fixture.writeManifest(files)
            #expect(throws: MacBundleResourceError.invalidManifest) {
                _ = try MacBundleResources(bundleURL: fixture.root)
            }
        }
        do {
            let fixture = try BundleFixture()
            defer { fixture.remove() }
            var files = try fixture.manifestFiles()
            files.removeValue(forKey: "Contents/Resources/Bridge/Device/__init__.py")
            try fixture.writeManifest(files)
            #expect(throws: MacBundleResourceError.invalidManifest) {
                _ = try MacBundleResources(bundleURL: fixture.root)
            }
        }
    }

    @Test func contentMutationInvalidatesTheRetainedStamp() throws {
        let fixture = try BundleFixture()
        defer { fixture.remove() }
        let resources = try MacBundleResources(bundleURL: fixture.root)
        try Data("changed".utf8).write(to: fixture.url(.checkScript), options: .atomic)
        #expect(throws: MacBundleResourceError.invalidManifest) {
            try resources.revalidate()
        }
    }

    @Test func writableResourceIsRejected() throws {
        let fixture = try BundleFixture()
        defer { fixture.remove() }
        let resources = try MacBundleResources(bundleURL: fixture.root)
        try FileManager.default.setAttributes([.posixPermissions: 0o664], ofItemAtPath: fixture.url(.checkScript).path)
        #expect(throws: MacBundleResourceError.invalidBundle) {
            try resources.revalidate()
        }
    }

    @Test func symlinkAndHardlinkEntriesAreRejected() throws {
        do {
            let fixture = try BundleFixture()
            defer { fixture.remove() }
            let target = fixture.root.appendingPathComponent("outside.py")
            try Data("outside".utf8).write(to: target)
            try FileManager.default.removeItem(at: fixture.url(.checkScript))
            try FileManager.default.createSymbolicLink(at: fixture.url(.checkScript), withDestinationURL: target)
            #expect(throws: MacBundleResourceError.invalidBundle) {
                _ = try MacBundleResources(bundleURL: fixture.root)
            }
        }
        do {
            let fixture = try BundleFixture()
            defer { fixture.remove() }
            let target = fixture.root.appendingPathComponent("outside.py")
            try Data("outside".utf8).write(to: target)
            try FileManager.default.removeItem(at: fixture.url(.checkScript))
            try FileManager.default.linkItem(at: target, to: fixture.url(.checkScript))
            #expect(throws: MacBundleResourceError.invalidBundle) {
                _ = try MacBundleResources(bundleURL: fixture.root)
            }
        }
    }

    @Test func malformedOrIncompleteManifestFailsClosed() throws {
        let fixture = try BundleFixture()
        defer { fixture.remove() }
        let incomplete: [String: Any] = ["version": 1, "files": [:]]
        try JSONSerialization.data(withJSONObject: incomplete).write(to: fixture.manifestURL, options: .atomic)
        #expect(throws: MacBundleResourceError.invalidManifest) {
            _ = try MacBundleResources(bundleURL: fixture.root)
        }
    }

    @Test func duplicateManifestKeysFailClosed() throws {
        let fixture = try BundleFixture()
        defer { fixture.remove() }
        try Data(#"{"version":1,"files":{},"files":{}}"#.utf8).write(to: fixture.manifestURL, options: .atomic)
        #expect(throws: MacBundleResourceError.invalidManifest) {
            _ = try MacBundleResources(bundleURL: fixture.root)
        }
    }
}

private final class BundleFixture {
    let root: URL
    let manifestURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-bundle-\(UUID().uuidString)").appendingPathComponent("GoFly.app")
        manifestURL = root.appendingPathComponent(MacBundleResources.manifestRelativePath)
        for entry in MacBundleResourceEntry.allCases {
            let url = root.appendingPathComponent(entry.rawValue)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(entry.rawValue.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        var files: [String: String] = [:]
        for entry in MacBundleResourceEntry.allCases {
            files[entry.rawValue] = Self.sha256(Data(entry.rawValue.utf8))
        }
        try writeManifest(files)
    }

    func manifestFiles() throws -> [String: String] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        return object?["files"] as? [String: String] ?? [:]
    }

    func writeManifest(_ files: [String: String]) throws {
        let manifest: [String: Any] = ["version": MacBundleResources.manifestVersion, "files": files]
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: manifestURL.path)
    }

    func url(_ entry: MacBundleResourceEntry) -> URL {
        root.appendingPathComponent(entry.rawValue)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
