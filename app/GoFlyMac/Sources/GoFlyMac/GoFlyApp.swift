import AppKit
import SwiftUI
import GoFlyMacCore
import CoreText

@main
struct GoFlyApp: App {
    @State private var model: MacAppModel
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        if let fontURL = Bundle.module.url(forResource: "NotoSansTC", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
        let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")
        let checker: any MacChecking = (try? ProcessBridge(
            configurationURL: resources.appendingPathComponent("LocalConfiguration.json"),
            scriptURL: resources.appendingPathComponent("Bridge/bridge.py"))) ?? UnavailableChecker()
        let setupRunner: any MacSetupRunning = (try? SetupProcessBridge(
            configurationURL: resources.appendingPathComponent("SetupConfiguration.json"),
            scriptURL: resources.appendingPathComponent("Bridge/Setup/setup_bridge.py"))) ?? UnavailableSetupRunner()
        let stateRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GoFlySetup")
        let setup = MacSetupModel(runner: setupRunner, journal: MacSetupJournalReader(stateRoot: stateRoot))
        _model = State(initialValue: MacAppModel(live: checker, setup: setup))
    }

    var body: some Scene {
        Window("GoFly for Mac", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme(.light)
                .task { await model.restoreSetup(); model.checkEnvironment() }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button("實際操作", action: { model.switchMode(preview: false) })
                            Button("介面預覽", action: { model.switchMode(preview: true) })
                        } label: {
                            Text(model.isPreview ? "介面預覽 · 示意資料" : "實際操作")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .help("唯讀檢查不會變更手機；按開始安裝才會簽署、配對與安裝。介面預覽使用示意資料。")
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
