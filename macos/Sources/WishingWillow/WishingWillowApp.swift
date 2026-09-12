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
        WishingWillowApp.main()
    }
}

struct WishingWillowApp: App {
    @State private var store = WillowStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu-bar glyph. It carries exactly one bit: is any live session sitting
/// on an undeclared turn. Anything more would need reading, and a menu bar is
/// not for reading.
private struct MenuBarLabel: View {
    let store: WillowStore

    var body: some View {
        Image(systemName: symbol)
            .task { store.start() }
    }

    private var symbol: String {
        let live = store.sessions.filter { !$0.isStale }
        if live.contains(where: { $0.declaration == .unreadable }) { return "exclamationmark.triangle" }
        if live.contains(where: { $0.declaration == .undeclared }) { return "leaf" }
        return "leaf.fill"
    }
}
