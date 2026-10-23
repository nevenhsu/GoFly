import GoFlyCore
import SwiftUI

/// Shared full-screen search used by teleport and by route fields (plan 4.3 / 4.7).
///
/// The header belongs to the page: a back chevron next to the field, with no
/// navigation title, so the keyboard never pushes a title bar around. Results
/// are an unframed list of 64 pt rows with an icon tile, a title and one
/// subtitle line; the field keeps its own gray, bordered appearance.
struct GoFlySearchPanel: View {
    @ObservedObject var search: CandidateController
    var focusRequest: UUID?
    var placeholderKey: String = "search.placeholder"
    var placeholderOverride: String?
    /// Optional chip such as "Choosing: destination" for route fields.
    var roleTitle: String?
    var onBack: (() -> Void)?
    var onFavorites: () -> Void = {}
    var recentPlaces: [MapPlace] = []
    var onSelect: (MapPlace) -> Void = { _ in }
    var onUseCurrentLocation: (() -> Void)?
    var onClearPlace: (() -> Void)?
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if let roleTitle { roleChip(roleTitle) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let error = search.inputError {
                        GoFlyStatusBanner(tone: .warning, title: goFlyString(error.rawValue),
                                          identifier: "search.inputError")
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    if search.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(goFlyString("search.searching"))
                                .font(.subheadline)
                                .foregroundStyle(GoFlyStyle.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .accessibilityIdentifier("search.searching")
                    }
                    content
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(GoFlyStyle.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.panel")
        .onAppear { focused = true }
        .onChange(of: focusRequest) { _, request in if request != nil { focused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoFlyStyle.primary)
                .accessibilityLabel(goFlyString("common.back"))
                .accessibilityIdentifier("search.back")
                .padding(.leading, -8)
            }
            HStack(spacing: 8) {
                Image(systemName: GoFlySymbols.search)
                    .goFlyControlSymbol(size: 17, weight: .medium)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityHidden(true)
                TextField(placeholderOverride ?? goFlyString(placeholderKey), text: Binding(
                    get: { search.query }, set: { search.updateQuery($0) }
                ))
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { focused = false }
                .accessibilityIdentifier("search.query")
                if !search.query.isEmpty {
                    Button { search.updateQuery("") } label: {
                        Image(systemName: GoFlySymbols.clearSearch)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .accessibilityLabel(goFlyString("search.clear"))
                    .accessibilityIdentifier("search.clear")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .background(GoFlyStyle.inputSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder,
                                  lineWidth: focused ? 1.5 : 0.75)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func roleChip(_ title: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: GoFlySymbols.flag)
                    .goFlyControlSymbol(size: 12, maximum: 14, weight: .semibold)
                Text(title)
                    .font(.footnote)
            }
            .foregroundStyle(GoFlyStyle.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(GoFlyStyle.secondarySurface, in: Capsule())
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search.role")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if search.queryKind == .empty {
            emptyContent
        } else {
            resultsContent
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if let onUseCurrentLocation {
            actionRow(goFlyString("route.useCurrentLocation"),
                      symbol: GoFlySymbols.location, identifier: "route.picker.current",
                      action: onUseCurrentLocation)
        }
        if !favorites.favorites.isEmpty {
            sectionHeader("favorites.title", actionTitle: goFlyString("search.viewAll")) {
                focused = false
                onFavorites()
            }
            ForEach(favorites.favorites.prefix(5)) { favorite in
                row(favorite.place, title: favorite.displayTitle,
                    symbol: GoFlySymbols.favoriteSelected, identifier: favorite.place)
            }
        }
        if !recentPlaces.isEmpty {
            sectionHeader("search.recent")
            ForEach(recentPlaces) { place in
                row(place, symbol: GoFlySymbols.recent, identifier: place)
            }
        }
        if favorites.favorites.isEmpty, recentPlaces.isEmpty {
            GoFlyEmptyState(symbol: GoFlySymbols.search,
                            message: goFlyString("search.noResults"))
                .padding(.top, 24)
                .accessibilityIdentifier("search.emptyResults")
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if search.queryKind == .coordinate, let coordinate = search.results.first {
            coordinateRow(coordinate)
        }
        if !matchingFavorites.isEmpty {
            sectionHeader("favorites.title")
            ForEach(matchingFavorites) { favorite in
                row(favorite.place, title: favorite.displayTitle,
                    symbol: GoFlySymbols.favoriteSelected, identifier: favorite.place)
            }
        }
        // A coordinate query already owns the first row; never render it twice.
        let places = search.queryKind == .coordinate ? [] : search.results.filter { place in
            !matchingFavorites.contains { $0.place.coordinate == place.coordinate }
        }
        if !places.isEmpty {
            sectionHeader("search.nearby")
            ForEach(places) { place in
                row(place, symbol: GoFlySymbols.place, identifier: place)
            }
        }
        if places.isEmpty, matchingFavorites.isEmpty, search.queryKind != .coordinate,
           !search.isSearching, search.inputError == nil {
            GoFlyEmptyState(symbol: GoFlySymbols.search,
                            message: goFlyString(search.searchFailed ? "search.failed" : "search.noResults"))
                .padding(.top, 12)
                .accessibilityIdentifier("search.emptyResults")
        }
    }

    private var matchingFavorites: [FavoritePlace] {
        guard search.queryKind == .name else { return [] }
        let query = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return favorites.favorites.filter {
            ($0.label?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.place.title.localizedCaseInsensitiveContains(query)
                || ($0.place.address?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ key: String, actionTitle: String? = nil,
                               action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(goFlyString(key))
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundStyle(GoFlyStyle.secondary)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("favorites.open")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 2)
        .accessibilityIdentifier("search.section.\(key)")
    }

    private func coordinateRow(_ place: MapPlace) -> some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 12) {
                    iconTile(GoFlySymbols.heading, filled: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(goFlyLocalizedFormat(goFlyString("search.goToCoordinate"),
                                                  place.coordinate.shortDisplayText))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(goFlyString("search.validCoordinate"))
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(place.coordinate.displayText)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        Divider().padding(.leading, 68)
        }
    }

    private func row(_ place: MapPlace, title: String? = nil, symbol: String,
                     identifier: MapPlace) -> some View {
        VStack(spacing: 0) {
        HStack(spacing: 12) {
            Button {
                select(place)
            } label: {
                HStack(spacing: 12) {
                    iconTile(symbol)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title?.isEmpty == false ? title! : place.title)
                            .font(.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(place.address ?? place.coordinate.displayText)
                            .font(.footnote)
                            .foregroundStyle(GoFlyStyle.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.result.\(identifier.coordinate.displayText)")
        }
        .padding(.horizontal, 20)
        Divider().padding(.leading, 68)
        }
    }

    private func actionRow(_ title: String, symbol: String, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            focused = false
            action()
        } label: {
            HStack(spacing: 12) {
                iconTile(symbol)
                Text(title)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .accessibilityIdentifier(identifier)
    }

    /// A calm gray icon tile keeps titles aligned across sections, matching the
    /// Figma list instead of a bare glyph.
    private func iconTile(_ symbol: String, filled: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(filled ? GoFlyStyle.surface : GoFlyStyle.primary)
            .frame(width: 36, height: 36)
            .background(filled ? GoFlyStyle.primary : GoFlyStyle.secondarySurface, in: Circle())
            .accessibilityHidden(true)
    }

    private func select(_ place: MapPlace) {
        search.select(place)
        focused = false
        onSelect(place)
    }
}
