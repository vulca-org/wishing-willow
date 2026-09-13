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
        // --anatomy <目录>：导出左翼状态的工程标注图（中英各一张），给 README 与设计评审用。
        if let i = args.firstIndex(of: "--anatomy") {
            exit(Anatomy.run(outputDirectory: i + 1 < args.count ? args[i + 1] : "anatomy"))
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
    private var backdrop: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 样例演示用不落盘的已读记录：先前演示把样例会话标成已读写进了真实的 seen.json，
        // 之后拍收起态时两翼全缩回刘海——拍到的是上一次演示留下的状态。
        let demo = PresentDemo.seconds != nil && !PresentDemo.real
        backdrop = Backdrop.show()
        let c = IslandController(store: store, seen: demo ? SeenStore(ephemeral: true) : SeenStore())
        island = c
        c.start()

        if let hold = PresentDemo.seconds {
            // 前一半停在收起态，后一半展开 —— 两个状态各拍一张。
            if !PresentDemo.passive {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold / 2) {
                    if CommandLine.arguments.contains("--detail") {
                        c.presentDetail()
                    } else if !CommandLine.arguments.contains("--pill-cycle") {
                        c.presentExpanded()
                    }
                }
                // --expand-then-detail：先展开，1.6 秒后再打开面板——走用户真实的「悬停展开 → 点击」路径，
                // 录「展开态换成面板」那一段过渡（用户报过文字叠加）。
                if CommandLine.arguments.contains("--expand-then-detail") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold / 2 + 1.6) { c.presentDetail() }
                }
                // --pill-cycle：展开（胶囊吸回岛里）→ 收起（胶囊滴出去）→ 胶囊悬停预览 → 离开 → 岛悬停鼓起 → 复原。
                // 录第二个会话胶囊的出场、收回与悬停动效。
                if CommandLine.arguments.contains("--pill-cycle") {
                    let t0 = 3.5
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0) { c.presentExpanded() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 2.0) { c.presentCollapse() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 4.0) { c.presentPillHover(true) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 5.5) { c.presentPillHover(false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 6.5) { c.presentHoverBump(true) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + t0 + 7.5) { c.presentHoverBump(false) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + hold) {
                NSApp.terminate(nil)
            }
        }
    }
}
