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

    static let wing: CGFloat = 76
    static let expandedSize = CGSize(width: 480, height: 156)

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
            ? Self.expandedSize
            : CGSize(width: g.width + Self.wing * 2, height: g.height)
        // 让路：挂到刘海下方 6pt，不和别的刘海 app 抢同一块矩形。
        let drop: CGFloat = yielding ? g.height + 6 : 0
        let rect = NSRect(x: g.midX - size.width / 2,
                          y: s.frame.maxY - drop - size.height,
                          width: size.width, height: size.height)
        panel.setFrame(rect, display: true, animate: animated)
    }

    // MARK: 交互

    private func hover(_ inside: Bool) {
        if inside {
            autoCollapse?.invalidate()
            if let f = FocusRule.focus(store, seen) { seen.markSeen(f) }
            setExpanded(true)
        } else {
            // 展开时面板在鼠标下面变大，会误报一次「离开」。等一拍再看鼠标还在不在里面。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.setExpanded(false) }
            }
        }
    }

    /// 一轮刚开始：静止展开 6 秒。不算已读 —— 面板在屏幕顶上出现，不是任何人看过的证据。
    private func flash() {
        setExpanded(true)
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.setExpanded(false) }
            }
        }
    }

    private func setExpanded(_ on: Bool) {
        guard state.expanded != on else { return }
        state.expanded = on
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
        setExpanded(true)
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
