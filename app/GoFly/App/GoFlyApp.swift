import GoFlyCore
import GoFlyTransport
import SwiftUI

@main
struct GoFlyApp: App {
    @StateObject private var service = ServiceController(service: NativeDeviceService())
    @StateObject private var onboarding = OnboardingController(
        probe: Self.onboardingProbe(), location: GoFlyLocationAuthorization()
    )
    @AppStorage("gofly.onboarding.complete") private var onboardingComplete = false

    var body: some Scene {
        WindowGroup {
            if onboardingComplete {
                GoFlyMapView(service: service)
            } else {
                GoFlyOnboardingView(controller: onboarding) {
                    onboardingComplete = true
                }
            }
        }
    }

    private static func onboardingProbe() -> any TunnelProbing {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-gofly-ui-unreachable") {
            return NetworkTunnelProbe.unavailableUITestProbe
        }
        #endif
        return NetworkTunnelProbe()
    }
}
