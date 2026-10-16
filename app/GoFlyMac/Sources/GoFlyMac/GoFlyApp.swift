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
        _model = State(initialValue: MacAppModel(live: checker))
    }

    var body: some Scene {
        Window("GoFly for Mac", id: "main") {
            MacRootView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme(.light)
                .task { model.checkEnvironment() }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Menu {
                            Button("唯讀檢查", action: { model.switchMode(preview: false) })
                            Button("介面預覽", action: { model.switchMode(preview: true) })
                        } label: {
                            Text(model.isPreview ? "介面預覽 · 示意資料" : "唯讀檢查")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .help("唯讀檢查不會安裝、簽名或寫入手機；介面預覽使用示意資料。")
                        .accessibilityIdentifier("mode-menu")
                    }
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("切換到唯讀檢查") { model.switchMode(preview: false) }
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
