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
                VStack(alignment: .leading, spacing: 16) {
                    if let failure = favorites.error {
                        GoFlyStatusBanner(tone: .danger, title: goFlyString(failure.rawValue), identifier: "favorites.error")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(goFlyString("favorites.label"))
                            .font(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.secondary)
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
                                .foregroundStyle(GoFlyTextColor.secondary)
                                .accessibilityLabel(goFlyString("search.clear"))
                            }
                        }
                        .padding(.leading, 16)
                        .frame(minHeight: 48)
                        .goFlySearchField(isFocused: focused)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(place.address ?? place.title).font(GoFlyFont.subheadline)
                        Text(place.coordinate.displayText)
                            .font(GoFlyFont.footnote).foregroundStyle(GoFlyTextColor.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GoFlyStyle.secondarySurface, in: RoundedRectangle(cornerRadius: 14))

                    // C2 / D7: 40 pt between the place card and the Save button; the Home indicator sits 20 pt below it.
                    Button {
                        if favorites.save(place: place, label: draft) {
                            onDismiss()
                        }
                    } label: {
                        Text(goFlyString("favorites.save"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GoFlyActionStyle(primary: true))
                    .disabled(!favorites.canMutate)
                    .padding(.top, 24)
                    .accessibilityIdentifier("favorites.editor.save")
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, -1)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("favorites.editor.form")
        }
        .presentationDetents([.height(367), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(GoFlyStyle.surface)
        .onAppear {
            if draft.isEmpty, let fav = favorites.favorite(for: place), let l = fav.label {
                draft = l
            }
        }
    }

    private var isFavorite: Bool {
        favorites.isFavorite(place)
    }

    private var header: some View {
        GoFlySheetHeader(title: nil) {
            Button(goFlyString("favorites.cancel")) {
                favorites.clearError()
                onDismiss()
            }
            .accessibilityIdentifier("favorites.editor.cancel")
        } trailing: {
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
                        .foregroundStyle(GoFlyTextColor.danger)
                }
                .accessibilityIdentifier("favorites.editor.delete")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
