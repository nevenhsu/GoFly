import Foundation

public enum TransferPackageValidator {
    public static func validate(directory: URL) throws -> ValidatedTransferPackage {
        let root = try TransferFileIO.openPackageRoot(directory)
        guard let rawManifest = try root.read("manifest.json", maximum: TransferLimits.manifestBytes) else {
            throw TransferFailure.artifactMismatch
        }
        let input = try TransferInput(data: rawManifest)
        let manifest = input.manifest

        // The first pass only reads bounded metadata and streams each digest.
        // No payload Data is retained while the package quota is established.
        var artifacts: [String: TransferArtifact] = [:]
        var aggregate: Int64 = 0
        for artifact in manifest.artifacts {
            let maximum = maximumBytes(for: artifact.path)
            guard artifact.byteCount <= Int64(maximum) else { throw TransferFailure.limitExceeded }
            guard aggregate <= Int64(TransferLimits.aggregateBytes) - artifact.byteCount else {
                throw TransferFailure.limitExceeded
            }
            guard let actual = try root.inspect(artifact.path, maximum: maximum),
                  actual.size == artifact.byteCount, actual.sha256 == artifact.sha256 else {
                throw TransferFailure.artifactMismatch
            }
            aggregate += artifact.byteCount
            guard artifacts.updateValue(artifact, forKey: artifact.path) == nil else {
                throw TransferFailure.artifactMismatch
            }
        }

        // The two route archives have independent 64 MiB payload quotas. The
        // sums use only verified actual artifact byte counts and are checked
        // before any route manifest or payload is retained for semantics.
        let importedArchiveBytes = try archivePayloadBytes(prefix: "routes/imported/", suffix: ".gpx", artifacts: artifacts)
        let favoriteArchiveBytes = try archivePayloadBytes(prefix: "routes/favorites/", suffix: ".route", artifacts: artifacts)
        guard importedArchiveBytes <= Int64(ImportedRoutesLimits.payloadBytes),
              favoriteArchiveBytes <= Int64(FavoriteRoutesLimits.payloadBytes) else {
            throw TransferFailure.limitExceeded
        }

        var counts = TransferCounts()
        var settings: TransferSettings?
        var draft: RouteDraft?
        var expectedPaths = Set<String>(["manifest.json"])

        if manifest.categories.contains(.favorites) {
            let artifact = try requireArtifact("favorites/archive.json", in: artifacts)
            let data = try semanticRead("favorites/archive.json", artifact: artifact, root: root,
                                        rawManifestSHA256: input.rawManifestSHA256)
            let places = try TransferArchiveCodec.favoritePlaces(data)
            counts = TransferCounts(favorites: places.count, importedRoutes: counts.importedRoutes,
                                    favoriteRoutes: counts.favoriteRoutes, draftNodes: counts.draftNodes,
                                    gpxPoints: counts.gpxPoints)
            expectedPaths.insert(artifact.path)
        }

        if manifest.categories.contains(.routes) {
            let importedManifestArtifact = try requireArtifact("routes/imported/manifest.json", in: artifacts)
            let favoriteManifestArtifact = try requireArtifact("routes/favorites/manifest.json", in: artifacts)
            let draftArtifact = try requireArtifact("routes/draft.json", in: artifacts)
            let importedManifest = try semanticRead(importedManifestArtifact.path, artifact: importedManifestArtifact,
                                                    root: root, rawManifestSHA256: input.rawManifestSHA256)
            let favoriteManifest = try semanticRead(favoriteManifestArtifact.path, artifact: favoriteManifestArtifact,
                                                    root: root, rawManifestSHA256: input.rawManifestSHA256)
            let imported = try TransferArchiveCodec.decodeImportedManifest(importedManifest)
            let favorites = try TransferArchiveCodec.decodeFavoriteRouteManifest(favoriteManifest)
            expectedPaths.formUnion([importedManifestArtifact.path, favoriteManifestArtifact.path, draftArtifact.path])

            var importedPoints = 0
            var importedIDs = Set<UUID>()
            for record in imported {
                guard importedIDs.insert(record.id).inserted else { throw TransferFailure.artifactMismatch }
                let path = "routes/imported/\(record.id.uuidString).gpx"
                let artifact = try requireArtifact(path, in: artifacts)
                let data = try semanticRead(path, artifact: artifact, root: root,
                                            rawManifestSHA256: input.rawManifestSHA256)
                try TransferArchiveCodec.validateImportedPayload(data, record: record)
                importedPoints += record.pointCount
                expectedPaths.insert(path)
            }

            var favoriteIDs = Set<UUID>()
            var favoritePoints = 0
            for record in favorites {
                guard favoriteIDs.insert(record.id).inserted else { throw TransferFailure.artifactMismatch }
                let path = "routes/favorites/\(record.id.uuidString).route"
                let artifact = try requireArtifact(path, in: artifacts)
                let data = try semanticRead(path, artifact: artifact, root: root,
                                            rawManifestSHA256: input.rawManifestSHA256)
                try TransferArchiveCodec.validateFavoriteRoutePayload(data, record: record)
                if record.sourceKind == .gpx { favoritePoints += record.count }
                expectedPaths.insert(path)
            }

            let draftData = try semanticRead(draftArtifact.path, artifact: draftArtifact, root: root,
                                             rawManifestSHA256: input.rawManifestSHA256)
            draft = try TransferCodec.decodeDraft(draftData)
            let draftNodes = draft?.isManual == true ? draft?.nodes.count ?? 0 : 0
            let draftPoints = draft?.gpxSource?.document.pointCount ?? 0
            counts = TransferCounts(favorites: counts.favorites, importedRoutes: imported.count,
                                    favoriteRoutes: favorites.count, draftNodes: draftNodes,
                                    gpxPoints: importedPoints + favoritePoints + draftPoints)
        }

        if manifest.categories.contains(.settings) {
            let artifact = try requireArtifact("settings/preferences.json", in: artifacts)
            let data = try semanticRead(artifact.path, artifact: artifact, root: root,
                                        rawManifestSHA256: input.rawManifestSHA256)
            settings = try TransferCodec.decodeSettings(data)
            expectedPaths.insert(artifact.path)
        }

        // A selected category has a closed artifact set. This also rejects
        // valid-looking payloads hidden under an unselected category.
        guard Set(artifacts.keys) == Set(artifacts.keys).intersection(expectedPaths.subtracting(["manifest.json"])) else {
            throw TransferFailure.artifactMismatch
        }
        let inventory = try root.inventory(maxDepth: 4, maxEntries: 512)
        let actualFiles = Set(inventory.filter { !$0.1 }.map(\.0))
        let actualDirectories = Set(inventory.filter(\.1).map(\.0))
        let expectedDirectories = Set(expectedPaths.flatMap(ancestors(of:)))
        guard actualFiles == expectedPaths, actualDirectories == expectedDirectories else {
            throw TransferFailure.artifactMismatch
        }
        return ValidatedTransferPackage(input: input, counts: counts, settings: settings, draft: draft)
    }

