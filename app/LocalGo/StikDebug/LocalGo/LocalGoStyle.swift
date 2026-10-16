import SwiftUI
import UIKit

/// Shared native appearance for the map, places, and settings.
enum LocalGoStyle {
    static let accent = adaptive(0x285C4D, 0xA2D5BA)
    static let ink = adaptive(0x1B3029, 0xEDF4EF)
    static let muted = adaptive(0x61716A, 0xA6B6AD)
    static let paper = adaptive(0xF2F5F1, 0x142019)
    static let surface = adaptive(0xFCFDFB, 0x203027)
    static let recessed = adaptive(0xE9EFE8, 0x2B3C31)
    static let danger = adaptive(0xA33E37, 0xF2AAA1)
    static let warning = adaptive(0x805916, 0xE4C483)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

struct LocalGoButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet, danger }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ kind: Kind = .secondary) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return LocalGoStyle.paper
        case .danger: return LocalGoStyle.danger
        case .secondary, .quiet: return LocalGoStyle.accent
        }
    }
    private var background: Color {
        switch kind {
        case .primary: return LocalGoStyle.accent
        case .secondary: return LocalGoStyle.recessed
        case .quiet: return .clear
        case .danger: return LocalGoStyle.danger.opacity(0.1)
        }
    }
}

struct LocalGoIconButtonStyle: ButtonStyle {
    var active = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(destructive ? LocalGoStyle.danger : (active ? LocalGoStyle.paper : LocalGoStyle.ink))
            .background(destructive ? LocalGoStyle.danger.opacity(0.1) : (active ? LocalGoStyle.accent : LocalGoStyle.recessed), in: Circle())
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
