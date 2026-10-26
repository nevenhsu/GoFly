import SwiftUI
import UIKit

struct GoFlyMapSearchBar: View {
    let text: String
    let hasContent: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    let onPaste: (String) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button(action: onSearch) {
                    HStack(spacing: 10) {
                        Image(systemName: GoFlySymbols.search)
                            .goFlyControlSymbol(size: 20, maximum: 20, weight: .medium)
                            .foregroundStyle(GoFlyTextColor.secondary)
                        Text(text)
                            .font(GoFlyFont.body)
                            .foregroundStyle(hasContent ? GoFlyTextColor.primary : GoFlyTextColor.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(goFlyString("search.placeholder"))
                .accessibilityValue(hasContent ? text : "")
                .accessibilityHint(goFlyString("map.searchHint"))
                .accessibilityIdentifier("map.searchBar")

                if hasContent {
                    Button(action: onClear) {
                        Image(systemName: GoFlySymbols.clearSearch)
                            .goFlyControlSymbol(size: 16, maximum: 18, weight: .medium)
                            .foregroundStyle(GoFlyTextColor.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(goFlyString("search.clear"))
                    .accessibilityIdentifier("map.searchClear")
                    .padding(.trailing, 6)
                } else {
                    GoFlyPasteControl(accessibilityLabel: goFlyString("search.paste"),
                                      accessibilityIdentifier: "map.searchPaste",
                                      backgroundColor: UIColor(GoFlyStyle.cardSurface),
                                      symbolPointSize: 20,
                                      symbolColor: UIColor(GoFlyGrayScale.pasteSymbol),
                                      onPaste: onPaste)
                        .frame(width: 44, height: 44)
                        .padding(.trailing, 6)
                }
            }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
            .goFlyShadow(.floating)

            Button(action: onSettings) {
                // Figma 04 · Settings / 設定 > icon / gear.
                Image("SettingsGear")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(GoFlyTextColor.primary)
                    .frame(width: 50, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("settings.title"))
            .accessibilityIdentifier("map.settings")
            .background(GoFlyStyle.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(GoFlyStyle.subtleBorder, lineWidth: 0.5)
            }
            .goFlyShadow(.floating)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
    }
}
