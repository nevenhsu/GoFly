import Foundation
import GoFlyCore
import Testing

struct GoFlyColorTokenTests {
    private struct ColorSchemeDocument: Decodable {
        struct Colors: Decodable {
            struct FigmaVariables: Decodable {
                let lightTheme: [String: String]
                let darkTheme: [String: String]
                let commonColor: [String: String]
            }

            let figmaVariables: FigmaVariables
        }

        let colors: Colors
    }

    private func readSnapshot() throws -> ColorSchemeDocument.Colors.FigmaVariables {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() } // app/GoFly/Tests/GoFlyCoreTests/<file> -> repo root
        let url = root.appendingPathComponent("docs/IOS-COLOR-SCHEME.json")
        return try JSONDecoder().decode(ColorSchemeDocument.self, from: Data(contentsOf: url))
            .colors.figmaVariables
    }

    @Test func everyThemeAndCommonTokenMatchesTheFigmaSnapshot() throws {
        let snapshot = try readSnapshot()
        let themeTokens = GoFlyColorTokens.all.filter { $0.name.hasPrefix("color/") }
        let commonTokens = GoFlyColorTokens.all.filter { $0.name.hasPrefix("common/") }

        #expect(Set(snapshot.lightTheme.keys) == Set(themeTokens.map(\.name)))
        #expect(Set(snapshot.darkTheme.keys) == Set(themeTokens.map(\.name)))
        #expect(Set(snapshot.commonColor.keys) == Set(commonTokens.map(\.name)))

        for token in themeTokens {
            #expect(snapshot.lightTheme[token.name] == token.lightHex, "Light \(token.name)")
            #expect(snapshot.darkTheme[token.name] == token.darkHex, "Dark \(token.name)")
        }
        for token in commonTokens {
            #expect(snapshot.commonColor[token.name] == token.lightHex, "Common \(token.name)")
            #expect(token.lightHex == token.darkHex, "Common token must not vary by appearance: \(token.name)")
        }
    }

    @Test func changingAppearanceImmediatelySelectsTheMatchingPalette() {
        var appearance = GoFlyColorAppearance.light
        #expect(GoFlyColorTokens.hex(named: "color/canvas", appearance: appearance) == "#EEEEF3")

        appearance = .dark
        #expect(GoFlyColorTokens.hex(named: "color/canvas", appearance: appearance) == "#0B0B0D")
        #expect(GoFlyColorTokens.hex(named: "color/surface/control/active", appearance: appearance) == "#48484D")
    }
}
