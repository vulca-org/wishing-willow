import AppKit
import SwiftUI

/// 入口。`--snapshot <目录>` 走离屏渲染，不起菜单栏。
@main
enum Main {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot") {
            let out = i + 1 < args.count ? args[i + 1] : "snapshots"
            exit(Snapshot.run(outputDirectory: out))
        }
        if let i = args.firstIndex(of: "--selfshot") {
            SelfShot.run(outputDirectory: i + 1 < args.count ? args[i + 1] : "selfshots")
            return
        }
        // --present <秒>：正常启动、状态项放上真实菜单栏、弹出面板停留几秒后退出。
        // 这是给 screencapture 拍 WindowServer 那一层用的 —— 离屏渲染会吞控件，
        // cacheDisplay 拍不到玻璃与外观，只有真的摆在屏幕上才是用户看到的样子。
        if let i = args.firstIndex(of: "--present") {
            PresentDemo.seconds = i + 1 < args.count ? (Double(args[i + 1]) ?? 6) : 6
            // --real：用本机真实状态而不是样例。截图只留在本地，不进公开仓。
            PresentDemo.real = args.contains("--real")
            PresentDemo.passive = args.contains("--passive")
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum PresentDemo {
    nonisolated(unsafe) static var seconds: Double? = nil
    nonisolated(unsafe) static var real = false
    /// --passive：不强制展开、不屏蔽事件——验证「声明到达就展开」这类要按真实事件发生的行为。
    nonisolated(unsafe) static var passive = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = (PresentDemo.seconds == nil || PresentDemo.real)
        ? WillowStore()
        : WillowStore(directory: SelfShot.fixtureDirectoryForDemo())
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = IslandController(store: store)
        island = c
        c.start()

        if let hold = PresentDemo.seconds {
            // 前一半停在收起态，后一半展开 —— 两个状态各拍一张。
            if !PresentDemo.passive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold / 2) {
                    if CommandLine.arguments.contains("--detail") { c.presentDetail() } else { c.presentExpanded() }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold) {
                NSApp.terminate(nil)
            }
        }
    }
}
