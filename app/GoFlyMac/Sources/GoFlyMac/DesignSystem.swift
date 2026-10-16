import SwiftUI
import AppKit

enum GoFlyStyle {
    static let ink = Color.black
    static let muted = Color(white: 0.45)
    static let line = Color(white: 0.78)
    static let divider = Color(white: 0.87)
    static let sidebar = Color(white: 0.97)
    static func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom("Noto Sans TC", size: size).weight(bold ? .bold : .regular)
    }
}

struct DesignAsset: View {
    let name: String
    let size: CGSize
    init(_ name: String, width: CGFloat, height: CGFloat? = nil) {
        self.name = name; self.size = CGSize(width: width, height: height ?? width)
    }
    var body: some View {
        if let url = Bundle.module.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .frame(width: name == "WingedArrow" ? size.width * 0.640625 : size.width,
                       height: name == "WingedArrow" ? size.height * 0.515625 : size.height)
                .frame(width: size.width, height: size.height).accessibilityHidden(true)
        }
    }
}

struct PillButton: View {
    let title: String
    var primary = false
    var width: CGFloat? = 240
    var height: CGFloat = 48
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(GoFlyStyle.font(15, bold: true))
                .frame(maxWidth: .infinity).frame(height: height)
                .foregroundStyle(!enabled ? Color(white: 0.55) : primary ? .white : .black)
                .background(!enabled ? Color(white: 0.93) : primary ? .black : .white, in: Capsule())
                .overlay(Capsule().strokeBorder(primary || !enabled ? .clear : GoFlyStyle.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).disabled(!enabled).frame(width: width)
    }
}

struct StatusRow: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(GoFlyStyle.font(16, bold: true)).foregroundStyle(.black)
            Text(detail).font(GoFlyStyle.font(13)).foregroundStyle(Color(white: 0.4))
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(GoFlyStyle.line, lineWidth: 1))
    }
}

struct Rule: View { var body: some View { Rectangle().fill(GoFlyStyle.divider).frame(height: 1) } }
