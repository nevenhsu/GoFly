import GoFlyCore
import SwiftUI

struct GoFlySearchPanel: View {
    @ObservedObject var search: CandidateController
    var maximumHeight: CGFloat
    @FocusState private var focused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var resultsHeight: CGFloat = 56
    @State private var fixedHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField(goFlyString("search.placeholder"), text: Binding(
                        get: { search.query }, set: { search.updateQuery($0) }
                    ))
                    .font(.body)
                    .focused($focused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { focused = false }
                    .accessibilityIdentifier("search.query")
                    if !search.query.isEmpty {
                        Button { search.updateQuery("") } label: {
                            Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(goFlyString("search.clear"))
                        .accessibilityIdentifier("search.clear")
                    }
                }
                .frame(minHeight: 44)
                .padding(.leading, 12)
                .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 12))

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
            if !visiblePlaces.isEmpty && availableResultsHeight >= 44 {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(visiblePlaces) { place in
                            placeRow(place)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { resultsHeight = $0 }
                }
                .frame(height: min(availableResultsHeight, max(44, resultsHeight)))
            } else if visiblePlaces.isEmpty && !search.isSearching && search.queryKind == .name {
                VStack(alignment: .leading, spacing: 4) {
                    Text(goFlyString(search.searchFailed ? "search.failed" : "search.noResults"))
                    Text(goFlyString("search.tryAnotherQuery")).foregroundStyle(GoFlyStyle.secondary)
                }
                .font(.footnote)
                .accessibilityIdentifier("search.emptyResults")
            }
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 8 : 16)
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: GoFlyStyle.cornerRadius).strokeBorder(GoFlyStyle.border, lineWidth: 0.5)
        }
    }

    private var visiblePlaces: [MapPlace] {
        if !search.results.isEmpty { return search.results }
        return search.candidate.map { [$0.place] } ?? []
    }

    private var availableResultsHeight: CGFloat {
        max(0, min(220, maximumHeight - fixedHeight - (dynamicTypeSize.isAccessibilitySize ? 28 : 44)))
    }

    private func placeRow(_ place: MapPlace) -> some View {
        let selected = search.candidate?.place.id == place.id
        return Button {
            search.select(place)
            focused = false
        } label: {
            HStack {
                Text(place.title).font(.body).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? GoFlyStyle.secondarySurface : GoFlyStyle.surface,
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? GoFlyStyle.primary : GoFlyStyle.border, lineWidth: selected ? 1.5 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("search.result.\(place.coordinate.displayText)")
    }
}
