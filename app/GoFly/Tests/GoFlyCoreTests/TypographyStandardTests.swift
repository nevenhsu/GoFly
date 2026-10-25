import Foundation
import Testing

/// docs/IOS-TYPOGRAPHY.md: text uses `GoFlyFont` tokens, two weights, and fixed sizes only for icons.
struct TypographyStandardTests {
    private static func appSources() throws -> [(name: String, lines: [String])] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }   // Tests/GoFlyCoreTests/<file> -> app/GoFly
        let app = url.appendingPathComponent("App")
        let names = try FileManager.default.contentsOfDirectory(atPath: app.path).filter { $0.hasSuffix(".swift") }.sorted()
        return try names.map { name in
            (name, try String(contentsOf: app.appendingPathComponent(name), encoding: .utf8).components(separatedBy: "\n"))
        }
    }

    /// Files whose fixed font sizes are icon or artwork geometry.
    private static let geometryFiles: Set<String> = ["GoFlySymbols.swift", "GoFlyMapCanvas.swift", "GoFlySetupBootstrap.swift",
                                                     "GoFlyOnboardingView.swift", "GoFlyStyle.swift", "GoFlyComponentGallery.swift"]

    @Test func textNeverUsesRawTextStylesOrMediumAndBoldWeights() throws {
        let raw = try NSRegularExpression(pattern: #"\.font\(\.(footnote|body|subheadline|headline|caption2?|title[23]?)\b"#)
        let weights = try NSRegularExpression(pattern: #"\.font\(.*\.weight\(\.(medium|bold|light|heavy)\)"#)
        for source in try Self.appSources() where source.name != "GoFlyStyle.swift" {
            for (index, line) in source.lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                #expect(raw.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a raw text style; use GoFlyFont")
                #expect(weights.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a weight other than regular or semibold")
            }
        }
    }

    @Test func fixedSizesAppearOnlyNextToIcons() throws {
        for source in try Self.appSources() where !Self.geometryFiles.contains(source.name) {
            for (index, line) in source.lines.enumerated() where line.contains(".font(.system(size:") {
                let context = source.lines[max(0, index - 5)...index].joined(separator: "\n")
                #expect(context.contains("Image(") || context.contains("Canvas") || context.contains("Label("),
                        "\(source.name):\(index + 1) uses a fixed font size outside an icon; use GoFlyFont")
            }
        }
    }

    @Test func textColorsComeFromTheTextColorSet() throws {
        let allowed = ["GoFlyTextColor.", "tone.", "GoFlyStyle.success", "GoFlyStyle.danger", "GoFlyStyle.warning", "foreground)", "(foreground"]
        let raw = try NSRegularExpression(pattern: #"\.foreground(Style|Color)\((\.(primary|secondary|white|black|gray)|Color\.|Color\(|GoFlyStyle\.(primary|secondary|surface|disabledForeground|errorForeground))"#)
        for source in try Self.appSources() where !["GoFlyStyle.swift", "GoFlySetupBootstrap.swift", "GoFlyComponentGallery.swift"].contains(source.name) {
            for (index, line) in source.lines.enumerated() where line.contains(".foregroundStyle(") || line.contains(".foregroundColor(") {
                let range = NSRange(line.startIndex..., in: line)
                #expect(raw.firstMatch(in: line, range: range) == nil, "\(source.name):\(index + 1) uses a raw color; use GoFlyTextColor")
                #expect(allowed.contains { line.contains($0) }, "\(source.name):\(index + 1) is not a GoFlyTextColor role")
            }
        }
    }
}
