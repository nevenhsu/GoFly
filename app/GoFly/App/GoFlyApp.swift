import GoFlyCore
import GoFlyTransport
import SwiftUI

@main
struct GoFlyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = GoFlyPreferences.shared
    @StateObject private var bootstrap: GoFlySetupBootstrap
    @AppStorage("gofly.onboarding.complete") private var onboardingComplete = false

    init() {
        _ = GoFlyPreferences.shared
        GoFlySetupFixture.seedIfRequested()
        _bootstrap = StateObject(wrappedValue: GoFlySetupBootstrap())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let runtime = bootstrap.runtime {
                    normalRuntimeView(runtime)
                } else {
                    GoFlySetupLockView(phase: bootstrap.phase, onRetry: bootstrap.retry)
                }
            }
            .environment(\.locale, preferences.locale)
            .preferredColorScheme(preferences.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { preferences.refreshSystemPreferences() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                preferences.refreshSystemPreferences()
            }
        }
    }

    @ViewBuilder
    private func normalRuntimeView(_ runtime: GoFlyRuntimeAssembly) -> some View {
        Group {
            if onboardingComplete {
                GoFlyMapView(
                    service: runtime.service,
                    recoveryStore: runtime.sessionRecovery,
                    movement: runtime.movement,
                    setupMetadata: bootstrap.metadata
                )
            } else {
                GoFlyOnboardingView(controller: runtime.onboarding) {
                    onboardingComplete = true
                }
            }
        }
        .onChange(of: preferences.effectiveLanguage) { _, _ in
            runtime.movement.continuation.refreshPresentation()
        }
        .environmentObject(runtime.favorites)
        .environmentObject(runtime.importedRoutes)
        .environmentObject(runtime.favoriteRoutes)
        .task {
            await runtime.importedRoutes.load()
            await runtime.favoriteRoutes.load()
        }
    }
}
