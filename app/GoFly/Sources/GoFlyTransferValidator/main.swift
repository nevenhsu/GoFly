import Darwin
import Foundation
import GoFlyCore

private func identity(_ value: SetupAppIdentity) -> [String: String] {
    ["bundleID": value.bundleID, "build": value.build,
     "profileSHA256": value.profileSHA256, "executableSHA256": value.executableSHA256]
}

private func validate() throws -> Data {
    let arguments = CommandLine.arguments
    guard arguments.count == 3, arguments[1] == "validate", arguments[2].hasPrefix("/") else {
        throw TransferFailure.invalidInput
    }
    let package = try TransferPackageValidator.validate(directory: URL(fileURLWithPath: arguments[2], isDirectory: true))
    let manifest = package.input.manifest
    let counts = package.counts
    let output: [String: Any] = [
        "version": 1,
        "transferID": manifest.transferID.uuidString.lowercased(),
        "dataSetID": manifest.dataSetID.uuidString.lowercased(),
        "nonce": manifest.nonce.uuidString.lowercased(),
        "sourceDeviceUDID": manifest.sourceDeviceUDID,
        "destinationDeviceUDID": manifest.destinationDeviceUDID,
        "sourceApp": identity(manifest.sourceApp), "targetApp": identity(manifest.targetApp),
        "setupID": manifest.setupID.uuidString.lowercased(),
        "categories": manifest.categories.map(\.rawValue),
        "rawManifestSHA256": package.input.rawManifestSHA256,
        "counts": ["favorites": counts.favorites, "importedRoutes": counts.importedRoutes,
                   "favoriteRoutes": counts.favoriteRoutes, "draftNodes": counts.draftNodes,
                   "gpxPoints": counts.gpxPoints]
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes])
    guard data.count < 262_144 else { throw TransferFailure.limitExceeded }
    return data + Data([10])
}

do {
    FileHandle.standardOutput.write(try validate())
} catch {
    // No paths, input content, or dependency diagnostics cross this boundary.
    let code = error as? TransferFailure == .invalidInput ? "invalid-input" : "backup-invalid"
    FileHandle.standardError.write(Data("\(code)\n".utf8))
    exit(1)
}
