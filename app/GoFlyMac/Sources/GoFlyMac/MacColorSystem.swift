import AppKit
import SwiftUI

/// Mac-only semantic color tokens. Keep this palette independent from the iOS
/// app so a future Mac theme can change here without changing app/GoFly.
enum MacColorSystem {
    static let canvas = adaptive(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let sidebar = adaptive(light: 0xF5F5F7, dark: 0x2C2C2E)
    static let surface = adaptive(light: 0xF5F5F7, dark: 0x2C2C2E)
    static let controlSurface = adaptive(light: 0xE9E9EB, dark: 0x3A3A3C)
    static let disabledSurface = adaptive(light: 0xF2F2F7, dark: 0x2C2C2E)
    static let progressPendingIndicator = adaptive(light: 0xE8E8ED, dark: 0x3A3A3C)
    static let progressActiveIndicator = adaptive(light: 0x000000, dark: 0x171717)
    static let progressActiveGlyph = adaptive(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let inputSurface = adaptive(light: 0xF5F5F7, dark: 0x1C1C1E)

    static let primaryText = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let secondaryText = adaptive(light: 0x6E6E73, dark: 0x98989D)
    static let disabledText = adaptive(light: 0xAEAEB2, dark: 0x636366)
    static let separator = adaptive(light: 0xE5E5EA, dark: 0x38383A)
    static let border = adaptive(light: 0xD1D1D6, dark: 0x48484A)
    static let inputBorder = adaptive(light: 0xC7C7CC, dark: 0x48484A)
    static let selectionSurface = adaptive(light: 0xFFFFFF, dark: 0x3A3A3C)

    static let info = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    static let infoSurface = adaptive(light: 0xE5F2FF, dark: 0x182B40)
    static let infoBorder = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    static let warningSurface = adaptive(light: 0xFFF4E5, dark: 0x3A2B16)
    static let warningBorder = adaptive(light: 0xFF9F0A, dark: 0xFF9F0A)
    static let mockWindow = adaptive(light: 0xE9E9EB, dark: 0x303033)
    static let mockContent = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let mockControl = adaptive(light: 0xF2F2F7, dark: 0x3A3A3C)
    static let deviceMockFrame = Color(nsColor: color(0x1C1C1E))
    static let deviceMockScreen = adaptive(light: 0xE5E5EA, dark: 0x3A3A3C)
    static let deviceMockCard = adaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let accent = adaptive(light: 0x007AFF, dark: 0x0A84FF)
    static let accentText = Color(nsColor: color(0xFFFFFF))
    static let annotation = adaptive(light: 0xFF9F0A, dark: 0xFF9F0A)

    static let primaryActionSurface = adaptive(light: 0x000000, dark: 0xFFFFFF)
    static let primaryActionText = adaptive(light: 0xFFFFFF, dark: 0x000000)
    static let brandMarkSurface = Color(nsColor: color(0x000000))
    static let brandMark = Color(nsColor: color(0xFFFFFF))

    static let success = adaptive(light: 0x34C759, dark: 0x30D158)
    static let successSurface = adaptive(light: 0xEAF8EE, dark: 0x1D3225)
    static let warning = adaptive(light: 0xFF9F0A, dark: 0xFF9F0A)
    static let error = adaptive(light: 0xFF3B30, dark: 0xFF453A)
    static let errorSurface = adaptive(light: 0xFFF0EF, dark: 0x3A2220)
    static let errorBorder = adaptive(light: 0xFF3B30, dark: 0xFF453A)
    static let transparent = Color.clear

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return color(isDark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
