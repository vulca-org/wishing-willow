import AppKit
import SwiftUI

/// `--backdrop`（只配合 `--present`）：在刘海下方铺一块底色，给 README 拍图和录屏用。
///
/// 真屏幕上拍，背后会拍进别的窗口——公开素材里不能出现作者屏幕上的其他东西；
/// 离屏渲染又不忠实（见 macos/README「验收只认真实屏幕」）。所以还是在真屏幕上拍，
/// 只是先盖一层：层级在菜单栏之上、灵动岛之下，不接鼠标。
/// 只盖拍摄区域（刘海居中 760×520pt，装得下最高的展开态 470pt 加阴影），录素材的几分钟里屏幕其余部分照常能用。
@MainActor
enum Backdrop {
    static let size = CGSize(width: 760, height: 520)

    static var isOn: Bool { PresentDemo.seconds != nil && CommandLine.arguments.contains("--backdrop") }

    static func show() -> NSWindow? {
        guard isOn, let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main else {
            return nil
        }
        let f = screen.frame
        let rect = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
        let w = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: BackdropView())
        w.setFrame(rect, display: true)
        w.orderFrontRegardless()
        return w
    }
}

/// 浅冷色的桌面：纯黑的岛要一眼读得出轮廓，顶上一团亮光把视线引到刘海。
private struct BackdropView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.80, green: 0.85, blue: 0.92), Color(red: 0.49, green: 0.57, blue: 0.70)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.7), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Color(red: 0.36, green: 0.44, blue: 0.62).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.15, y: 1), startRadius: 0, endRadius: 900)
        }
        .ignoresSafeArea()
    }
}
