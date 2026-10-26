import Combine
import Foundation

@MainActor
public final class FavoritePlacesStore: ObservableObject {
    @Published public private(set) var favorites: [FavoritePlace] = []
    @Published public private(set) var loadState: FavoritePlacesLoadState = .ready
    @Published public private(set) var error: FavoritePlacesFailure?
    @Published public private(set) var canUndo = false
    private var deleted: [(index: Int, favorite: FavoritePlace)] = []
    private let persistence: any FavoritePlacesPersistence
    // A label editor may remove and re-add its immutable place snapshot. Only
    // successfully persisted labels enter this cache; drafts never reach it.
    private var rememberedLabels: [FavoritePlaceKey: String] = [:]

    public init(persistence: any FavoritePlacesPersistence) {
        self.persistence = persistence
        reload()
    }

    /// Rereads the stored favorites; used by the shared retry. Unsaved in-memory
    /// changes are dropped, so the list matches what is on disk.
    public func reload() {
        do {
            favorites = try persistence.read().map { try FavoritePlacesArchive.decode($0) } ?? []
            rememberedLabels = [:]
            for favorite in favorites { rememberedLabels[favorite.key] = favorite.label }
            loadState = .ready
            error = nil
        } catch {
            let failure = error as? FavoritePlacesFailure ?? .unavailable
            loadState = .blocked(failure)
            self.error = failure
        }
    }
    public var canMutate: Bool { loadState == .ready }
    @discardableResult
    public func favorite(for place: MapPlace) -> FavoritePlace? {
        guard let key = FavoritePlaceKey(place: place) else { return nil }
        return favorites.first { $0.key == key }
    }
    public func isFavorite(_ place: MapPlace) -> Bool { favorite(for: place) != nil }
    public func clearError() { error = nil }

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
                proposed.insert(FavoritePlace(key: key, place: place, label: rememberedLabels[key]), at: 0)
            }
            guard persist(proposed) else { return false }
            if let removed { rememberedLabels[removed.key] = removed.label }
            return true
        } catch { self.error = error as? FavoritePlacesFailure ?? .writeFailed; return false }
    }

    /// One persisted transaction for the selected batch; undo retains each record's label and position.
    @discardableResult public func delete(_ keys: Set<FavoritePlaceKey>) -> Bool {
        guard canMutate else { return false }
        let removed = favorites.enumerated().filter { keys.contains($0.element.key) }
        guard !removed.isEmpty else { return false }
        guard persist(favorites.filter { !keys.contains($0.key) }) else { return false }
        deleted = removed.map { (index: $0.offset, favorite: $0.element) }
        canUndo = true
        return true
    }

    @discardableResult public func undoDelete() -> Bool {
        guard canMutate, canUndo else { return false }
        var proposed = favorites
        for item in deleted where !proposed.contains(where: { $0.key == item.favorite.key }) {
            proposed.insert(item.favorite, at: min(item.index, proposed.count))
        }
        guard persist(proposed) else { return false }
        deleted = []
        canUndo = false
        return true
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
        proposed.remove(at: index)
        proposed.insert(FavoritePlace(key: key, place: favorites[index].place, label: label), at: 0)
        guard persist(proposed) else { return false }
        rememberedLabels[key] = label
        return true
    }

    @discardableResult public func save(place: MapPlace, label: String?) -> Bool {
        guard canMutate else { return false }
        do {
            guard let key = FavoritePlaceKey(place: place) else { throw FavoritePlacesFailure.invalidPlace }
            try FavoritePlacesArchive.validate(place)
            let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard FavoritePlacesArchive.validText(trimmed, maximum: FavoritePlacesLimits.labelCharacters) else {
                error = .invalidLabel
                return false
            }
            let normalized = FavoritePlacesArchive.normalizedLabel(trimmed)
            var proposed = favorites
            if let index = proposed.firstIndex(where: { $0.key == key }) {
                proposed.remove(at: index)
            }
            proposed.insert(FavoritePlace(key: key, place: place, label: normalized), at: 0)
            guard persist(proposed) else { return false }
            rememberedLabels[key] = normalized
            return true
        } catch { self.error = error as? FavoritePlacesFailure ?? .writeFailed; return false }
    }

    @discardableResult public func delete(place: MapPlace) -> Bool {
        guard let key = FavoritePlaceKey(place: place) else { return false }
        return delete([key])
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
