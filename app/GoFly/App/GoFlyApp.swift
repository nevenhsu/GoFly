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
        #if DEBUG && targetEnvironment(simulator)
        if !GoFlyIconPreview.isRequested { GoFlySetupFixture.seedIfRequested() }
        #else
        GoFlySetupFixture.seedIfRequested()
        #endif
        _bootstrap = StateObject(wrappedValue: GoFlySetupBootstrap())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if GoFlyIconPreview.isRequested {
                    GoFlyIconPreview(bootstrapIsIdle: bootstrap.runtime == nil
                        && bootstrap.startupTask == nil && bootstrap.transferTask == nil)
                } else {
                    startupContent
                }
                #else
                startupContent
                #endif
            }
            .environment(\.locale, preferences.locale)
            .preferredColorScheme(preferences.colorScheme)
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                #if DEBUG && targetEnvironment(simulator)
                if GoFlyIconPreview.isRequested { return }
                #endif
                await bootstrap.observeMacCommands()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    preferences.refreshSystemPreferences()
                } else {
                    bootstrap.invalidateMacCommandObservation()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                preferences.refreshSystemPreferences()
            }
            .onOpenURL { url in
                #if DEBUG && targetEnvironment(simulator)
                if GoFlyIconPreview.isRequested { return }
                #endif
                bootstrap.handle(url: url)
            }
        }
    }

    @ViewBuilder
    private var startupContent: some View {
        if bootstrap.phase.isTransferLocked {
            GoFlyTransferLockView(phase: bootstrap.phase)
        } else if let runtime = bootstrap.runtime {
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
