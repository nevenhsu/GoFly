import GoFlyCore
import SwiftUI
import UniformTypeIdentifiers

struct GoFlyImportedRoutesView: View {
    @EnvironmentObject private var imports: ImportedRoutesStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: RouteExecutionController
    var onLoaded: () -> Void
    var onFocusPoint: (GeoCoordinate) -> Void = { _ in }
    @State private var showingImporter = false
    @State private var actionRecord: ImportedRouteRecord?
    @State private var showingActions = false
    @State private var showingPoints = false
    @State private var snackbar: GoFlySnackbarMessage?
    @State private var shareItem: DiagnosticsShareItem?
    @State private var fileOperationInProgress = false
    @State private var fileTask: Task<Void, Never>?
    @State private var fileErrorKey: String?
    @State private var loadFailureKey: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let failure = currentFailureKey { notice(failure, identifier: "imports.error") }
                if fileOperationInProgress || imports.isBusy || imports.isValidatingSelection {
                    ProgressView(goFlyString(imports.isValidatingSelection ? "imports.validating" : "imports.working"))
                        .accessibilityIdentifier("imports.working")
                }
                if imports.loadState == .loading {
                    ProgressView(goFlyString("imports.loading"))
                } else if imports.loadState == .ready, imports.records.isEmpty {
                    GoFlyEmptyState(symbol: GoFlySymbols.importEmpty, message: goFlyString("imports.empty"))
                        .accessibilityIdentifier("imports.empty")
                }
                ForEach(imports.records.reversed()) { record in recordCard(record) }
            }
            .padding(16)
        }
        .accessibilityIdentifier("imports.content")
        .safeAreaInset(edge: .bottom) {
            importButton
                .padding(16)
                .background(GoFlyStyle.surface)
        }
        .goFlySnackbar($snackbar)
        .background(GoFlyStyle.canvas)
        .navigationTitle(goFlyString("imports.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Text(goFlyString("common.back"))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("imports.back")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.goFlyGPX, .xml]) { result in
            switch result {
            case .success(let url): importURL(url)
            case .failure(let error): presentFileError(error)
            }
        }
        .confirmationDialog(actionRecord?.filename ?? goFlyString("imports.title"),
                            isPresented: $showingActions, titleVisibility: .visible) {
            Button(goFlyString("imports.load"), action: loadSelected)
                .disabled(isBusy || !controller.canEdit || selectedSnapshot == nil || executionFailureKey != nil)
                .accessibilityIdentifier("imports.load")
            Button(goFlyString("imports.points.all")) { showingPoints = true }
                .disabled(selectedSnapshot == nil)
                .accessibilityIdentifier("imports.points.showAll")
            Button(goFlyString("imports.export"), action: exportSelected)
                .disabled(isBusy || selectedSnapshot == nil)
                .accessibilityIdentifier("imports.export")
            Button(goFlyString("imports.deleteAction"), role: .destructive, action: deleteSelected)
                .disabled(isBusy || !imports.canMutate)
                .accessibilityIdentifier("imports.delete")
            Button(goFlyString("common.cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $showingPoints) {
            if let snapshot = selectedSnapshot {
                NavigationStack {
                    GoFlyGPXPointsView(document: snapshot.document, title: snapshot.record.filename, onFocus: onFocusPoint)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(goFlyString("common.back")) { showingPoints = false }
                            }
                        }
                }
            }
        }
        .sheet(item: $shareItem) { item in
            GoFlyShareSheet(url: item.url)
        }
        .onDisappear {
            fileTask?.cancel()
            fileTask = nil
        }
    }

    private var isBusy: Bool { fileOperationInProgress || imports.isBusy || imports.isValidatingSelection }

    private var selectedSnapshot: ImportedRouteSnapshot? {
        guard imports.loadState == .ready, !imports.isValidatingSelection, let snapshot = imports.selectedSnapshot,
              imports.selectedID == snapshot.record.id else { return nil }
        return snapshot
    }

    private var currentFailureKey: String? {
        if case .blocked(let failure) = imports.loadState { return failure.localizationKey }
        return fileErrorKey ?? loadFailureKey ?? imports.error?.localizationKey
    }

    private var executionFailureKey: String? {
        guard let snapshot = selectedSnapshot else { return nil }
        do { _ = try PlannedRoute(imported: snapshot.document); return nil }
        catch let failure as ImportedRouteExecutionFailure { return failure.localizationKey }
        catch { return "imports.error.unavailable" }
    }

    private var importButton: some View {
        Button {
            do {
                if let fixture = try GoFlyGPXFileAccess.uiTestImportURL() { importURL(fixture) }
                else { showingImporter = true }
            } catch { presentFileError(error) }
        } label: {
            Label(goFlyString("imports.import"), systemImage: GoFlySymbols.importFile)
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(isBusy || !imports.canMutate)
        .accessibilityIdentifier("imports.import")
    }

    private func recordCard(_ record: ImportedRouteRecord) -> some View {
        Button {
            fileErrorKey = nil
            loadFailureKey = nil
            actionRecord = record
            fileTask = Task {
                await imports.select(record.id)
                guard !Task.isCancelled else { return }
                if let key = executionFailureKey { loadFailureKey = key }
                showingActions = true
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.filename).font(.body.weight(.semibold)).lineLimit(2)
                Text(record.start.displayText + " → " + record.end.displayText)
                    .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                Text(goFlyImportedRouteMetadata(record))
                    .font(.footnote).foregroundStyle(GoFlyStyle.secondary)
                if let failure = imports.unavailable[record.id] {
                    Text(goFlyString(failure.localizationKey))
                        .font(.footnote).foregroundStyle(GoFlyStyle.errorForeground)
                        .accessibilityIdentifier("imports.unavailable.\(record.id.uuidString)")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || imports.loadState != .ready)
        .accessibilityIdentifier("imports.record.\(record.id.uuidString)")
        .background(GoFlyStyle.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func deleteSelected() {
        guard !isBusy, let record = actionRecord else { return }
        fileTask = Task {
            guard await imports.delete(record.id) else { return }
            snackbar = GoFlySnackbarMessage(text: goFlyString("imports.deleted"),
                actionTitle: imports.canUndo ? goFlyString("imports.undo") : nil,
                action: imports.canUndo ? { Task { _ = await imports.undoDelete() } } : nil)
        }
    }

    private func notice(_ key: String, identifier: String) -> some View {
        GoFlyStatusBanner(tone: .danger, title: goFlyString(key), message: goFlyString("imports.error.guidance"), identifier: identifier)
    }

    private func importURL(_ url: URL) {
        guard !isBusy else { return }
        fileOperationInProgress = true
        fileErrorKey = nil
        loadFailureKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            do {
                guard try await GoFlyGPXFileAccess.importFile(url, into: imports), let snapshot = selectedSnapshot else { return }
                snackbar = GoFlySnackbarMessage(
                    text: goFlyLocalizedFormat(goFlyString("imports.imported"), snapshot.record.filename),
                    actionTitle: goFlyString("imports.load"), action: { loadRoute(snapshot.record.id) })
            }
            catch { presentFileError(error) }
        }
    }

    private func loadSelected() {
        guard let id = imports.selectedID else { return }
        loadRoute(id)
    }

    private func loadRoute(_ id: UUID) {
        guard !isBusy, controller.canEdit else { return }
        // The admission revision must be captured before the async selection
        // revalidation. A late validation result cannot overwrite a newer
        // draft or a transfer hold.
        guard let admission = controller.beginImportedLoad() else { return }
        fileOperationInProgress = true
        loadFailureKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            await imports.select(id)
            guard !Task.isCancelled, let snapshot = imports.selectedSnapshot,
                  imports.selectedID == id, snapshot.record.id == id, controller.canEdit else { return }
            if controller.loadImportedRoute(snapshot, expectedAdmissionRevision: admission) { onLoaded() }
            else { loadFailureKey = controller.error?.localizationKey }
        }
    }

    private func exportSelected() {
        guard !isBusy, let snapshot = selectedSnapshot else { return }
        fileOperationInProgress = true
        fileErrorKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            do {
                let data = try await imports.exportSelected()
                try Task.checkCancellation()
                let url = try GoFlyGPXFileAccess.shareURL(data: data, filename: snapshot.record.filename)
                shareItem = DiagnosticsShareItem(url: url)
            } catch { presentFileError(error) }
        }
    }

    private func presentFileError(_ error: any Error) {
        if error is CancellationError || (error as? CocoaError)?.code == .userCancelled { return }
        if let failure = error as? GoFlyGPXFileFailure { fileErrorKey = failure.localizationKey }
        else if let failure = error as? ImportedRoutesFailure { fileErrorKey = failure.localizationKey }
        else if let failure = error as? GPXFailure { fileErrorKey = failure.localizationKey }
        else { fileErrorKey = "imports.file.unavailable" }
    }
}

@MainActor
func goFlyImportedRouteMetadata(_ record: ImportedRouteRecord) -> String {
    goFlyLocalizedFormat(goFlyString("imports.metadata"),
                                    goFlyString("imports.kind.\(record.kind.rawValue)"), record.pointCount)
}
