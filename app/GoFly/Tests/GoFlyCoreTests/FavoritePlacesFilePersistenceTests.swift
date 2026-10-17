import Combine
import Darwin
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct FavoritePlacesFilePersistenceTests {
    @Test func actualFileReplacementIsPrivateAndRelaunchReadsTheSameFavorite() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/gofly05-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileFavoritePlacesPersistence(directory: directory)
        #expect(try disk.read() == nil)
        let store = FavoritePlacesStore(persistence: disk)
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        let place = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        #expect(store.toggle(place))
        let bytes = try #require(try disk.read())
        #expect(!bytes.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: disk.fileURL.path)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        let relaunched = FavoritePlacesStore(persistence: FileFavoritePlacesPersistence(directory: directory))
        #expect(relaunched.loadState == .ready)
        #expect(relaunched.favorites == store.favorites)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["favorites.json"])
    }
    @Test(arguments: FavoritePlacesWriteCheckpoint.allCases)
    func eachPrecommitFailurePreservesActualAuthoritativeBytesAndPublishedState(checkpoint: FavoritePlacesWriteCheckpoint) throws {
        let directory = URL(fileURLWithPath: "/private/tmp/gofly05-fault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let normalDisk = FileFavoritePlacesPersistence(directory: directory)
        let originalStore = FavoritePlacesStore(persistence: normalDisk)
        let first = place(id: "first")
        #expect(originalStore.toggle(first))
        let bytes = try #require(try normalDisk.read())
        let failingDisk = FileFavoritePlacesPersistence(directory: directory) { reached in
            if reached == checkpoint { throw CocoaError(.fileWriteUnknown) }
        }
        let store = FavoritePlacesStore(persistence: failingDisk)
        var publications = 0
        let observation = store.$favorites.dropFirst().sink { _ in publications += 1 }
        #expect(!store.toggle(place(id: "other")))
        #expect(store.error == .writeFailed)
        #expect(store.favorites == originalStore.favorites)
        #expect(publications == 0)
        #expect(try normalDisk.read() == bytes)
        #expect(FavoritePlacesStore(persistence: normalDisk).favorites == originalStore.favorites)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["favorites.json"])
        withExtendedLifetime(observation) {}
    }

    @Test func aRealFailedRenamePreservesTheOldFileAndNoObserverSeesAFalseSuccess() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/gofly05-rename-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let normalDisk = FileFavoritePlacesPersistence(directory: directory)
        let original = FavoritePlacesStore(persistence: normalDisk)
        #expect(original.toggle(place(id: "first")))
        let bytes = try normalDisk.read()
        let failingDisk = FileFavoritePlacesPersistence(directory: directory) { checkpoint in
            if checkpoint == .stagingFlushed {
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.lastPathComponent != "favorites.json" {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
        let store = FavoritePlacesStore(persistence: failingDisk)
        #expect(!store.toggle(place(id: "other")))
        #expect(store.error == .writeFailed)
        #expect(store.favorites == original.favorites)
        #expect(try normalDisk.read() == bytes)
    }

    @Test(arguments: ["symlink", "directory", "fifo", "oversized", "directorySymlink"])
    func unsafeOrOversizedFilesBlockMutationWithoutFollowingOrReplacingThem(kind: String) throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly05-unsafe-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent("FavoritePlaces", isDirectory: true)
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = Data("must stay unchanged".utf8)
        let outsideFile = outside.appendingPathComponent("favorites.json")
        try sentinel.write(to: outsideFile)
        if kind == "directorySymlink" {
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("favorites.json")
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outsideFile)
            case "directory": try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            case "fifo": #expect(mkfifo(file.path, 0o600) == 0)
            default: try Data(repeating: 32, count: 1_048_577).write(to: file)
            }
        }
        let disk = FileFavoritePlacesPersistence(directory: directory)
        let store = FavoritePlacesStore(persistence: disk)
        #expect(store.loadState == .blocked(kind == "oversized" ? .limitExceeded : .unsafeFile))
        #expect(!store.toggle(place(id: "new")))
        #expect(!store.canMutate)
        #expect(try Data(contentsOf: outsideFile) == sentinel)
        if kind == "oversized" {
            #expect(try Data(contentsOf: disk.fileURL).count == 1_048_577)
        }
    }

    @Test(arguments: [false, true])
    func aTargetThatBecomesNonregularAfterLoadIsPreservedAndBlocksFurtherMutations(directoryReplaced: Bool) throws {
        let root = URL(fileURLWithPath: "/private/tmp/gofly05-replaced-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("FavoritePlaces", isDirectory: true)
        let disk = FileFavoritePlacesPersistence(directory: directory)
        let store = FavoritePlacesStore(persistence: disk)
        #expect(store.toggle(place(id: "first")))
        let before = store.favorites
        let sentinel = Data("external data must remain unchanged".utf8)
        if directoryReplaced {
            try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("old-directory"))
            try sentinel.write(to: directory)
        } else {
            let outside = root.appendingPathComponent("outside.json")
            try sentinel.write(to: outside)
            try FileManager.default.removeItem(at: disk.fileURL)
            try FileManager.default.createSymbolicLink(at: disk.fileURL, withDestinationURL: outside)
        }
        #expect(!store.toggle(place(id: "other")))
        #expect(store.loadState == .blocked(.unsafeFile))
        #expect(!store.canMutate)
        #expect(store.favorites == before)
        #expect(!store.toggle(place(id: "yet-another")))
        if directoryReplaced { #expect(try Data(contentsOf: directory) == sentinel) }
        else {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: disk.fileURL.path) == root.appendingPathComponent("outside.json").path)
            #expect(try Data(contentsOf: root.appendingPathComponent("outside.json")) == sentinel)
        }
    }

    private func place(id: String) -> MapPlace {
        MapPlace(id: .mapKit(id), title: "Place", coordinate: GeoCoordinate(latitude: 25, longitude: 121)!)
    }
}
