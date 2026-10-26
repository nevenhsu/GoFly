import GoFlyCore
import SwiftUI
import UIKit

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
    var onClearRecentPlaces: (() -> Void)?
    var onSelect: (MapPlace) -> Void = { _ in }
    var onUseCurrentLocation: (() -> Void)?
    var onClearPlace: (() -> Void)?
    @EnvironmentObject private var favorites: FavoritePlacesStore
    @State private var focused = false

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
                                .font(GoFlyFont.subheadline)
                                .foregroundStyle(GoFlyTextColor.secondary)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                .foregroundStyle(GoFlyTextColor.primary)
                .accessibilityLabel(goFlyString("common.back"))
                .accessibilityIdentifier("search.back")
                .padding(.leading, -8)
            }
            HStack(spacing: 8) {
                Image(systemName: GoFlySymbols.search)
                    .goFlyControlSymbol(size: 17, weight: .medium)
                    .foregroundStyle(GoFlyTextColor.secondary)
                    .accessibilityHidden(true)
                PasteableSearchTextField(
                    placeholder: placeholderOverride ?? goFlyString(placeholderKey),
                    text: search.query,
                    isFocused: focused,
                    onTextChange: { query in
                        search.updateQuery(query)
                        focused = true
                    },
                    onFocusChange: { focused = $0 },
                    onSubmit: { focused = false }
                )
                .frame(maxWidth: .infinity, minHeight: 50)
                .frame(height: 50)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            .goFlySearchField(isFocused: focused)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func roleChip(_ title: String) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: GoFlySymbols.flag)
                    .goFlyControlSymbol(size: 12, maximum: 14, weight: .semibold)
                Text(title)
                    .font(GoFlyFont.footnote)
            }
            .foregroundStyle(GoFlyTextColor.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(GoFlyStyle.secondarySurface, in: Capsule())
            Spacer()
            Button(action: onFavorites) {
                HStack(spacing: 8) {
                    GoFlyStarIcon(size: 22, filled: false)
                    Text(goFlyString("favorites.shortTitle"))
                        .font(GoFlyFont.subheadlineEmphasis)
                }
                .foregroundStyle(GoFlyTextColor.primary)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(goFlyString("favorites.shortTitle"))
            .accessibilityIdentifier("search.favorites")
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
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
        if !recentPlaces.isEmpty {
            sectionHeader("search.recent",
                          actionTitle: goFlyString("search.clearHistory"),
                          actionIdentifier: "search.clearHistory",
                          action: onClearRecentPlaces)
            ForEach(recentPlaces) { place in
                row(place, symbol: GoFlySymbols.recent, identifier: place)
            }
        }
        // An empty query has not searched anything, so it never reports "no results" (B3).
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
                placeRow(place, identifier: place)
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
                               actionIdentifier: String? = nil,
                               action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(goFlyString(key))
                .font(GoFlyFont.subheadlineEmphasis)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(GoFlyFont.subheadlineEmphasis)
                        .foregroundStyle(GoFlyTextColor.secondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(actionIdentifier ?? (key == "favorites.title" ? "favorites.open" : "search.sectionAction.\(key)"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goFlyLocalizedFormat(goFlyString("search.goToCoordinate"),
                                                  place.coordinate.shortDisplayText))
                            .font(GoFlyFont.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(goFlyString("search.validCoordinate"))
                            .font(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
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

    private func placeRow(_ place: MapPlace, identifier: MapPlace) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    select(place)
                } label: {
                    HStack(spacing: 12) {
                        pinIconTile
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.title)
                                .font(GoFlyFont.body)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(place.address ?? place.coordinate.displayText)
                                .font(GoFlyFont.footnote)
                                .foregroundStyle(GoFlyTextColor.secondary)
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

    private var pinIconTile: some View {
        GoFlyTabIcon(mode: .teleport, selected: false, size: 18)
            .foregroundStyle(GoFlyTextColor.primary)
            .frame(width: 36, height: 36)
            .background(GoFlyStyle.secondarySurface, in: Circle())
            .accessibilityHidden(true)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title?.isEmpty == false ? title! : place.title)
                            .font(GoFlyFont.body)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(place.address ?? place.coordinate.displayText)
                            .font(GoFlyFont.footnote)
                            .foregroundStyle(GoFlyTextColor.secondary)
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
                    .font(GoFlyFont.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 12)
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
            .foregroundStyle(filled ? GoFlyStyle.surface : GoFlyTextColor.primary)
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

/// A native text field keeps standard cursor and selection behavior while its
/// right-side controls provide clear and privacy-safe system paste actions.
private struct PasteableSearchTextField: UIViewRepresentable {
    let placeholder: String
    let text: String
    let isFocused: Bool
    let onTextChange: (String) -> Void
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onFocusChange: onFocusChange, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.borderStyle = .none
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = .label
        textField.tintColor = .systemBlue
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .search
        textField.clearButtonMode = .never
        textField.pasteConfiguration = UIPasteConfiguration(forAccepting: String.self)
        textField.accessibilityIdentifier = "search.query"
        textField.delegate = context.coordinator
        textField.pasteDelegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        let controls = SearchTextFieldAccessoryView()
        controls.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pasteButton = UIView(frame: .zero)
        pasteButton.translatesAutoresizingMaskIntoConstraints = false
        addGoFlyPasteControl(to: pasteButton, target: textField,
                             backgroundColor: UIColor(GoFlyStyle.fieldSurface),
                             accessibilityLabel: goFlyString("search.paste"),
                             accessibilityIdentifier: "search.paste")
        controls.addSubview(pasteButton)
        NSLayoutConstraint.activate([
            pasteButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            pasteButton.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            pasteButton.topAnchor.constraint(equalTo: controls.topAnchor),
            pasteButton.bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])

        let clearButton = UIButton(type: .system)
        clearButton.setImage(UIImage(systemName: GoFlySymbols.clearSearch), for: .normal)
        clearButton.tintColor = .secondaryLabel
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: 44),
            clearButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        clearButton.accessibilityLabel = goFlyString("search.clear")
        clearButton.accessibilityIdentifier = "search.clear"
        clearButton.addAction(UIAction { [weak textField] _ in
            textField?.text = ""
            textField?.sendActions(for: .editingChanged)
            textField?.becomeFirstResponder()
        }, for: .touchUpInside)
        controls.addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.leadingAnchor.constraint(equalTo: controls.leadingAnchor),
            clearButton.trailingAnchor.constraint(equalTo: controls.trailingAnchor),
            clearButton.topAnchor.constraint(equalTo: controls.topAnchor),
            clearButton.bottomAnchor.constraint(equalTo: controls.bottomAnchor)
        ])
        textField.rightView = controls
        textField.rightViewMode = .always
        textField.text = text
        textField.placeholder = placeholder
        context.coordinator.clearButton = clearButton
        context.coordinator.pasteButton = pasteButton
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onSubmit = onSubmit
        clearButton.isHidden = text.isEmpty
        pasteButton.isHidden = !text.isEmpty
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        textField.placeholder = placeholder
        if textField.text != text { textField.text = text }
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onSubmit = onSubmit
        context.coordinator.clearButton?.isHidden = text.isEmpty
        context.coordinator.pasteButton?.isHidden = !text.isEmpty

        if isFocused, !textField.isFirstResponder {
            DispatchQueue.main.async { [weak textField] in _ = textField?.becomeFirstResponder() }
        } else if !isFocused, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate, UITextPasteDelegate {
        var onTextChange: (String) -> Void
        var onFocusChange: (Bool) -> Void
        var onSubmit: () -> Void
        weak var clearButton: UIButton?
        weak var pasteButton: UIView?

        init(onTextChange: @escaping (String) -> Void,
             onFocusChange: @escaping (Bool) -> Void,
             onSubmit: @escaping () -> Void) {
            self.onTextChange = onTextChange
            self.onFocusChange = onFocusChange
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            let value = textField.text ?? ""
            clearButton?.isHidden = value.isEmpty
            pasteButton?.isHidden = !value.isEmpty
            onTextChange(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { onFocusChange(true) }
        func textFieldDidEndEditing(_ textField: UITextField) { onFocusChange(false) }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return false
        }

        func textPasteConfigurationSupporting(
            _ textPasteConfigurationSupporting: any UITextPasteConfigurationSupporting,
            combineItemAttributedStrings itemStrings: [NSAttributedString],
            for textRange: UITextRange
        ) -> NSAttributedString {
            trimmedPasteText(itemStrings)
        }
    }
}

private final class SearchTextFieldAccessoryView: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: 44, height: 44) }
}

/// A standalone native paste button used where a paste action must not activate
/// the surrounding search-entry button.
struct GoFlyPasteControl: UIViewRepresentable {
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    var backgroundColor: UIColor = .secondarySystemGroupedBackground
    var symbolColor: UIColor = .secondaryLabel
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> PasteRecipient {
        let container = PasteRecipient(onPaste: onPaste)
        addGoFlyPasteControl(to: container, target: container, backgroundColor: backgroundColor,
                             symbolColor: symbolColor,
                             accessibilityLabel: accessibilityLabel,
                             accessibilityIdentifier: accessibilityIdentifier)
        return container
    }

    func updateUIView(_ container: PasteRecipient, context: Context) {
        container.onPaste = onPaste
    }

    /// Receives `UIPasteControl` items directly. A hidden text field never
    /// reports `.editingChanged` for a programmatic paste, so it cannot relay.
    final class PasteRecipient: UIView {
        var onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init(frame: .zero)
            pasteConfiguration = UIPasteConfiguration(forAccepting: String.self)
        }

        required init?(coder: NSCoder) { nil }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return }
            _ = provider.loadObject(ofClass: String.self) { [weak self] value, _ in
                let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return }
                Task { @MainActor in self?.onPaste(text) }
            }
        }
    }
}