    private static func requireArtifact(_ path: String, in artifacts: [String: TransferArtifact]) throws -> TransferArtifact {
        guard let artifact = artifacts[path] else { throw TransferFailure.artifactMismatch }
        return artifact
    }

    private static func archivePayloadBytes(prefix: String, suffix: String,
                                            artifacts: [String: TransferArtifact]) throws -> Int64 {
        var total: Int64 = 0
        for (path, artifact) in artifacts where path.hasPrefix(prefix) && path.hasSuffix(suffix) {
            guard total <= Int64.max - artifact.byteCount else { throw TransferFailure.limitExceeded }
            total += artifact.byteCount
        }
        return total
    }

    private static func semanticRead(_ path: String, artifact: TransferArtifact,
                                     root: _TransferDirectoryHandle,
                                     rawManifestSHA256: String) throws -> Data {
        guard let actual = try root.inspect(path, maximum: maximumBytes(for: path)),
              actual.size == artifact.byteCount, actual.sha256 == artifact.sha256 else {
            throw TransferFailure.artifactMismatch
        }
        guard let manifest = try root.read("manifest.json", maximum: TransferLimits.manifestBytes),
              SetupValidation.sha256(manifest) == rawManifestSHA256 else {
            throw TransferFailure.artifactMismatch
        }
        guard let data = try root.read(path, maximum: maximumBytes(for: path)) else {
            throw TransferFailure.artifactMismatch
        }
        guard Int64(data.count) == artifact.byteCount, SetupValidation.sha256(data) == artifact.sha256 else {
            throw TransferFailure.artifactMismatch
        }
        return data
    }

    private static func maximumBytes(for path: String) -> Int {
        switch path {
        case "favorites/archive.json": return FavoritePlacesLimits.fileBytes
        case "routes/draft.json": return TransferLimits.draftBytes
        case "settings/preferences.json": return TransferLimits.settingsBytes
        case let value where value.hasSuffix(".gpx"): return GPXLimits.fileBytes
        case let value where value.hasSuffix(".route"): return FavoriteRoutesLimits.fileBytes
        case "routes/imported/manifest.json": return ImportedRoutesLimits.manifestBytes
        case "routes/favorites/manifest.json": return FavoriteRoutesLimits.manifestBytes
        default: return TransferLimits.manifestBytes
        }
    }

    private static func ancestors(of path: String) -> [String] {
        let components = path.split(separator: "/").map(String.init)
        guard components.count > 1 else { return [] }
        return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
    }
}
