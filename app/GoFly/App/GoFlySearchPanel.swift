import GoFlyCore
import SwiftUI

struct GoFlySearchPanel: View {
    @ObservedObject var search: CandidateController
    var maximumHeight: CGFloat
    var focusRequest: UUID?
    var onFavorites: () -> Void
    var favoritesVisible: Bool? = nil
    var inputIsEmphasized = false
    var onMinimumHeightChange: (CGFloat) -> Void = { _ in }
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resultsHeight: CGFloat = 56
    @State private var fixedHeight: CGFloat = 44
    @State private var inputHeight: CGFloat = 44
    @State private var favoritesHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 180
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 18

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: GoFlySymbols.search)
                        .font(.system(size: min(symbolSize, 22), weight: .medium))
                        .foregroundStyle(GoFlyStyle.secondary)
                        .accessibilityHidden(true)
                    TextField(goFlyString("search.placeholder"), text: Binding(
                        get: { search.query }, set: { search.updateQuery($0) }
                    ), prompt: Text(goFlyString("search.placeholder")).foregroundStyle(GoFlyStyle.secondary))
                    .font(.body)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .accessibilityIdentifier("search.query")
                    if !search.query.isEmpty {
                        Button { search.updateQuery("") } label: {
                            Image(systemName: GoFlySymbols.clearSearch)
                                .goFlyControlSymbol(size: 20, weight: .medium)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(goFlyString("search.clear"))
                        .accessibilityIdentifier("search.clear")
                    }
                }
                .padding(.trailing, search.query.isEmpty ? 16 : 0)
                .frame(minHeight: 52)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { inputHeight = $0 }
                .padding(.leading, 16)
                .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: GoFlyStyle.controlRadius)
                        .strokeBorder(inputIsEmphasized || focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder,
                                      lineWidth: inputIsEmphasized || focused ? 1.5 : 0.75)
                        .allowsHitTesting(false)
                }

                if let error = search.inputError {
                    Text(goFlyString(error.rawValue))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.errorForeground)
                        .accessibilityIdentifier("search.inputError")
                }
                if search.isSearching {
                    ProgressView(goFlyString("search.searching")).font(.footnote)
                }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { fixedHeight = $0 }
            if !visiblePlaces.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(visiblePlaces) { place in
                            placeRow(place)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { resultsHeight = $0 }
                }
                .frame(height: needsCompactScroll ? max(56, resultsHeight) : min(max(56, availableResultsHeight), max(56, resultsHeight)))
                .scrollDisabled(needsCompactScroll)
            } else if visiblePlaces.isEmpty && !search.isSearching && search.queryKind == .name {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString(search.searchFailed ? "search.failed" : "search.noResults"))
                    Text(goFlyString("search.tryAnotherQuery")).foregroundStyle(GoFlyStyle.secondary)
                }
                .font(.footnote)
                .accessibilityIdentifier("search.emptyResults")
            }
            if showsFavorites {
                Button {
                    focused = false
                    onFavorites()
                } label: {
                    Label(goFlyString("favorites.title"), systemImage: GoFlySymbols.favorite)
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("favorites.open")
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { favoritesHeight = $0 }
            }
        }
            .padding(panelPadding)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(height: min(contentHeight, max(minimumInputHeight, maximumHeight)))
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.panel")
        .goFlyCard(floating: true)
        .onChange(of: focusRequest) { _, request in
            if request != nil { focused = true }
        }
        .onChange(of: minimumInputHeight, initial: true) { _, height in onMinimumHeightChange(height) }
    }

    private var visiblePlaces: [MapPlace] {
        if !search.results.isEmpty { return search.results }
        switch search.queryKind {
        case .empty, .invalidCoordinate: return search.candidate.map { [$0.place] } ?? []
        case .name, .coordinate: return []
        }
    }

    private var availableResultsHeight: CGFloat {
        max(0, min(220, maximumHeight - fixedHeight - (dynamicTypeSize.isAccessibilitySize ? 28 : 44)
            - (showsFavorites ? favoritesHeight + 12 : 0)))
    }

    private var needsCompactScroll: Bool { !visiblePlaces.isEmpty && availableResultsHeight < 56 }
    private var panelPadding: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 16 }
    private var minimumInputHeight: CGFloat { inputHeight + panelPadding * 2 }
    private var showsFavorites: Bool { favoritesVisible ?? !focused }

    private func placeRow(_ place: MapPlace) -> some View {
        GoFlyPlaceOptionCard(
            place: place,
            selected: search.candidate?.place.id == place.id && search.candidate?.place.coordinate == place.coordinate,
            selectionIdentifier: "search.result.\(place.coordinate.displayText)",
            starIdentifier: "search.favorite.\(place.coordinate.displayText)",
            onSelect: {
                search.select(place)
                focused = false
            }
        )
    }
}
