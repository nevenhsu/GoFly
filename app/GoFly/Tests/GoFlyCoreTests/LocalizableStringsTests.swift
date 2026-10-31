import Foundation
import Testing

/// A malformed .strings file silently drops every key after the error, so each
/// language must parse and carry the same keys.
struct LocalizableStringsTests {
    private static func load(_ language: String) throws -> [String: String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }   // Tests/GoFlyCoreTests/<file> -> app/GoFly
        let data = try Data(contentsOf: url.appendingPathComponent("Resources/\(language).lproj/Localizable.strings"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func everyLanguageParsesAndHasTheSameKeys() throws {
        let en = try Self.load("en")
        for language in ["zh-Hant", "zh-Hans"] {
            let other = try Self.load(language)
            #expect(Set(other.keys).symmetricDifference(Set(en.keys)).isEmpty,
                    "\(language) differs from en: \(Set(other.keys).symmetricDifference(Set(en.keys)).sorted())")
        }
    }
}
