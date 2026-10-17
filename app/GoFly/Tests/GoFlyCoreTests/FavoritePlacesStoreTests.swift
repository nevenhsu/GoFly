import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct FavoritePlacesStoreTests {
    @Test func starPublishesOnlyAfterPersistenceAndUsesIdentityAndExactCoordinate() throws {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        let first = place(id: "one", latitude: 25)
        let sameNameElsewhere = place(id: "one", latitude: 25.0000001)
        #expect(store.loadState == .ready)
        #expect(store.toggle(first))
        #expect(store.isFavorite(first))
        #expect(!store.isFavorite(sameNameElsewhere))
        let saved = try #require(disk.bytes)
        let renamed = MapPlace(id: first.id, title: "Renamed", coordinate: first.coordinate)
        #expect(store.isFavorite(renamed))
        disk.failWrites = true
        #expect(!store.toggle(first))
        #expect(store.isFavorite(first))
        #expect(disk.bytes == saved)
        #expect(store.error == .writeFailed)
        disk.failWrites = false
        #expect(store.toggle(sameNameElsewhere))
        #expect(store.favorites.count == 2)
        let relaunched = FavoritePlacesStore(persistence: disk)
        #expect(relaunched.favorites == store.favorites)
    }

    @Test func labelsAreSeparateAndRemoveReaddUsesOnlyTheLastPersistedLabel() throws {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        let place = place(id: "home", latitude: 25)
        #expect(store.toggle(place))
        let key = try #require(store.favorite(for: place)?.key)
        #expect(store.saveLabel(for: key, draft: "  Home  "))
        let editorSnapshot = try #require(store.favorite(for: place))
        #expect(editorSnapshot.label == "Home")
        #expect(editorSnapshot.place.title == "Same name")
        #expect(store.toggle(editorSnapshot.place))
        #expect(!store.isFavorite(place))
        #expect(!store.saveLabel(for: key, draft: "Unsaved draft"))
        #expect(store.error == .notFavorite)
        #expect(store.toggle(editorSnapshot.place))
        #expect(store.favorite(for: place)?.label == "Home")
        #expect(FavoritePlacesStore(persistence: disk).favorite(for: place)?.label == "Home")
        let before = disk.bytes
        disk.failWrites = true
        #expect(!store.saveLabel(for: key, draft: "Work"))
        #expect(store.favorite(for: place)?.label == "Home")
        #expect(disk.bytes == before)
        disk.failWrites = false
        #expect(store.toggle(place))
        #expect(store.toggle(place))
        #expect(store.favorite(for: place)?.label == "Home")
        #expect(!store.saveLabel(for: key, draft: String(repeating: "x", count: 121)))
        #expect(store.error == .invalidLabel)
        #expect(store.saveLabel(for: key, draft: "  "))
        #expect(store.favorite(for: place)?.label == nil)
        #expect(store.toggle(place))
        #expect(store.toggle(place))
        #expect(store.favorite(for: place)?.label == nil)
        #expect(editorSnapshot.label == "Home", "An open editor remains an immutable snapshot")
    }

    @Test func runtimeIdentityMismatchCannotPersistAndAddressFallbackKeepsOriginalMetadata() throws {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        let first = GeoCoordinate(latitude: 25, longitude: 121)!
        let other = GeoCoordinate(latitude: 26, longitude: 121)!
        #expect(!store.toggle(MapPlace(id: .coordinate(first), title: "Mismatch", coordinate: other)))
        #expect(!store.toggle(MapPlace(id: .mapKit("  "), title: "Empty identity", coordinate: first)))
        #expect(!store.toggle(MapPlace(id: .mapKit(String(repeating: "x", count: 2049)), title: "Long identity", coordinate: first)))
        #expect(disk.bytes == nil)
        let addressPlace = MapPlace(id: .mapKit("address"), title: "  ", coordinate: first, address: "  Taipei  ")
        #expect(addressPlace.address == "Taipei")
        #expect(addressPlace.title == "Taipei")
        #expect(store.toggle(addressPlace))
        let key = try #require(store.favorite(for: addressPlace)?.key)
        #expect(store.saveLabel(for: key, draft: "Label"))
        #expect(store.favorite(for: addressPlace)?.place == addressPlace)
        #expect(store.favorite(for: addressPlace)?.displayTitle == "Label")
        #expect(store.toggle(MapPlace(id: .mapKit("other"), title: addressPlace.title, coordinate: first)))
        #expect(store.favorites.count == 2)
        let coordsOnly = MapPlace(id: .coordinate(first), title: "", coordinate: first, address: "   ")
        #expect(coordsOnly.address == nil)
        #expect(coordsOnly.title == "25.000000, 121.000000")
    }

    @Test func recordLimitRejectsTheWholeProposedChangeWithoutPublishing() {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        for index in 0..<100 { #expect(store.toggle(place(id: "place-\(index)", latitude: 25))) }
        let before = disk.bytes
        let original = store.favorites
        #expect(!store.toggle(place(id: "overflow", latitude: 25)))
        #expect(store.error == .limitExceeded)
        #expect(store.favorites == original)
        #expect(disk.bytes == before)
        #expect(store.toggle(original[0].place))
        #expect(store.toggle(place(id: "overflow", latitude: 25)))
        #expect(store.favorites.count == 100)
    }

    @Test func unknownVersionIsRecognizedBeforeItsUnknownRecordSchemaIsDecoded() {
        let bytes = Data(#"{"schemaVersion":99,"favorites":[{"newVersionField":true}]}"#.utf8)
        let disk = FavoriteTestPersistence(bytes: bytes)
        let store = FavoritePlacesStore(persistence: disk)
        #expect(store.loadState == .blocked(.unsupportedSchema))
        #expect(!store.canMutate)
        #expect(!store.toggle(place(id: "new", latitude: 25)))
        #expect(disk.bytes == bytes)
    }

    @Test func knownVersionOneSchemaRehydratesValidatedSourceAndNormalizedMetadata() throws {
        let bytes = Data(#"{"schemaVersion":1,"favorites":[{"identity":{"kind":"mapKit","value":"stable"},"coordinate":{"latitude":25.033,"longitude":121.5654},"title":"Taipei","address":"  Taiwan  ","label":"  Home  "}]}"#.utf8)
        let disk = FavoriteTestPersistence(bytes: bytes)
        let store = FavoritePlacesStore(persistence: disk)
        #expect(store.loadState == .ready)
        let favorite = try #require(store.favorites.first)
        #expect(favorite.place.id == .mapKit("stable"))
        #expect(favorite.place.coordinate == GeoCoordinate(latitude: 25.033, longitude: 121.5654))
        #expect(favorite.place.title == "Taipei")
        #expect(favorite.place.address == "Taiwan")
        #expect(favorite.label == "Home")
        #expect(disk.bytes == bytes, "Loading never rewrites an archive")
        #expect(store.toggle(favorite.place))
        #expect(FavoritePlacesStore(persistence: disk).favorites.isEmpty)
    }

    @Test func invalidArchivesRejectTheWholeCollectionAndCannotBeOverwrittenByAnyMutation() throws {
        let valid: [String: Any] = ["identity": ["kind": "mapKit", "value": "stable"],
            "coordinate": ["latitude": 25.0, "longitude": 121.0], "title": "Taipei"]
        func archive(_ records: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "favorites": records])
        }
        var badRecords: [[String: Any]] = []
        for coordinate in [["latitude": 91.0, "longitude": 121.0], ["latitude": -91.0, "longitude": 121.0],
                           ["latitude": 25.0, "longitude": 181.0]] {
            var record = valid; record["coordinate"] = coordinate; badRecords.append(record)
        }
        for identity in [["kind": "mapKit", "value": ""], ["kind": "other", "value": "stable"],
                         ["kind": "coordinate", "value": "unexpected"],
                         ["kind": "mapKit", "value": String(repeating: "x", count: 2049)]] {
            var record = valid; record["identity"] = identity; badRecords.append(record)
        }
        for (field, text) in [("title", ""), ("title", String(repeating: "x", count: 513)),
                              ("address", String(repeating: "x", count: 2049)),
                              ("label", String(repeating: "x", count: 121))] {
            var record = valid; record[field] = text; badRecords.append(record)
        }
        var archives = try badRecords.map { try archive([valid, $0]) }
        archives.append(try archive([valid, valid]))
        archives.append(try archive(Array(repeating: valid, count: 101)))
        archives.append(Data(repeating: 32, count: 1_048_577))
        archives.append(Data(#"{"schemaVersion":1,"favorites":[{"id":"prototype-uuid","name":"Old","point":{"latitude":25,"longitude":121},"createdAt":0}]}"#.utf8))
        archives.append(Data(#"{"schemaVersion":1,"favorites":[{"identity":{"kind":"coordinate"},"coordinate":{"latitude":1e400,"longitude":121},"title":"Infinity"}]}"#.utf8))
        archives.append(Data("{broken".utf8))
        let coordinate = GeoCoordinate(latitude: 25, longitude: 121)!
        let target = MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
        let key = try #require(FavoritePlaceKey(place: target))
        for bytes in archives {
            let disk = FavoriteTestPersistence(bytes: bytes)
            let store = FavoritePlacesStore(persistence: disk)
            guard case .blocked = store.loadState else { Issue.record("An invalid archive must block all mutations"); continue }
            #expect(!store.canMutate)
            #expect(store.favorites.isEmpty)
            #expect(!store.toggle(target))
            #expect(!store.saveLabel(for: key, draft: "New"))
            #expect(disk.bytes == bytes)
        }
    }

    @Test func observersNeverReceiveAChangeBeforeTheCorrespondingArchiveHasCommitted() {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        var publications = 0
        let observation = store.$favorites.dropFirst().sink { proposed in
            publications += 1
            #expect(FavoritePlacesStore(persistence: disk).favorites == proposed)
        }
        #expect(store.toggle(place(id: "first", latitude: 25)))
        #expect(publications == 1)
        disk.failWrites = true
        #expect(!store.toggle(place(id: "other", latitude: 26)))
        #expect(publications == 1)
        withExtendedLifetime(observation) {}
    }

    @Test func removingByExactIdentityDoesNotTryToPersistRefreshedInvalidDisplayMetadata() {
        let disk = FavoriteTestPersistence()
        let store = FavoritePlacesStore(persistence: disk)
        let original = place(id: "same", latitude: 25)
        #expect(store.toggle(original))
        let refreshed = MapPlace(id: original.id, title: String(repeating: "x", count: 513),
            coordinate: original.coordinate, address: String(repeating: "x", count: 2049))
        #expect(store.isFavorite(refreshed))
        #expect(store.toggle(refreshed))
        #expect(store.favorites.isEmpty)
        #expect(!store.toggle(refreshed), "Adding new metadata still enforces all bounds")
        #expect(store.error == .invalidPlace)
    }

    private func place(id: String, latitude: Double) -> MapPlace {
        MapPlace(id: .mapKit(id), title: "Same name", coordinate: GeoCoordinate(latitude: latitude, longitude: 121)!)
    }
}

private final class FavoriteTestPersistence: FavoritePlacesPersistence, @unchecked Sendable {
    var bytes: Data?
    var failWrites = false
    init(bytes: Data? = nil) { self.bytes = bytes }
    func read() throws -> Data? { bytes }
    func replaceAtomically(with data: Data) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        bytes = data
    }
}
