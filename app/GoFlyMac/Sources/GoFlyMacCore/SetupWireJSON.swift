import Foundation

/// Foundation decodes values; this bounded preflight rejects duplicate keys
/// (including escaped spellings) and a coerced protocol/journal version.
enum SetupWireJSON {
    static func object(_ data: Data, integerKey: String? = nil, integerValue: String? = nil,
                       maximumBytes: Int = 262_144) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumBytes else { throw MacSetupFailure.invalidResponse }
        var scan = Scan(bytes: Array(data), integerKey: integerKey, integerValue: integerValue)
        _ = try scan.value(depth: 0)
        scan.whitespace()
        guard scan.index == scan.bytes.count, (integerKey == nil || scan.foundInteger),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MacSetupFailure.invalidResponse
        }
        return object
    }

    private struct Scan {
        let bytes: [UInt8]
        let integerKey: String?
        let integerValue: String?
        var index = 0
        var foundInteger = false

        mutating func whitespace() {
            while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func value(depth: Int) throws -> String? {
            guard depth <= 64 else { throw MacSetupFailure.invalidResponse }
            whitespace()
            guard index < bytes.count else { throw MacSetupFailure.invalidResponse }
            switch bytes[index] {
            case 123:
                index += 1
                var names = Set<String>()
                if take(125) { return nil }
                while true {
                    let name = try string()
                    guard names.insert(name).inserted, take(58) else { throw MacSetupFailure.invalidResponse }
                    let literal = try value(depth: depth + 1)
                    if depth == 0, name == integerKey {
                        guard literal == integerValue else { throw MacSetupFailure.invalidResponse }
                        foundInteger = true
                    }
                    if take(125) { return nil }
                    guard take(44) else { throw MacSetupFailure.invalidResponse }
                }
            case 91:
                index += 1
                if take(93) { return nil }
                while true {
                    _ = try value(depth: depth + 1)
                    if take(93) { return nil }
                    guard take(44) else { throw MacSetupFailure.invalidResponse }
                }
            case 34:
                _ = try string()
                return nil
            default:
                let start = index
                while index < bytes.count, ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
                guard index > start else { throw MacSetupFailure.invalidResponse }
                return String(decoding: bytes[start..<index], as: UTF8.self)
            }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            whitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func string() throws -> String {
            whitespace()
            let start = index
            guard index < bytes.count, bytes[index] == 34 else { throw MacSetupFailure.invalidResponse }
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 92 {
                    guard index < bytes.count else { throw MacSetupFailure.invalidResponse }
                    index += 1
                } else if byte == 34 {
                    guard let result = try JSONSerialization.jsonObject(
                        with: Data(bytes[start..<index]), options: .fragmentsAllowed
                    ) as? String else { throw MacSetupFailure.invalidResponse }
                    return result
                }
            }
            throw MacSetupFailure.invalidResponse
        }
    }
}