private func trimmedPasteText(_ itemStrings: [NSAttributedString]) -> NSAttributedString {
    let pastedText = itemStrings.map(\.string).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    return NSAttributedString(string: pastedText)
}

/// Centers a 36 pt system paste control in `host`. The system draws the glyph:
/// UIPasteControl is a secure control and ignores taps when it is hidden,
/// transparent, or covered by another view.
@MainActor @discardableResult
private func addGoFlyPasteControl(
    to host: UIView,
    target: any UIPasteConfigurationSupporting,
    backgroundColor: UIColor,
    symbolColor: UIColor = UIColor(GoFlyGrayScale.pasteSymbol),
    accessibilityLabel: String,
    accessibilityIdentifier: String
) -> UIPasteControl {
    let configuration = UIPasteControl.Configuration()
    configuration.displayMode = .iconOnly
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = symbolColor
    // A clear base color is drawn black by the system control; use the host's solid surface.
    configuration.baseBackgroundColor = backgroundColor
    let pasteControl = UIPasteControl(configuration: configuration)
    pasteControl.target = target
    pasteControl.accessibilityLabel = accessibilityLabel
    pasteControl.accessibilityIdentifier = accessibilityIdentifier
    pasteControl.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(pasteControl)
    NSLayoutConstraint.activate([
        pasteControl.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        pasteControl.centerYAnchor.constraint(equalTo: host.centerYAnchor),
        pasteControl.widthAnchor.constraint(equalToConstant: 36),
        pasteControl.heightAnchor.constraint(equalToConstant: 36)
    ])
    return pasteControl
}
