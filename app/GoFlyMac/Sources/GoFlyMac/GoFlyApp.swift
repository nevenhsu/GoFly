import AppKit
import SwiftUI
import GoFlyMacCore

@main
struct GoFlyApp: App {
    @State private var model: MacAppModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        let checker: any MacChecking
        do {
            checker = try ProcessBridge(
                configurationURL: resources.appendingPathComponent("LocalConfiguration.json"),
                scriptURL: resources.appendingPathComponent("Bridge/bridge.py"))
        } catch {
            checker = UnavailableChecker(reason: (error as? CheckFailure) ?? .unavailable)
        }
        let setupRunner: any MacSetupRunning
        do {
            setupRunner = try ProcessBridge(
                configurationURL: resources.appendingPathComponent("SetupConfiguration.json"),
                scriptURL: resources.appendingPathComponent("Bridge/bridge.py"))
        } catch {
            setupRunner = UnavailableChecker(reason: (error as? CheckFailure) ?? .unavailable)
        }
        let setup = MacSetupModel(runner: setupRunner, journal: BridgeStatusJournalReader(runner: setupRunner))
        _model = State(initialValue: MacAppModel(live: checker, setup: setup))
    }

    var body: some Scene {
        Window("GoFly for Mac", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    await model.restoreSetup()
                    model.checkEnvironment()
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
