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
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PresentDemo.seconds == nil
        ? WillowStore()
        : WillowStore(directory: SelfShot.fixtureDirectoryForDemo())
    private var island: IslandController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = IslandController(store: store)
        island = c
        c.start()

        if let hold = PresentDemo.seconds {
            // 前一半停在收起态，后一半展开 —— 两个状态各拍一张。
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold / 2) {
                c.presentExpanded()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold) {
                NSApp.terminate(nil)
            }
        }
    }
}
