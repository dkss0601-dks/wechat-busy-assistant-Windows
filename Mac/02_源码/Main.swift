import Cocoa
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var model: Assistant?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = Assistant(); self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 810), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "忙碌消息助手"
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: AssistantView(model: model))
        window.minSize = NSSize(width: 950, height: 740)
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.stop("应用已退出。") }
}

@main struct Launcher {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            selfTest()
            profileRulesTests()
            conversationRulesTests()
            _ = MainActor.assumeIsolated { Task { await lifecycleTests(); await profileLifecycleTests(); await conversationLifecycleTests(); await firstScreenLifecycleTests(); await firstScreenAlignmentTests(); activityDescriptionTests(); await freshnessTests(); exit(0) } }
            RunLoop.main.run(); return
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared; let delegate = AppDelegate()
            app.delegate = delegate; app.setActivationPolicy(.regular)
            let menu = NSMenu(); let appItem = NSMenuItem(); menu.addItem(appItem)
            let appMenu = NSMenu(); appItem.submenu = appMenu
            appMenu.addItem(withTitle: "退出忙碌消息助手", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            let edit = NSMenuItem(); menu.addItem(edit); edit.submenu = NSMenu(title: "编辑")
            edit.submenu?.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            edit.submenu?.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            edit.submenu?.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            edit.submenu?.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            app.mainMenu = menu; app.run()
        }
    }
}
