import Darwin
import Foundation
import GoFlyCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let goFlyGPX = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

enum GoFlyGPXFileFailure: Error, Equatable {
    case unavailable, tooLarge, unsupported
    var localizationKey: String {
        switch self {
        case .unavailable: "imports.file.unavailable"
        case .tooLarge: "imports.file.tooLarge"
        case .unsupported: "imports.file.unsupported"
        }
    }
}

enum GoFlyGPXFileAccess {
    @MainActor
    static func importFile(_ url: URL, into store: ImportedRoutesStore) async throws -> Bool {
        let data = try await Task.detached(priority: .userInitiated) { try readFile(url) }.value
        try Task.checkCancellation()
        return await store.importData(data, filename: url.lastPathComponent)
    }

    /// A bounded copy for the system share sheet; it never changes the imported payload.
    static func shareURL(data: Data, filename: String) throws -> URL {
        guard data.count <= GPXLimits.fileBytes else { throw GoFlyGPXFileFailure.tooLarge }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoFlyGPXExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let basename = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let url = directory.appendingPathComponent(basename.isEmpty ? "route.gpx" : basename + ".gpx")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    private static func readFile(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw GoFlyGPXFileFailure.unsupported }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else { throw GoFlyGPXFileFailure.unavailable }
        defer { _ = Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw GoFlyGPXFileFailure.unavailable }
        guard metadata.st_mode & S_IFMT == S_IFREG else { throw GoFlyGPXFileFailure.unsupported }
        guard metadata.st_size >= 0, metadata.st_size <= GPXLimits.fileBytes else { throw GoFlyGPXFileFailure.tooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while data.count <= GPXLimits.fileBytes {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, min($0.count, GPXLimits.fileBytes + 1 - data.count))
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw GoFlyGPXFileFailure.unavailable
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw GoFlyGPXFileFailure.tooLarge
    }

    /// Data-only simulator input, selected by an explicit test argument. Import
    /// still reads this regular file through the same bounded source adapter.
    static func uiTestImportURL() throws -> URL? {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-gofly-ui-gpx-file"),
              arguments.indices.contains(index + 1) else { return nil }
        let variant = arguments[index + 1]
        guard ["valid", "gapped", "zero", "invalid", "large", "tenThousand"].contains(variant) else { return nil }
        let contents: String
        switch variant {
        case "invalid": contents = "<gpx><trk>invalid</trk></gpx>"
        case "large": contents = String(repeating: " ", count: GPXLimits.fileBytes + 1)
        case "tenThousand":
            let points = (0..<GPXLimits.points).map { index in
                let latitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), 25 + Double(index) * 0.000001)
                let longitude = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), 121.5 + Double(index) * 0.000001)
                return "<trkpt lat=\"\(latitude)\" lon=\"\(longitude)\"/>"
            }.joined()
            contents = "<gpx xmlns=\"http://www.topografix.com/GPX/1/1\" version=\"1.1\" creator=\"GoFly UI input\"><trk><trkseg>\(points)</trkseg></trk></gpx>"
        default:
            let secondSegment: String
            if variant == "gapped" {
                secondSegment = "<trkseg><trkpt lat=\"25.04\" lon=\"121.54\"/><trkpt lat=\"25.05\" lon=\"121.55\"/></trkseg>"
            } else { secondSegment = "" }
            let end = variant == "zero" ? "25.02" : "25.03"
            let endLongitude = variant == "zero" ? "121.52" : "121.53"
            contents = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="GoFly UI input">
            <trk><trkseg><trkpt lat="25.02" lon="121.52"/><trkpt lat="\(end)" lon="\(endLongitude)"/></trkseg>\(secondSegment)</trk>
            </gpx>
            """
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GoFlyGPXInputs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("\(variant).gpx")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
        #else
        return nil
        #endif
    }
}

/// Export only. Source imports never ask FileDocument to allocate a whole file.
struct GoFlyGPXExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.goFlyGPX] }
    static var writableContentTypes: [UTType] { [.goFlyGPX] }
    let data: Data

    init(data: Data) throws {
        guard data.count <= GPXLimits.fileBytes else { throw GoFlyGPXFileFailure.tooLarge }
        self.data = data
    }
    init(configuration: ReadConfiguration) throws { throw GoFlyGPXFileFailure.unsupported }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
