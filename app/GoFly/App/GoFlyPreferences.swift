import Foundation
import GoFlyCore
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
    private var transferHold: UUID?
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "gofly.preferences.v1"

    private init() {
        let store = GoFlyUITestOverrides.preferencesDefaults() ?? UserDefaults.standard
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
        guard transferHold == nil, language != value else { return }
        language = value
        save()
    }

    func setAppearance(_ value: GoFlyAppearance) {
        guard transferHold == nil, appearance != value else { return }
        appearance = value
        save()
    }

    /// The transfer coordinator owns this private synchronous admission. It
    /// prevents a preference write from racing the accepted export cutline.
    func acquireTransferHold() -> UUID? {
        guard transferHold == nil else { return nil }
        let hold = UUID()
        transferHold = hold
        return hold
    }

    @discardableResult
    func releaseTransferHold(_ hold: UUID) -> Bool {
        guard transferHold == hold else { return false }
        transferHold = nil
        return true
    }

    /// Re-reads the one persisted preferences dictionary after Core activates
    /// a restore. Unknown keys and the restore marker stay in UserDefaults;
    /// this method only refreshes the presentation projection.
    func refreshPersistedValues() {
        let saved = defaults.dictionary(forKey: Self.storageKey)
        if let value = saved?["language"] as? String,
           let decoded = GoFlyLanguage(rawValue: value) { language = decoded }
        if let value = saved?["appearance"] as? String,
           let decoded = GoFlyAppearance(rawValue: value) { appearance = decoded }
    }

    func transferStore() -> TransferPreferencesStore {
        TransferPreferencesStore(defaults: defaults, storageKey: Self.storageKey)
    }

    func refreshSystemPreferences() {
        systemLanguages = Locale.preferredLanguages
    }

    private func save() {
        var dictionary = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        dictionary["language"] = language.rawValue
        dictionary["appearance"] = appearance.rawValue
        defaults.set(dictionary, forKey: Self.storageKey)
    }
}
