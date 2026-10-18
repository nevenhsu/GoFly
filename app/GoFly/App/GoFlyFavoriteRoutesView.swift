import GoFlyCore
import SwiftUI

struct GoFlyFavoriteRoutesView: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    @ObservedObject var controller: RouteExecutionController
    var onDismiss: () -> Void
    @State private var editing: FavoriteRouteRecord?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadRequest: UUID?
    @State private var loadFailureKey: String?
    @State private var visibleScrollFrame: CGRect = .zero

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GoFlyFavoriteRouteFailureNotice(localErrorKey: loadFailureKey)
                    if favorites.loadState == .loading {
                        ProgressView(goFlyString("favoriteRoutes.loading"))
                    } else if favorites.loadState == .ready, favorites.records.isEmpty {
                        GoFlyEmptyState(symbol: GoFlySymbols.route, message: goFlyString("favoriteRoutes.empty"))
                            .accessibilityIdentifier("favoriteRoutes.empty")
                    }
                    if favorites.isBusy || favorites.isValidatingSelection {
                        ProgressView(goFlyString(favorites.isValidatingSelection ? "favoriteRoutes.validating" : "favoriteRoutes.working"))
                            .font(.body)
                            .accessibilityIdentifier("favoriteRoutes.working")
                    }
                    if favorites.canUndo {
                        HStack(spacing: 12) {
                            Text(goFlyString("favoriteRoutes.deleted"))
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                invalidateLoad()
                                Task { _ = await favorites.undoDelete() }
                            } label: {
                                Text(goFlyString("favoriteRoutes.undo"))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!favorites.canMutate)
                            .accessibilityIdentifier("favoriteRoutes.undo")
                        }
                    }
                    ForEach(favorites.records) { record in card(record) }
                }
                .padding(16)
            }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
            .accessibilityIdentifier("favoriteRoutes.content")
            .safeAreaInset(edge: .bottom) {
                Button(goFlyString("favoriteRoutes.return")) {
                    invalidateLoad()
                    onDismiss()
                }
                .buttonStyle(GoFlyActionStyle())
                .accessibilityIdentifier("favoriteRoutes.return")
                .padding(16)
                .background(GoFlyStyle.surface)
            }
            .background(GoFlyStyle.canvas)
            .navigationTitle(goFlyString("favoriteRoutes.title"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .topLeading) { viewportMetrics }
        }
        .presentationDetents([.large])
        .presentationBackground(GoFlyStyle.surface)
        .sheet(item: $editing) { record in
            GoFlyFavoriteRouteLabelEditor(record: record) { editing = nil }
        }
        .onAppear { controller.invalidateFavoriteLoadAdmission() }
        .onDisappear { invalidateLoad() }
    }

    private var canSelect: Bool {
        controller.canEdit && favorites.loadState == .ready && !favorites.isBusy
    }

    private func card(_ record: FavoriteRouteRecord) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.label ?? goFlyFavoriteRouteEndpoints(record))
                    .font(.body.weight(.semibold)).lineLimit(2)
                if record.label != nil {
                    Text(goFlyFavoriteRouteEndpoints(record))
                        .font(.footnote).foregroundStyle(GoFlyStyle.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
            .gesture(LongPressGesture(minimumDuration: 0.6).exclusively(before: TapGesture())
                .onEnded { gesture in
                    switch gesture {
                    case .first: edit(record)
                    case .second: load(record)
                    }
                })
            .allowsHitTesting(canSelect)
            .disabled(!canSelect)
            .foregroundStyle(canSelect ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.label.map { $0 + ", " + goFlyFavoriteRouteEndpoints(record) }
                                ?? goFlyFavoriteRouteEndpoints(record))
            .accessibilityValue(goFlyLocalizedFormat(goFlyString(record.sourceKind == .gpx
                ? "favoriteRoutes.pointCount" : "favoriteRoutes.placeCount"), record.count))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(favorites.selectedID == record.id ? .isSelected : [])
            .accessibilityAction { load(record) }
            .accessibilityAction(named: Text(goFlyString("favoriteRoutes.editLabel"))) { edit(record) }
            .accessibilityIdentifier("favoriteRoutes.record.\(record.id.uuidString)")
            Button {
                invalidateLoad()
                Task { _ = await favorites.delete(record.id) }
            } label: {
                Image(systemName: GoFlySymbols.delete)
                    .goFlyControlSymbol(size: 20, weight: .regular)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(favorites.canMutate ? GoFlyStyle.primary : GoFlyStyle.disabledForeground)
            .disabled(!favorites.canMutate)
            .accessibilityLabel(goFlyLocalizedFormat(goFlyString("favoriteRoutes.delete"),
                record.label ?? goFlyFavoriteRouteEndpoints(record)))
            .accessibilityIdentifier("favoriteRoutes.delete.\(record.id.uuidString)")
            .padding(.trailing, 6)
        }
        .background(favorites.selectedID == record.id ? GoFlyStyle.secondarySurface : GoFlyStyle.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(favorites.selectedID == record.id ? GoFlyStyle.primary : GoFlyStyle.border,
                              lineWidth: favorites.selectedID == record.id ? 1.5 : 0.5)
        }
    }

    private func invalidateLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadRequest = nil
        controller.invalidateFavoriteLoadAdmission()
    }

    private func load(_ record: FavoriteRouteRecord) {
        guard canSelect else { return }
        invalidateLoad()
        guard let admission = controller.beginFavoriteLoad() else { return }
        let request = UUID()
        loadRequest = request
        loadFailureKey = nil
        loadTask = Task {
            await favorites.select(record.id)
            guard !Task.isCancelled, loadRequest == request,
                  favorites.loadState == .ready, favorites.selectedID == record.id,
                  let snapshot = favorites.selectedSnapshot, snapshot.record.id == record.id,
                  controller.favoriteLoadAdmissionRevision == admission else { return }
            if controller.loadFavoriteRoute(snapshot, expectedAdmissionRevision: admission) { onDismiss() }
            else { loadFailureKey = controller.error?.localizationKey }
        }
    }

    private func edit(_ record: FavoriteRouteRecord) {
        guard canSelect else { return }
        invalidateLoad()
        loadFailureKey = nil
        editing = record
    }

    @ViewBuilder private var viewportMetrics: some View {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
            Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                        visibleScrollFrame.width, visibleScrollFrame.height))
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
                .accessibilityIdentifier("favoriteRoutes.viewport.metrics")
        }
        #endif
    }
}

struct GoFlyFavoriteRouteFailureNotice: View {
    @EnvironmentObject private var favorites: FavoriteRoutesStore
    var localErrorKey: String? = nil

    var body: some View {
        if let key {
            Label(goFlyString(key), systemImage: GoFlySymbols.warning)
                .font(.footnote)
                .foregroundStyle(GoFlyStyle.errorForeground)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("favoriteRoutes.error")
        }
    }
    private var key: String? {
        if case .blocked(let failure) = favorites.loadState { return failure.localizationKey }
        return localErrorKey ?? favorites.error?.localizationKey
    }
}

func goFlyFavoriteRouteEndpoints(_ record: FavoriteRouteRecord) -> String {
    (record.startTitle ?? record.start.displayText) + " → " + (record.endTitle ?? record.end.displayText)
}
