import Foundation
import GoFlyTransport

/// Simulator-only launch-argument overrides. Release and device builds compile
/// the inert variant, so no production argument can select test state.
#if DEBUG && targetEnvironment(simulator)
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func contains(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? {
        guard let namespace = value(flag).flatMap(UUID.init(uuidString:)) else { return nil }
        return root.appendingPathComponent("UITests", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(namespace.uuidString, isDirectory: true)
    }

    static func preferencesDefaults() -> UserDefaults? {
        guard let namespace = value("-gofly-ui-preferences-store").flatMap(UUID.init(uuidString:)),
              let store = UserDefaults(suiteName: "gofly.ui.preferences.\(namespace.uuidString)") else {
            return nil
        }
        if store.object(forKey: "gofly.preferences.v1") == nil {
            store.set([
                "language": value("-gofly-ui-preferences-language") ?? "system",
                "appearance": value("-gofly-ui-preferences-appearance") ?? "system"
            ], forKey: "gofly.preferences.v1")
        }
        return store
    }

    static func tunnelProbe() -> NetworkTunnelProbe? {
        contains("-gofly-ui-unreachable") ? .unavailableUITestProbe : nil
    }
}
#else
enum GoFlyUITestOverrides {
    static func value(_ flag: String) -> String? { nil }
    static func contains(_ flag: String) -> Bool { false }
    static func namespace(_ flag: String, under root: URL, folder: String) -> URL? { nil }
    static func preferencesDefaults() -> UserDefaults? { nil }
    static func tunnelProbe() -> NetworkTunnelProbe? { nil }
}
#endif
