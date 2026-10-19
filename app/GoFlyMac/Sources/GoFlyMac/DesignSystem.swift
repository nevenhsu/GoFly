import SwiftUI
import AppKit

enum GoFlyStyle {
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let line = Color(nsColor: .separatorColor)
    static let divider = Color(nsColor: .separatorColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondarySurface = Color(nsColor: .controlColor)
    static let inputSurface = adaptive(light: 0.93, dark: 0.16)
    static let inputBorder = adaptive(light: 0.58, dark: 0.48)
    static let cornerRadius: CGFloat = 16

    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .semibold : .regular)
    }

    private static func adaptive(light: CGFloat, dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(calibratedWhite: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }
}

enum GoFlyMacSymbols {
    static let home = "house"
    static let environment = "checklist"
    static let device = "iphone"
    static let install = "square.and.arrow.down"
    static let signing = "signature"
    static let repair = "wrench.and.screwdriver"
    static let connection = "network"
    static let completed = "checkmark.circle.fill"
    static let reinstall = "arrow.triangle.2.circlepath"
    static let usb = "cable.connector"
    static let wifi = "wifi"
}

private struct GoFlyInset: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(GoFlyStyle.line, lineWidth: 0.5) }
    }
}

private struct GoFlyInput: ViewModifier {
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.textFieldStyle(.plain)
            .font(GoFlyStyle.font(13))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.inputBorder, lineWidth: focused ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
            .focused($focused)
            .opacity(isEnabled ? 1 : 0.6)
    }
}

extension View {
    func goFlyInput() -> some View { modifier(GoFlyInput()) }
    func goFlyInset() -> some View { modifier(GoFlyInset()) }
    func goFlyRowFocus() -> some View { modifier(GoFlyRowFocus()) }
}

private struct GoFlyRowFocus: ViewModifier {
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.focused($focused)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.line,
                                  lineWidth: focused ? 2 : 1)
                    .padding(focused ? -3 : 0)
                    .opacity(isEnabled && (focused || hovered) ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onHover { hovered = $0 }
    }
}

struct DesignAsset: View {
    let name: String
    let size: CGSize
    init(_ name: String, width: CGFloat, height: CGFloat? = nil) {
        self.name = name; self.size = CGSize(width: width, height: height ?? width)
    }
    var body: some View {
        if let symbol = symbol {
            Image(systemName: symbol)
                .font(.system(size: min(size.width, size.height) * 0.78, weight: .regular))
                .frame(width: size.width, height: size.height)
                .foregroundStyle(GoFlyStyle.ink)
                .accessibilityHidden(true)
        } else if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().renderingMode(.template).aspectRatio(contentMode: .fit)
                .frame(width: name == "WingedArrow" ? size.width * 0.640625 : size.width,
                       height: name == "WingedArrow" ? size.height * 0.515625 : size.height)
                .frame(width: size.width, height: size.height).foregroundStyle(GoFlyStyle.ink).accessibilityHidden(true)
        }
    }

    private var symbol: String? {
        switch name {
        case "Device": GoFlyMacSymbols.device
        case "USB": GoFlyMacSymbols.usb
        case "EnvironmentPassed": GoFlyMacSymbols.completed
        default: nil
        }
    }
}

private struct GoFlyMacButtonStyle: ButtonStyle {
    let primary: Bool
    let focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? (primary ? GoFlyStyle.surface : GoFlyStyle.ink) : GoFlyStyle.muted)
            .background(isEnabled && primary ? GoFlyStyle.ink : GoFlyStyle.secondarySurface,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(focused ? GoFlyStyle.ink : GoFlyStyle.line, lineWidth: focused ? 2 : 0.75)
                    .padding(focused ? -3 : 0)
                    .allowsHitTesting(false)
            }
            .opacity(!isEnabled ? 0.6 : configuration.isPressed ? 0.72 : hovered ? 0.86 : 1)
            .onHover { hovered = $0 }
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    var width: CGFloat? = 208
    var height: CGFloat = 36
    var enabled = true
    let action: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            Text(title).font(GoFlyStyle.font(13, bold: true))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: height)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(GoFlyMacButtonStyle(primary: primary, focused: focused))
        .disabled(!enabled).focused($focused).frame(width: width)
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(GoFlyStyle.font(14, bold: true)).foregroundStyle(GoFlyStyle.ink)
            Text(detail).font(GoFlyStyle.font(13)).foregroundStyle(GoFlyStyle.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 200, maxHeight: .infinity)
        .scrollBounceBehavior(.basedOnSize)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius).strokeBorder(GoFlyStyle.line, lineWidth: 0.75))
    }
}

struct Rule: View { var body: some View { Rectangle().fill(GoFlyStyle.divider).frame(height: 1) } }
