import Combine
import Foundation

@MainActor
public final class FavoritePlacesStore: ObservableObject {
    @Published public private(set) var favorites: [FavoritePlace] = []
    @Published public private(set) var loadState: FavoritePlacesLoadState = .ready
    @Published public private(set) var error: FavoritePlacesFailure?
    private let persistence: any FavoritePlacesPersistence
    private let transferOwnerID = UUID()
    private var transferHold: TransferHold?
    // A label editor may remove and re-add its immutable place snapshot. Only
    // successfully persisted labels enter this cache; drafts never reach it.
    private var rememberedLabels: [FavoritePlaceKey: String] = [:]

    public init(persistence: any FavoritePlacesPersistence) {
        self.persistence = persistence
        do {
            if let data = try persistence.read() { favorites = try FavoritePlacesArchive.decode(data) }
            for favorite in favorites { rememberedLabels[favorite.key] = favorite.label }
        } catch {
            let failure = error as? FavoritePlacesFailure ?? .unavailable
            loadState = .blocked(failure)
            self.error = failure
        }
    }
    public var canMutate: Bool { loadState == .ready && transferHold == nil }
    public func acquireTransferHold() -> TransferHold? {
        guard transferHold == nil, loadState == .ready, error == nil else { return nil }
        let hold = TransferHold(ownerID: transferOwnerID, tokenID: UUID())
        transferHold = hold
        return hold
    }
    @discardableResult
    public func releaseTransferHold(_ token: TransferHold) -> Bool {
        guard transferHold == token,
              token.ownerID == transferOwnerID else { return false }
        transferHold = nil
        return true
    }
    public func transferArchive(using token: TransferHold) throws -> Data {
        guard transferHold == token, token.ownerID == transferOwnerID,
              loadState == .ready, error == nil else { throw FavoritePlacesFailure.unavailable }
        let raw = try persistence.transferSnapshot()
        let data = try raw ?? TransferArchiveCodec.emptyFavoritePlaces()
        let decoded = try TransferArchiveCodec.favoritePlaces(data)
        guard decoded == favorites else { throw FavoritePlacesFailure.corruptArchive }
        return data
    }
    public func favorite(for place: MapPlace) -> FavoritePlace? {
        guard let key = FavoritePlaceKey(place: place) else { return nil }
        return favorites.first { $0.key == key }
    }
    public func isFavorite(_ place: MapPlace) -> Bool { favorite(for: place) != nil }
    public func clearError() { guard transferHold == nil else { return }; error = nil }

    @discardableResult public func toggle(_ place: MapPlace) -> Bool {
        guard canMutate else { return false }
        do {
            guard let key = FavoritePlaceKey(place: place) else { throw FavoritePlacesFailure.invalidPlace }
            var proposed = favorites
            let removed: FavoritePlace?
            if let index = proposed.firstIndex(where: { $0.key == key }) {
                removed = proposed.remove(at: index)
            } else {
                try FavoritePlacesArchive.validate(place)
                removed = nil
                proposed.append(FavoritePlace(key: key, place: place, label: rememberedLabels[key]))
            }
            guard persist(proposed) else { return false }
            if let removed { rememberedLabels[removed.key] = removed.label }
            return true
        } catch { self.error = error as? FavoritePlacesFailure ?? .writeFailed; return false }
    }

    @discardableResult public func saveLabel(for key: FavoritePlaceKey, draft: String) -> Bool {
        guard canMutate else { return false }
        guard let index = favorites.firstIndex(where: { $0.key == key }) else { error = .notFavorite; return false }
        guard FavoritePlacesArchive.validText(draft, maximum: FavoritePlacesLimits.labelCharacters) else {
            error = .invalidLabel
            return false
        }
        let label = FavoritePlacesArchive.normalizedLabel(draft)
        var proposed = favorites
        proposed[index] = FavoritePlace(key: key, place: favorites[index].place, label: label)
        guard persist(proposed) else { return false }
        rememberedLabels[key] = label
        return true
    }

    private func persist(_ proposed: [FavoritePlace]) -> Bool {
        do {
            let data = try FavoritePlacesArchive.encode(proposed)
            // Validation failures are specific; external persistence failures do
            // not expose paths or pretend that an observer change was saved.
            do { try persistence.replaceAtomically(with: data) }
            catch FavoritePlacesFailure.unsafeFile {
                loadState = .blocked(.unsafeFile)
                error = .unsafeFile
                return false
            }
            catch { self.error = .writeFailed; return false }
            favorites = proposed
            error = nil
            return true
        } catch { self.error = error as? FavoritePlacesFailure ?? .writeFailed; return false }
    }
}
