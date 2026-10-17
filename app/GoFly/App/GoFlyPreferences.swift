import Foundation
import Observation
import SwiftUI

enum GoFlyLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case zhHant = "zh-Hant"
    case zhHans = "zh-Hans"

    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: goFlyString("settings.system")
        case .en: "English"
        case .zhHant: "繁體中文"
        case .zhHans: "简体中文"
        }
    }
}

enum GoFlyAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .system: goFlyString("settings.system")
        case .light: goFlyString("settings.appearance.light")
        case .dark: goFlyString("settings.appearance.dark")
        }
    }
}

/// Selected presentation values only. Reading preferences never changes disk or movement owners.
@MainActor @Observable
final class GoFlyPreferences {
    static let shared = GoFlyPreferences()
    private(set) var language: GoFlyLanguage
    private(set) var appearance: GoFlyAppearance
    private var systemLanguages: [String]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "gofly.preferences.v1"

    private init() {
        var store = UserDefaults.standard
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-gofly-ui-preferences-store"),
           arguments.indices.contains(index + 1),
           let namespace = UUID(uuidString: arguments[index + 1]),
           let isolated = UserDefaults(suiteName: "gofly.ui.preferences.\(namespace.uuidString)") {
            store = isolated
            if store.object(forKey: Self.storageKey) == nil {
                func initialValue(_ flag: String) -> String {
                    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                        return "system"
                    }
                    return arguments[index + 1]
                }
                store.set([
                    "language": initialValue("-gofly-ui-preferences-language"),
                    "appearance": initialValue("-gofly-ui-preferences-appearance")
                ], forKey: Self.storageKey)
            }
        }
        #endif
        defaults = store
        let saved = store.dictionary(forKey: Self.storageKey)
        language = (saved?["language"] as? String).flatMap(GoFlyLanguage.init(rawValue:)) ?? .system
        appearance = (saved?["appearance"] as? String).flatMap(GoFlyAppearance.init(rawValue:)) ?? .system
        systemLanguages = Locale.preferredLanguages
    }

    var effectiveLanguage: String {
        if language != .system { return language.rawValue }
        return Bundle.preferredLocalizations(
            from: ["en", "zh-Hant", "zh-Hans"], forPreferences: systemLanguages
        ).first ?? "en"
    }

    var locale: Locale { Locale(identifier: effectiveLanguage) }
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func setLanguage(_ value: GoFlyLanguage) {
        guard language != value else { return }
        language = value
        save()
    }

    func setAppearance(_ value: GoFlyAppearance) {
        guard appearance != value else { return }
        appearance = value
        save()
    }

    func refreshSystemPreferences() {
        systemLanguages = Locale.preferredLanguages
    }

    private func save() {
        defaults.set(["language": language.rawValue, "appearance": appearance.rawValue], forKey: Self.storageKey)
    }
}
