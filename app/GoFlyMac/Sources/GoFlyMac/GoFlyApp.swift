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
        let appModel = MacAppModel(live: checker, setup: setup)
        if CommandLine.arguments.contains("--preview") { appModel.switchMode(preview: true) }
        _model = State(initialValue: appModel)
    }

    var body: some Scene {
        Window("GoFly for Mac", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .task {
                    if !model.isPreview { await model.restoreSetup() }
                    model.checkEnvironment()
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button("實際操作", action: { model.switchMode(preview: false) })
                            Button("介面預覽", action: { model.switchMode(preview: true) })
                        } label: {
                            Text(model.isPreview ? "介面預覽 · 示意資料" : "實際操作")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .help("切換實際操作與示意資料。介面預覽不會操作手機。")
                        .accessibilityIdentifier("mode-menu")
                    }
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("切換到實際操作") { model.switchMode(preview: false) }
                Button("切換到介面預覽") { model.switchMode(preview: true) }
            }
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
