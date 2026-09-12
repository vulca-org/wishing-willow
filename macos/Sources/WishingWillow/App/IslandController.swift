import AppKit
import SwiftUI

/// 刘海位置的面板。
///
/// 为什么又回到刘海：先前默认走菜单栏，理由是刘海会和别的 app 冲突。
/// 但真实截图和这台机器的设置推翻了它 —— `_HIHideMenuBar = 1`，菜单栏自动隐藏，
/// 状态项大部分时间根本看不见，「常亮」在这里不可能成立。
/// 面板放在 `.mainMenu + 3`，菜单栏藏不藏都在。
///
/// 冲突的处理：boring.notch、Alcove、NotchNook 也在这一层盖同一块矩形，系统不仲裁。
/// 检测到它们在跑，就**不抢那块矩形**，改挂在刘海正下方 —— Apple 的灵动岛在
/// 多个活动并存时，本来就用一个分离出来的小胶囊。检测是按名字的启发式，写明白。
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .mainMenu + 3
        collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        appearance = NSAppearance(named: .darkAqua)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IslandController {
    private let store: WillowStore
    private let seen = SeenStore()
    private let state = IslandState()
    private let panel = IslandPanel()
    private var detail: NSWindow?
    private var autoCollapse: Timer?

    private(set) var yielding = false

    static let wing: CGFloat = 92   // 76 贴圆角、84 加内边距后截断成「审幻灯片…」；按 6 字 ≈ 67pt 算
    static let expandedWidth: CGFloat = 480

    init(store: WillowStore) { self.store = store }

    func start() {
        yielding = Self.otherNotchAppRunning()

        let host = NSHostingView(rootView: IslandView(
            store: store, seen: seen, state: state,
            notchWidth: notchGeometry().width,
            onHover: { [weak self] inside in self?.hover(inside) },
            onClick: { [weak self] in self?.openDetail() }
        ))
        panel.contentView = host

        store.onTurnStarted = { [weak self] _ in self?.flash() }
        store.start()
        layout(animated: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout(animated: false) }
        }
    }

    // MARK: 几何

    private func screen() -> NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? NSScreen.main
    }

    /// 刘海的中心 x 与宽度。没有刘海（外接屏）时给一个虚拟刘海：居中、同宽。
    private func notchGeometry() -> (midX: CGFloat, width: CGFloat, height: CGFloat) {
        guard let s = screen() else { return (0, 156, 28) }
        let f = s.frame
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            let w = f.width - l.width - r.width
            return (f.minX + l.width + w / 2, w, s.safeAreaInsets.top)
        }
        return (f.midX, 156, 28)
    }

    private func layout(animated: Bool) {
        guard let s = screen() else { return }
        let g = notchGeometry()
        let size = state.expanded
            ? CGSize(width: Self.expandedWidth, height: expandedHeight())
            : CGSize(width: g.width + Self.wing * 2, height: g.height)
        // 让路：挂到刘海下方 6pt，不和别的刘海 app 抢同一块矩形。
        let drop: CGFloat = yielding ? g.height + 6 : 0
        let rect = NSRect(x: g.midX - size.width / 2,
                          y: s.frame.maxY - drop - size.height,
                          width: size.width, height: size.height)
        panel.setFrame(rect, display: true, animate: animated)
    }

    /// 按内容量出展开高度，上下限兜住极端情况。
    private func expandedHeight() -> CGFloat {
        let probe = NSHostingController(rootView:
            IslandExpandedContent(store: store, seen: seen).frame(width: Self.expandedWidth))
        let fit = probe.sizeThatFits(in: CGSize(width: Self.expandedWidth, height: 10_000))
        return max(56, min(260, ceil(fit.height)))   // 下限 96 时一行内容会被撑出一块黑
    }

    // MARK: 交互

    /// 演示模式的日志。只在 --present 下写 stderr。
    private func demoLog(_ msg: String) {
        guard PresentDemo.seconds != nil else { return }
        FileHandle.standardError.write(Data("\(Date()) \(msg)\n".utf8))
    }

    private func hover(_ inside: Bool) {
        // 演示要可复现：你的鼠标恰好经过展开后的面板，悬停收回就会让「展开态」截图拍成收起态。
        // 忽略，但记下来——被忽略的事件本身就是证据。
        if PresentDemo.seconds != nil { demoLog("ignored hover inside=\(inside)"); return }
        if inside {
            autoCollapse?.invalidate()
            if let f = FocusRule.focus(store, seen) { seen.markSeen(f) }
            setExpanded(true, reason: "hover-in")
        } else {
            // 展开时面板在鼠标下面变大，会误报一次「离开」。等一拍再看鼠标还在不在里面。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.setExpanded(false, reason: "hover-out") }
            }
        }
    }

    /// 一轮刚开始：静止展开 6 秒。不算已读 —— 面板在屏幕顶上出现，不是任何人看过的证据。
    private func flash() {
        if PresentDemo.seconds != nil { demoLog("ignored turn-started"); return }
        setExpanded(true, reason: "turn-started")
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.setExpanded(false, reason: "flash-timeout") }
            }
        }
    }

    private func setExpanded(_ on: Bool, reason: String) {
        guard state.expanded != on else { return }
        state.expanded = on
        // 演示模式下把每次展开/收回的原因打到 stderr —— 真实截图里「该展开的时候是收起的」，
        // 不记原因就只能猜是谁收的。
        demoLog("expanded=\(on) reason=\(reason)")
        layout(animated: true)
    }

    private func openDetail() {
        if let w = detail, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "许愿柳"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: DetailView(store: store, seen: seen))
        detail = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for s in store.sessions { seen.markSeen(s) }
    }

    // MARK: 给 --present 用

    func presentExpanded() {
        store.reload()
        // 取消任何待执行的自动收回：否则演示期间恰好有一轮开始，那 6 秒的闪现计时器
        // 会在演示展开之后把它收回去 —— 真实截图里「展开态」拍到的是收起态，就是这么来的（待日志证实）。
        autoCollapse?.invalidate()
        autoCollapse = nil
        setExpanded(true, reason: "present")
    }

    /// 已知刘海类 app 在跑没有。按名字与 bundle id 的启发式：宁可误判成「有」而让路，
    /// 也不要两块面板叠在同一个矩形里抢鼠标。
    static func otherNotchAppRunning() -> Bool {
        let needles = ["notch", "alcove", "dynamiclake", "mediamate", "dynamic island"]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard app.processIdentifier != getpid() else { return false }
            let hay = ((app.bundleIdentifier ?? "") + " " + (app.localizedName ?? "")).lowercased()
            return needles.contains { hay.contains($0) }
        }
    }
}
