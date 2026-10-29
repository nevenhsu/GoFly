import Foundation
import Testing

/// Button labels stay one English word so they never wrap or overflow their capsule.
struct EnglishButtonLabelTests {
    private static let buttonKeys = [
        "route.resumeShort", "teleport.resumeShort", "wander.resumeShort", "route.cancelConfirmation.confirm",
        "route.cancelConfirmation.return", "route.start", "route.startShort", "route.cancel", "route.addStop",
        "route.viewList", "route.exchange", "route.clearRoute", "wifi.error.action", "operation.settings", "operation.return",
        "operation.cancel", "onboarding.location.allow", "onboarding.location.openSettings",
        "onboarding.location.continue", "onboarding.vpn.open", "settings.vpn.check",
        "settings.vpn.openLocalDevVPN", "settings.diagnostics.export", "setup.retry", "service.reset",
        "imports.import", "imports.load", "imports.deleteAction", "search.clearHistory",
        "placeDetails.setStart", "placeDetails.setEnd", "joystick.startWander", "joystick.stopWander",
        "favorites.selectAll", "toast.restore", "operation.retry", "common.retry", "common.undo", "common.confirm", "route.pause", "route.resume"
    ]

    @Test func everyButtonLabelIsASingleEnglishWord() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }   // Tests/GoFlyCoreTests/<file> -> app/GoFly
        let text = try String(contentsOf: url.appendingPathComponent("Resources/en.lproj/Localizable.strings"), encoding: .utf8)
        var strings: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ;\"")) }
            if parts.count == 2 { strings[parts[0]] = parts[1] }
        }
        for key in Self.buttonKeys {
            let value = try #require(strings[key], "missing \(key)")
            let words = value.split(whereSeparator: { $0 == " " }).filter { !["＋", "›", "+"].contains(String($0)) }
            #expect(words.count == 1, "\(key) = “\(value)” should be one word")
            #expect(value.count <= 12, "\(key) = “\(value)” is too long for a button")
        }
    }

    /// Toast and snackbar buttons are at most two Chinese characters.
    private static let toastKeys = ["operation.settings", "operation.retry", "common.retry", "common.undo",
                                    "imports.undo", "imports.load", "toast.restore", "wifi.error.action"]

    @Test func toastButtonsAreAtMostTwoChineseCharacters() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        for language in ["zh-Hant", "zh-Hans"] {
            let text = try String(contentsOf: url.appendingPathComponent("Resources/\(language).lproj/Localizable.strings"), encoding: .utf8)
            var strings: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ;\"")) }
                if parts.count == 2 { strings[parts[0]] = parts[1] }
            }
            for key in Self.toastKeys {
                let value = try #require(strings[key], "missing \(key) in \(language)")
                #expect(value.count <= 2, "\(language) \(key) = “\(value)” should be at most two characters")
            }
        }
    }
}
