import Foundation
import Testing
@testable import GoFlyCore

final class CapturingSink: DiagnosticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiagnosticsRecord] = []

    var records: [DiagnosticsRecord] { lock.withLock { storage } }

    func write(_ record: DiagnosticsRecord) {
        lock.withLock { storage.append(record) }
    }
}

private func temporaryDirectory(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("gofly-\(label)-\(UUID().uuidString)", isDirectory: true)
}

struct DiagnosticsRecordTests {
    @Test func recordRendersOneBoundedLineAndOneJSONObject() throws {
        let event = DiagnosticsEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.5),
            category: .device, level: .notice, name: "device.tick",
            fields: [
                "b": .count(2),
                "a": .coordinate(latitude: 25.0333333, longitude: 121.5654321),
                "note": .text("line1\nline2"),
                "ok": .flag(true),
                "code": .code(-109),
                "ms": .milliseconds(12.34)
            ])
        let record = DiagnosticsRecord(event: event)

        #expect(record.line.hasPrefix("NOTICE device device.tick"))
        #expect(!record.line.contains("\n"))
        // Field order is stable so logs can be diffed between runs.
        #expect(record.line.contains("a=25.033,121.565"))
        #expect(record.line.contains("note=line1 line2"))
        #expect(record.line.contains("code=-109"))
        #expect(record.line.contains("ms=12.3"))

        let json = try #require(try JSONSerialization.jsonObject(with: Data(record.json.utf8)) as? [String: Any])
        #expect(json["cat"] as? String == "device")
        #expect(json["lvl"] as? String == "notice")
        #expect(json["name"] as? String == "device.tick")
        #expect(json["t"] as? Double == 1_700_000_000.5)
        let fields = try #require(json["fields"] as? [String: Any])
        #expect(fields["a"] as? String == "25.033,121.565")
        #expect(fields["ok"] as? Int == 1)
        #expect(fields["code"] as? Int == -109)
    }

    @Test func textFieldsAreCollapsedAndTruncatedSoOneEventStaysOneRecord() throws {
        let long = String(repeating: "x", count: 300) + "\n" + String(repeating: "y", count: 10)
        let record = DiagnosticsRecord(event: DiagnosticsEvent(
            category: .movement, level: .debug, name: "text", fields: ["v": .text(long)]))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(record.json.utf8)) as? [String: Any])
        let fields = try #require(object["fields"] as? [String: Any])
        let value = try #require(fields["v"] as? String)
        #expect(value.count == 96)
        #expect(!value.contains("\n"))
        #expect(!record.json.contains("\n"))
    }
}

struct DiagnosticsFileSinkTests {
    @Test func appendsAreBoundedAndKeepTheNewestRecordsAtLineBoundaries() throws {
        let directory = temporaryDirectory("ring")
        let sink = DiagnosticsFileSink(directory: directory, filename: "gofly.jsonl", maximumBytes: 4_096)
        for index in 0..<200 {
            let padding = String(repeating: "x", count: 40)
            sink.append(Data("{\"i\":\(index),\"pad\":\"\(padding)\"}\n".utf8))
        }
        let data = try #require(sink.load())
        #expect(data.count <= 4_096)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"i\":199"))
        #expect(!text.contains("{\"i\":0,"))
        // A trim records itself and never leaves a partial line behind.
        #expect(text.contains("diagnostics.ring.trimmed"))
        for line in text.split(separator: "\n") {
            #expect((try? JSONSerialization.jsonObject(with: Data(line.utf8))) != nil)
        }
    }

    @Test func ringFileAndDirectoryAreNotWorldReadable() throws {
        let directory = temporaryDirectory("mode")
        let sink = DiagnosticsFileSink(directory: directory, filename: "gofly.jsonl", maximumBytes: 1 << 20)
        sink.append(Data("{}\n".utf8))
        let directoryMode = try #require(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)
        let fileMode = try #require(FileManager.default.attributesOfItem(atPath: sink.url.path)[.posixPermissions] as? NSNumber)
        #expect(directoryMode.intValue & 0o777 == 0o700)
        #expect(fileMode.intValue & 0o777 == 0o600)
    }

    @Test func appendSurvivesAMissingParentWithoutReportingSuccess() throws {
        // A directory that cannot be created is a no-op, never a crash.
        let sink = DiagnosticsFileSink(directory: URL(fileURLWithPath: "/dev/null/nope"),
                                       filename: "gofly.jsonl", maximumBytes: 1 << 20)
        sink.append(Data("{}\n".utf8))
        #expect(sink.size == 0)
        #expect(sink.load() == nil)
    }
}

struct DiagnosticsExportTests {
    @Test func exportCopiesTheRingWithAHeaderIntoAShareableFile() throws {
        let ring = temporaryDirectory("export-ring")
        let exports = temporaryDirectory("export-out")
        let diagnostics = Diagnostics()
        diagnostics.start(directory: ring)
        diagnostics.record("test.export", category: .device, level: .notice, ["a": .count(1)])
        let url = try diagnostics.export(directory: exports)

        #expect(url.pathExtension == "jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("# GoFly diagnostics"))
        #expect(text.contains("test.export"))
        let exportedMode = try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)
        #expect(exportedMode.intValue & 0o777 == 0o600)
    }

    @Test func exportWorksBeforeAnyEventWasWritten() throws {
        let diagnostics = Diagnostics()
        diagnostics.start(directory: temporaryDirectory("export-empty"))
        let url = try diagnostics.export(directory: temporaryDirectory("export-empty-out"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("# GoFly diagnostics"))
    }
}

struct DiagnosticsFanOutTests {
    @Test func eventsReachAttachedSinksInOrderAndDetachStopsThem() {
        let sink = CapturingSink()
        Diagnostics.shared.attach(sink)
        Diagnostics.shared.record("test.fanout.first", category: .movement, level: .notice, ["a": .count(1)])
        Diagnostics.shared.record("test.fanout.second", category: .movement, level: .debug, ["a": .count(2)])
        Diagnostics.shared.flush()
        Diagnostics.shared.detach(sink)
        Diagnostics.shared.record("test.fanout.afterDetach", category: .movement, level: .notice)
        Diagnostics.shared.flush()

        let names = sink.records.map(\.event.name)
        #expect(names.contains("test.fanout.first"))
        #expect(names.contains("test.fanout.second"))
        #expect(!names.contains("test.fanout.afterDetach"))
        #expect(names.firstIndex(of: "test.fanout.first")! < names.firstIndex(of: "test.fanout.second")!)
    }
}
