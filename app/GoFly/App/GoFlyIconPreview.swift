#if DEBUG && targetEnvironment(simulator)
import GoFlyCore
import SwiftUI
import UIKit

/// Component-only inspection. This screen never creates a GPS fix, a movement
/// task, or a device acknowledgement, and is absent from the device build.
struct GoFlyIconPreview: View {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-gofly-ui-icon-preview")
    let bootstrapIsIdle: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    private var chinese: Bool { GoFlyPreferences.shared.effectiveLanguage.hasPrefix("zh") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chinese ? "圖示與輸入元件" : "Icons & input")
                        .font(.title2.bold())
                        .accessibilityIdentifier("iconPreview.title")
                    Text(chinese ? "元件預覽・不代表裝置、GPS 或 ACK 驗證" : "Component preview · no device, GPS or ACK verification")
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("iconPreview.scope")
                    Text(missingSymbols.isEmpty ? "SF Symbols: OK" : "Missing: \(missingSymbols.joined(separator: ", "))")
                        .font(.caption)
                        .accessibilityIdentifier("iconPreview.symbolAvailability")
                    Text("\(GoFlyPreferences.shared.effectiveLanguage) · \(colorScheme == .dark ? "dark" : "light")")
                        .font(.caption)
                        .accessibilityIdentifier("iconPreview.presentation")
                    Text(bootstrapIsIdle ? "Startup: idle" : "Startup: active")
                        .font(.caption)
                        .accessibilityIdentifier("iconPreview.startup")
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(chinese ? "位置箭頭" : "Position arrows")
                    HStack(spacing: 12) {
                        positionCard(source: .gps, title: chinese ? "目前位置" : "Current position")
                        positionCard(source: .simulation, title: chinese ? "模擬位置" : "Simulated position")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(chinese ? "地點圖釘" : "Place pins")
                    HStack(spacing: 24) {
                        VStack(spacing: 8) {
                            GoFlyPlacePinIcon(kind: .candidate).frame(width: 44, height: 44)
                            Text(chinese ? "候選地點" : "Candidate")
                        }
                        VStack(spacing: 8) {
                            GoFlyPlacePinIcon(kind: .destination).frame(width: 44, height: 44)
                            Text(chinese ? "漫遊目的地" : "Wander destination")
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .goFlyCard()
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(chinese ? "常用操作" : "Common actions")
                    HStack(spacing: 12) {
                        iconButton(GoFlySymbols.recenter, title: goFlyString("map.currentLocation"), id: "recenter")
                        iconButton(GoFlySymbols.settings, title: goFlyString("settings.title"), id: "settings")
                        iconButton(GoFlySymbols.favorite, title: goFlyString("favorites.title"), id: "favorite")
                        iconButton(GoFlySymbols.play, title: goFlyString("service.start"), id: "play")
                        iconButton(GoFlySymbols.pause, title: goFlyString("map.pause"), id: "pause")
                    }
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(chinese ? "搜尋輸入" : "Search input")
                    HStack(spacing: 8) {
                        Image(systemName: GoFlySymbols.search)
                            .goFlyControlSymbol(size: 18, maximum: 22)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .accessibilityHidden(true)
                        TextField(goFlyString("search.placeholder"), text: $query,
                                  prompt: Text(goFlyString("search.placeholder")).foregroundStyle(GoFlyStyle.secondary))
                            .font(.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("iconPreview.search")
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius)
                            .strokeBorder(GoFlyStyle.inputBorder, lineWidth: 0.75)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(chinese ? "符號目錄" : "Symbol catalog")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 16) {
                        ForEach(Self.symbols, id: \.self) { name in
                            Image(systemName: name)
                                .goFlyControlSymbol()
                                .frame(width: 44, height: 44)
                                .accessibilityLabel(name)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(GoFlyStyle.canvas.ignoresSafeArea())
        .accessibilityIdentifier("iconPreview")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private func positionCard(source: PositionSource, title: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    GoFlyPositionArrowPreview(source: source, freshness: .fresh, bearingDegrees: 25)
                        .frame(width: 40, height: 44)
                        .accessibilityHidden(true)
                    Text(chinese ? "即時" : "Fresh")
                }
                VStack(spacing: 4) {
                    GoFlyPositionArrowPreview(source: source, freshness: .waiting)
                        .frame(width: 40, height: 44)
                        .accessibilityHidden(true)
                    Text(chinese ? "等待" : "Waiting")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .goFlyCard()
    }

    private func iconButton(_ symbol: String, title: String, id: String) -> some View {
        Button { } label: { Image(systemName: symbol) }
            .buttonStyle(GoFlyIconStyle())
            .accessibilityLabel(title)
            .accessibilityIdentifier("iconPreview.control.\(id)")
    }

    private var missingSymbols: [String] { Self.symbols.filter { UIImage(systemName: $0) == nil } }

    // Deliberately covers every role in the production catalog; availability is
    // evaluated by UIKit on the running simulator rather than inferred from names.
    private static let symbols = [
        GoFlySymbols.recenter, GoFlySymbols.location, GoFlySymbols.sample, GoFlySymbols.place,
        GoFlySymbols.coordinates, GoFlySymbols.map, GoFlySymbols.favorite, GoFlySymbols.favoriteSelected,
        GoFlySymbols.search, GoFlySymbols.clearSearch, GoFlySymbols.settings, GoFlySymbols.adjustments,
        GoFlySymbols.close, GoFlySymbols.disclosure, GoFlySymbols.expand, GoFlySymbols.selected,
        GoFlySymbols.checked, GoFlySymbols.unchecked, GoFlySymbols.play, GoFlySymbols.pause,
        GoFlySymbols.add, GoFlySymbols.delete, GoFlySymbols.reorder, GoFlySymbols.importFile,
        GoFlySymbols.exportFile, GoFlySymbols.externalLink, GoFlySymbols.retry, GoFlySymbols.warning,
        GoFlySymbols.success, GoFlySymbols.information, GoFlySymbols.help, GoFlySymbols.network,
        GoFlySymbols.device, GoFlySymbols.language, GoFlySymbols.appearance, GoFlySymbols.background,
        GoFlySymbols.service, GoFlySymbols.storage, GoFlySymbols.locked, GoFlySymbols.route,
        GoFlySymbols.importEmpty, GoFlySymbols.manualMovement, GoFlySymbols.walking,
        GoFlySymbols.heading, GoFlySymbols.waiting
    ]
}
#endif
