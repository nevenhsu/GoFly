import GoFlyCore
import SwiftUI

@main
struct GoFlyApp: App {
    @StateObject private var service = ServiceController(service: NativeDeviceService())

    var body: some Scene {
        WindowGroup {
            GoFlyMapView(service: service)
        }
    }
}
