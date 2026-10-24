import Combine
import Foundation
import Network
import UIKit

/// Manages Wi-Fi connection state and synchronization across the map and settings.
@MainActor
final class GoFlyNetworkMonitor: ObservableObject {
    static let shared = GoFlyNetworkMonitor()

    @Published private(set) var isWiFiConnected: Bool = true
    @Published var wifiNoticeDismissed: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.neven.gofly.network", qos: .utility)
    private var started = false

    private init() {
        start()
    }

    func start() {
        guard !started else { return }
        started = true
        isWiFiConnected = evaluatePath(monitor.currentPath)
        monitor.pathUpdateHandler = { [weak self] path in
            let current = Self.evaluate(path)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let previous = self.isWiFiConnected
                self.isWiFiConnected = current
                if !previous && current {
                    self.wifiNoticeDismissed = false
                }
            }
        }
        monitor.start(queue: queue)
    }

    private func evaluatePath(_ path: NWPath) -> Bool {
        Self.evaluate(path)
    }

    private nonisolated static func evaluate(_ path: NWPath) -> Bool {
        #if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-wifi-disconnected") {
            return false
        } else if ProcessInfo.processInfo.arguments.contains("-gofly-ui-wifi-connected") {
            return true
        } else {
            return path.status == .satisfied && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
        }
        #else
        return path.status == .satisfied && path.usesInterfaceType(.wifi)
        #endif
    }

    var shouldShowWiFiError: Bool {
        !isWiFiConnected && !wifiNoticeDismissed
    }

    /// Re-reads the current path; the toast stays only while Wi-Fi is still missing.
    func recheck() {
        isWiFiConnected = Self.evaluate(monitor.currentPath)
        wifiNoticeDismissed = false
    }

    func dismissNotice() {
        wifiNoticeDismissed = true
    }

    func resetNotice() {
        wifiNoticeDismissed = false
    }

    func openWiFiSettings() {
        let candidates = [
            "App-Prefs:root=WIFI",
            "App-prefs:root=WIFI",
            "prefs:root=WIFI"
        ]
        func tryCandidate(at index: Int) {
            guard index < candidates.count else {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL, options: [:], completionHandler: nil)
                }
                return
            }
            if let url = URL(string: candidates[index]) {
                UIApplication.shared.open(url, options: [:]) { opened in
                    if !opened {
                        tryCandidate(at: index + 1)
                    }
                }
            } else {
                tryCandidate(at: index + 1)
            }
        }
        tryCandidate(at: 0)
    }
}
