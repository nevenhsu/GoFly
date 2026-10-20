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
        Diagnostics.shared.start()
        GoFlyPathMonitor.shared.start()
        _ = GoFlyPreferences.shared
        _bootstrap = StateObject(wrappedValue: GoFlySetupBootstrap())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                startupContent
            }
            .environment(\.locale, preferences.locale)
            .preferredColorScheme(preferences.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                Diagnostics.shared.record("background.scene", category: .background, level: .notice, [
                    "phase": .text(Self.label(phase)),
                    "onboarding": .flag(onboardingComplete)
                ])
                if phase == .active { preferences.refreshSystemPreferences() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                preferences.refreshSystemPreferences()
            }
        }
    }

    @ViewBuilder
    private var startupContent: some View {
        if let runtime = bootstrap.runtime {
            normalRuntimeView(runtime)
        } else if !onboardingComplete, bootstrap.phase == .preparing {
            NavigationStack {
                GoFlyWelcomeView(isPreparing: true, onNext: {})
            }
            .tint(GoFlyStyle.primary)
        } else {
            GoFlySetupLockView(phase: bootstrap.phase, onRetry: bootstrap.retry)
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

private extension GoFlyApp {
    static func label(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
