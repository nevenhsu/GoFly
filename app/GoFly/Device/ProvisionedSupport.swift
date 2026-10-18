import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)

enum SupportMountMethod: String { case personalized, cryptex }

struct ProvisionedSupport {
    let directory: URL

    init(method: SupportMountMethod) throws {
        let formalDirectory: URL?
        do {
            let setupMethod: SetupSupportMethod = method == .cryptex ? .cryptex : .personalized
            formalDirectory = try SetupActivationStore(directory: try GoFlySetupPaths.directory())
                .activeSupportDirectory(method: setupMethod)
        } catch {
            throw DeviceServiceFailure.devicePreparationRequired
        }

        if let formalDirectory {
            directory = formalDirectory
        } else {
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw DeviceServiceFailure.devicePreparationRequired
            }
            directory = documents.appendingPathComponent("DDI", isDirectory: true)
        }
        let files = ["MountMethod", "BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
            + (method == .cryptex ? ["Image.dmg.cryptex_info", "Image.dmg.root_hash"] : [])
        let directoryValues = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues?.isDirectory == true, directoryValues?.isSymbolicLink != true else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
        for name in files {
            let values = try? directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  let size = values?.fileSize, size > 0 else { throw DeviceServiceFailure.devicePreparationRequired }
        }
        guard (try? String(contentsOf: directory.appendingPathComponent("MountMethod"), encoding: .utf8)) == method.rawValue else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
    }

    func data(_ name: String) throws -> Data {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name), options: [.mappedIfSafe]), !data.isEmpty else {
            throw DeviceServiceFailure.devicePreparationRequired
        }
        return data
    }
}

#endif
