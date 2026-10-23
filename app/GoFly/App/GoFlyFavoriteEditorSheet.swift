import GoFlyCore
import SwiftUI

/// C2 sheet: modal for adding or editing a favorite place (plan C2).
/// Displays a dismiss/cancel button, title "編輯最愛", optional red "刪除" button,
/// editable label field, place address/coordinates box, and bottom primary "儲存" button.
struct GoFlyFavoriteEditorSheet: View {
    @EnvironmentObject private var favorites: FavoritePlacesStore
    let place: MapPlace
    var onDismiss: () -> Void
    var onDelete: (() -> Void)? = nil
    @State private var draft: String
    @FocusState private var focused: Bool

    init(place: MapPlace, initialLabel: String? = nil, onDismiss: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.place = place
        self.onDismiss = onDismiss
        self.onDelete = onDelete
        _draft = State(initialValue: initialLabel ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let failure = favorites.error {
                        GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue), identifier: "favorites.error")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goFlyString("favorites.label"))
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                        HStack {
                            TextField(goFlyString("favorites.label"), text: $draft)
                                .focused($focused).submitLabel(.done)
                                .onSubmit { focused = false }
                                .accessibilityIdentifier("favorites.editor.label")
                            if !draft.isEmpty {
                                Button { draft = "" } label: {
                                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(GoFlyStyle.secondary)
                                .accessibilityLabel(goFlyString("search.clear"))
                            }
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .background(labelFieldSurface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(focused ? GoFlyStyle.primary : GoFlyStyle.inputBorder,
                                              lineWidth: focused ? 1.5 : 0.75)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.address ?? place.title).font(.subheadline)
                        Text(place.coordinate.displayText)
                            .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(20)
            }
            .accessibilityIdentifier("favorites.editor.form")
            .safeAreaInset(edge: .bottom) {
                Button {
                    if favorites.save(place: place, label: draft) {
                        onDismiss()
                    }
                } label: {
                    Text(goFlyString("favorites.save"))
                }
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(!favorites.canMutate)
                .accessibilityIdentifier("favorites.editor.save")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .presentationDetents([.height(360), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .onAppear {
            if draft.isEmpty, let fav = favorites.favorite(for: place), let l = fav.label {
                draft = l
            }
        }
    }

    private var labelFieldSurface: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .systemGray4 : .systemGray6
        })
    }

    private var isFavorite: Bool {
        favorites.isFavorite(place)
    }

    private var header: some View {
        HStack {
            Button(goFlyString("favorites.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .accessibilityIdentifier("favorites.editor.cancel")
            Spacer()
            Text(goFlyString("favorites.editLabel")).font(.headline)
            Spacer()
            if isFavorite {
                Button {
                    if let onDelete {
                        onDelete()
                    } else {
                        favorites.delete(place: place)
                        onDismiss()
                    }
                } label: {
                    Text(goFlyString("favorites.delete"))
                        .foregroundStyle(GoFlyStyle.dangerForeground)
                }
                .accessibilityIdentifier("favorites.editor.delete")
            } else {
                Text(goFlyString("favorites.cancel"))
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
