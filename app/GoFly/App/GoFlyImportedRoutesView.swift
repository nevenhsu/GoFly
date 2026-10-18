import CryptoKit
import GoFlyCore
import SwiftUI
import UniformTypeIdentifiers

struct GoFlyImportedRoutesView: View {
    @EnvironmentObject private var imports: ImportedRoutesStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: RouteExecutionController
    var onLoaded: () -> Void
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var fileOperationInProgress = false
    @State private var fileTask: Task<Void, Never>?
    @State private var fileErrorKey: String?
    @State private var loadFailureKey: String?
    @State private var exportDocument: GoFlyGPXExportDocument?
    @State private var exportFilename = "route"
    @State private var exportMetrics = ""
    @State private var visibleScrollFrame: CGRect = .zero

    var body: some View {
        let eligibilityFailure = executionFailureKey
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { importButton; exportButton }
                    VStack(spacing: 12) { importButton; exportButton }
                }
                if fileOperationInProgress || imports.isBusy || imports.isValidatingSelection {
                    ProgressView(goFlyString(imports.isValidatingSelection ? "imports.validating" : "imports.working"))
                        .font(.body)
                        .accessibilityIdentifier("imports.working")
                }
                if let failure = currentFailureKey { notice(failure, identifier: "imports.error") }
                if imports.canUndo {
                    HStack(alignment: .center, spacing: 12) {
                        Text(goFlyString("imports.deleted"))
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Task { _ = await imports.undoDelete() }
                        } label: {
                            Text(goFlyString("imports.undo"))
                                .font(.body.weight(.semibold))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isBusy || !imports.canMutate)
                        .accessibilityIdentifier("imports.undo")
                    }
                }
                if imports.loadState == .loading {
                    ProgressView(goFlyString("imports.loading"))
                } else if imports.loadState == .ready, imports.records.isEmpty {
                    Text(goFlyString("imports.empty"))
                        .font(.body)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .accessibilityIdentifier("imports.empty")
                }
                ForEach(imports.records) { record in recordCard(record) }
                if let snapshot = selectedSnapshot {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(goFlyString("imports.preview"))
                            .font(.headline)
                        GoFlyGPXPreview(document: snapshot.document)
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if let eligibilityFailure {
                            notice(eligibilityFailure, identifier: "imports.executionError")
                        }
                    }
                }
            }
            .padding(16)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { visibleScrollFrame = $0 }
        .accessibilityIdentifier("imports.content")
        .safeAreaInset(edge: .bottom) {
            Button(goFlyString("imports.load"), action: loadSelected)
                .buttonStyle(GoFlyActionStyle(primary: true))
                .disabled(isBusy || !controller.canEdit || selectedSnapshot == nil || eligibilityFailure != nil)
                .accessibilityIdentifier("imports.load")
                .padding(16)
                .background(GoFlyStyle.surface)
        }
        .background(GoFlyStyle.surface)
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
        .fileExporter(isPresented: $showingExporter, document: exportDocument,
                      contentType: .goFlyGPX, defaultFilename: exportFilename) { result in
            if case .failure(let error) = result { presentFileError(error) }
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
                VStack {
                    Text(String(format: "%.2f,%.2f,%.2f,%.2f", visibleScrollFrame.minX, visibleScrollFrame.minY,
                                visibleScrollFrame.width, visibleScrollFrame.height))
                        .accessibilityIdentifier("imports.viewport.metrics")
                    if !exportMetrics.isEmpty {
                        Text(exportMetrics).accessibilityIdentifier("imports.export.metrics")
                    }
                }
                .font(.caption2).foregroundStyle(.clear).frame(width: 1, height: 1).allowsHitTesting(false)
            }
            #endif
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
            Label(goFlyString("imports.import"), systemImage: "square.and.arrow.down")
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(isBusy || !imports.canMutate)
        .accessibilityIdentifier("imports.import")
    }

    private var exportButton: some View {
        Button(action: exportSelected) {
            Label(goFlyString("imports.export"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(GoFlyActionStyle())
        .disabled(isBusy || selectedSnapshot == nil)
        .accessibilityIdentifier("imports.export")
    }

    private func recordCard(_ record: ImportedRouteRecord) -> some View {
        HStack(spacing: 0) {
            Button {
                fileErrorKey = nil
                loadFailureKey = nil
                Task { await imports.select(record.id) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.filename).font(.body.weight(.semibold)).lineLimit(2)
                    Text(record.start.displayText + " → " + record.end.displayText)
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                        .lineLimit(2)
                    Text(goFlyImportedRouteMetadata(record))
                        .font(.footnote)
                        .foregroundStyle(GoFlyStyle.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || imports.loadState != .ready)
            .accessibilityAddTraits(imports.selectedID == record.id ? .isSelected : [])
            .accessibilityIdentifier("imports.record.\(record.id.uuidString)")
            Button {
                Task { _ = await imports.delete(record.id) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isBusy || !imports.canMutate ? GoFlyStyle.disabledForeground : GoFlyStyle.primary)
            .disabled(isBusy || !imports.canMutate)
            .accessibilityLabel(goFlyLocalizedFormat(goFlyString("imports.delete"), record.filename))
            .accessibilityIdentifier("imports.delete.\(record.id.uuidString)")
            .padding(.trailing, 6)
        }
        .background(imports.selectedID == record.id ? GoFlyStyle.secondarySurface : GoFlyStyle.surface,
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(imports.selectedID == record.id ? GoFlyStyle.primary : GoFlyStyle.border,
                              lineWidth: imports.selectedID == record.id ? 1.5 : 0.5)
        }
    }

    private func notice(_ key: String, identifier: String) -> some View {
        Label(goFlyString(key), systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(GoFlyStyle.errorForeground)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoFlyStyle.errorSurface, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
    }

    private func importURL(_ url: URL) {
        guard !isBusy else { return }
        fileOperationInProgress = true
        fileErrorKey = nil
        loadFailureKey = nil
        fileTask = Task {
            defer { fileOperationInProgress = false }
            do { _ = try await GoFlyGPXFileAccess.importFile(url, into: imports) }
            catch { presentFileError(error) }
        }
    }

    private func loadSelected() {
        guard !isBusy, controller.canEdit, executionFailureKey == nil, let id = imports.selectedID else { return }
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
                exportDocument = try GoFlyGPXExportDocument(data: data)
                exportFilename = URL(fileURLWithPath: snapshot.record.filename).deletingPathExtension().lastPathComponent
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-gofly-ui-map-metrics") {
                    let document = try GPXCodec.decode(data)
                    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    exportMetrics = "\(document.pointCount),\(data.count),\(hash)"
                }
                #endif
                showingExporter = true
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
