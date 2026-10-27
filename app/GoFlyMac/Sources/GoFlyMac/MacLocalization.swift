import Foundation
import GoFlyMacCore

enum MacLocalization {
    static func text(_ key: String) -> String {
#if DEBUG
        if let language = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--capture-language=") })?
            .replacingOccurrences(of: "--capture-language=", with: ""),
           let path = Bundle.module.path(forResource: language, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(forKey: key, value: key, table: nil)
        }
#endif
        return Bundle.module.localizedString(forKey: key, value: key, table: nil)
    }

    static func teamSummary(_ team: MacTeam?) -> String {
        guard let team else { return text("device.team.pending") }
        let kind = text(team.isFreeProvisioningTeam ? "env.e08.free.label" : "env.e08.paid.label")
        let key = team.isFreeProvisioningTeam ? "device.team.free.summary" : "device.team.paid.summary"
        return String(format: text(key), team.teamName, kind)
    }

    static func teamIdentitySummary(_ team: MacTeam?) -> String {
        guard let team else { return text("device.team.pending") }
        let kind = text(team.isFreeProvisioningTeam ? "env.e08.free.label" : "env.e08.paid.label")
        return String(format: text("device.team.identity.summary"), team.teamName, kind)
    }

    static func projectVersion(version rawVersion: String?, build: String?) -> String {
        guard let rawVersion else { return text("device.version.pending") }
        let version = rawVersion.hasSuffix(".0") ? String(rawVersion.dropLast(2)) : rawVersion
        return String(format: text("device.version.summary"), version, build ?? "—")
    }

    static func deviceModelName(_ modelName: String?, fallback: String) -> String {
        guard let modelName, modelName.contains(" ") else { return fallback }
        return modelName
    }
}
