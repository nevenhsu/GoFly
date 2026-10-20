import Foundation
import GoFlyCore
import Network

/// Records Wi-Fi/path changes so a dropped LocalDevVPN tunnel can be told apart
/// from a native service failure after the fact. The handler runs on one serial
/// queue, which owns `lastDescription`.
final class GoFlyPathMonitor: @unchecked Sendable {
    static let shared = GoFlyPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.neven.gofly.path", qos: .utility)
    private var started = false
    private var lastDescription: String?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let description = Self.describe(path)
            guard description != self.lastDescription else { return }
            self.lastDescription = description
            Diagnostics.shared.record("tunnel.path", category: .tunnel, level: .notice, [
                "status": .text(path.status == .satisfied ? "satisfied" : "unsatisfied"),
                "wifi": .flag(path.usesInterfaceType(.wifi)),
                "wired": .flag(path.usesInterfaceType(.wiredEthernet)),
                "cellular": .flag(path.usesInterfaceType(.cellular)),
                "other": .flag(path.usesInterfaceType(.other)),
                "expensive": .flag(path.isExpensive),
                "constrained": .flag(path.isConstrained),
                "interfaces": .text(path.availableInterfaces.map {
                    "\(Self.label($0.type)):\($0.name)"
                }.joined(separator: ","))
            ])
        }
        monitor.start(queue: queue)
    }

    private static func describe(_ path: NWPath) -> String {
        [
            path.status == .satisfied ? "satisfied" : "unsatisfied",
            "wifi=\(path.usesInterfaceType(.wifi))",
            "wired=\(path.usesInterfaceType(.wiredEthernet))",
            "cellular=\(path.usesInterfaceType(.cellular))",
            "other=\(path.usesInterfaceType(.other))",
            "expensive=\(path.isExpensive)",
            "constrained=\(path.isConstrained)",
            path.availableInterfaces.map { "\(label($0.type)):\($0.name)" }.joined(separator: ",")
        ].joined(separator: "|")
    }

    private static func label(_ type: NWInterface.InterfaceType) -> String {
        switch type {
        case .wifi: "wifi"
        case .wiredEthernet: "wired"
        case .cellular: "cellular"
        case .loopback: "loopback"
        case .other: "other"
        @unknown default: "unknown"
        }
    }
}
