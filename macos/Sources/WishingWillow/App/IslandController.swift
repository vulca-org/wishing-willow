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
/// 检测到它们在跑，就**不抢那块矩形**，改挂在刘海正下方。检测是按名字的启发式，写明白。
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
    private let seen: SeenStore
    private let state = IslandState()
    private let panel = IslandPanel()
    private var autoCollapse: Timer?
    private var hoverIntent: DispatchWorkItem?
    private var stageShrink: DispatchWorkItem?
    private var arrivals = ArrivalQueue()
    private var outsideMonitor: Any?

    private(set) var yielding = false

    static let wing: CGFloat = 92   // 76 贴圆角、84 加内边距后截断成「审幻灯片…」；按 6 字 ≈ 72pt 算
    static let expandedWidth: CGFloat = 500     // 内容宽；形状再加两侧凹肩
    static let pillHeight: CGFloat = 24
    static let pillGap: CGFloat = 6
    static let shadowPad: CGFloat = 14

    // 弹簧参数取自 boring.notch 源码：打开 (0.42, 0.8)、收起 (0.45, 1.0) 不回弹、内容挪位 (0.38, 0.8)。
    static let openSpring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let closeSpring = Animation.spring(response: 0.45, dampingFraction: 1.0)
    static let moveSpring = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// 悬停要停够这么久才展开（boring.notch 的 minimumHoverDuration）：鼠标只是去点菜单栏时路过，不弹。
    static let hoverDelay: TimeInterval = 0.3

    init(store: WillowStore, seen: SeenStore) {
        self.store = store
        self.seen = seen
    }

    func start() {
        yielding = Self.otherNotchAppRunning()
        let g = notchGeometry()

        let host = NSHostingView(rootView: IslandView(
            store: store, seen: seen, state: state,
            notchWidth: g.width, notchHeight: g.height,
            onHover: { [weak self] inside in self?.hover(inside) },
            onClick: { [weak self] in self?.openDetail() },
            onClose: { [weak self] in self?.closeDetail() },
            onSwitch: { [weak self] id in self?.switchTo(id) }
        ))
        panel.contentView = host

        store.onDeclarationArrived = { [weak self] s in self?.arrive(s.id) }
        store.onReload = { [weak self] in self?.layout(animated: true) }
        store.onLiveChange = { [weak self] in self?.layout(animated: true) }
        store.onWithdraw = { [weak self] s, kind in self?.withdraw(kind, pinning: s.id) }
        store.start()
        morph(to: targetShapeSize(expanded: false), animated: false, spring: Self.moveSpring)
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

    /// 刘海的中心 x 与宽高。没有刘海（外接屏）时给一个虚拟刘海：居中、同宽。
    private func notchGeometry() -> (midX: CGFloat, width: CGFloat, height: CGFloat) {
        guard let s = screen() else { return (0, 185, 32) }
        let f = s.frame
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            let w = f.width - l.width - r.width
            return (f.minX + l.width + w / 2, w, s.safeAreaInsets.top)
        }
        return (f.midX, 185, 32)
    }

    /// 形状的目标尺寸（含凹肩）：展开 = 内容宽 + 两肩 × 内容高；收起时有话说才长出两翼，否则缩回刘海宽。
    private func targetShapeSize(expanded: Bool) -> CGSize {
        if state.detail { return DetailView.size }
        let g = notchGeometry()
        if expanded {
            return CGSize(width: Self.expandedWidth + 2 * NotchShape.open.top, height: expandedHeight())
        }
        let primary = FocusRule.pair(store, seen, pinned: state.pinned).primary
        let wings = primary.flatMap { FocusRule.label($0, seen, store) } != nil
        return CGSize(width: wings ? g.width + Self.wing * 2 + 2 * NotchShape.closed.top : g.width,
                      height: g.height)
    }

    /// 第二个会话的胶囊宽度。只在收起态出现：展开后它挪进页脚。
    private func pillWidth() -> CGFloat {
        guard !state.expanded, !state.detail else { return 0 }
        let pair = FocusRule.pair(store, seen, pinned: state.pinned)
        guard let other = pair.secondary, FocusRule.pill(other, seen, store) != nil else { return 0 }
        return 76 + (FocusRule.extra(store, primary: pair.primary, secondary: other) > 0 ? 20 : 0)
    }

    /// 舞台尺寸：形状居中，胶囊挂右侧，所以两侧对称地留出胶囊的位置；比刘海高的形状再留出阴影。
    private func stageSize(_ shape: CGSize, pill: CGFloat) -> CGSize {
        let pad = shape.height > notchGeometry().height + 1 ? Self.shadowPad : 0
        let side = pill > 0 ? Self.pillGap + pill : 0
        return CGSize(width: shape.width + 2 * max(pad, side), height: shape.height + pad)
    }

    /// 把舞台（窗口）瞬间放到这个尺寸，贴着刘海居中。舞台透明，不画任何东西。
    private func placeStage(_ size: CGSize) {
        guard let s = screen() else { return }
        let g = notchGeometry()
        let drop: CGFloat = yielding ? g.height + 6 : 0      // 让路：挂到刘海下方
        let rect = NSRect(x: g.midX - size.width / 2,
                          y: s.frame.maxY - drop - size.height,
                          width: size.width, height: size.height)
        let f = panel.frame
        if abs(f.minX - rect.minX) < 0.5, abs(f.minY - rect.minY) < 0.5,
           abs(f.width - rect.width) < 0.5, abs(f.height - rect.height) < 0.5 { return }
        panel.setFrame(rect, display: true)
    }

    /// 黑色形状此刻在屏幕上的矩形。悬停与点外面的判断用它，不用舞台——舞台比形状大。
    private func shapeScreenRect() -> NSRect {
        guard let s = screen() else { return .zero }
        let g = notchGeometry()
        let drop: CGFloat = yielding ? g.height + 6 : 0
        let sz = state.shapeSize
        return NSRect(x: g.midX - sz.width / 2, y: s.frame.maxY - drop - sz.height,
                      width: sz.width, height: sz.height)
    }

    /// 形状变到 target：舞台先撑到「现在与目标的较大者」，形状 spring 过去；
    /// 若是变小，等动画结束再把舞台缩回，否则形状会被窗口边裁掉。
    private func morph(to target: CGSize, animated: Bool, spring: Animation) {
        stageShrink?.cancel()
        let pill = pillWidth()
        guard animated else {
            state.shapeSize = target
            state.pillWidth = pill
            placeStage(stageSize(target, pill: pill))
            return
        }
        let nowStage = stageSize(state.shapeSize, pill: state.pillWidth)
        let nextStage = stageSize(target, pill: pill)
        placeStage(CGSize(width: max(nowStage.width, nextStage.width),
                          height: max(nowStage.height, nextStage.height)))
        withAnimation(spring) {
            state.shapeSize = target
            state.pillWidth = pill
        }
        if nextStage.width < nowStage.width || nextStage.height < nowStage.height {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.placeStage(self.stageSize(self.state.shapeSize, pill: self.state.pillWidth))
            }
            stageShrink = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }

    private func layout(animated: Bool) {
        let target = targetShapeSize(expanded: state.expanded)
        if animated && state.shapeSize == target && state.pillWidth == pillWidth() { return }
        morph(to: target, animated: animated, spring: Self.moveSpring)
    }

    /// 按内容量出展开高度，上下限兜住极端情况。
    private func expandedHeight() -> CGFloat {
        let g = notchGeometry()
        let probe = NSHostingController(rootView:
            IslandExpandedContent(store: store, seen: seen, pinned: state.pinned,
                                  notchWidth: g.width, notchHeight: g.height)
                .frame(width: Self.expandedWidth))
        let fit = probe.sizeThatFits(in: CGSize(width: Self.expandedWidth, height: 10_000))
        return max(72, min(300, ceil(fit.height)))
    }

    // MARK: 交互

    /// 演示模式的日志。只在 --present 下写 stderr。
    private func demoLog(_ msg: String) {
        guard PresentDemo.seconds != nil else { return }
        FileHandle.standardError.write(Data("\(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(Date())) \(msg)\n".utf8))
    }

    private func hover(_ inside: Bool) {
        // 演示要可复现：你的鼠标恰好经过展开后的面板，悬停收回就会让「展开态」截图拍成收起态。
        // 忽略，但记下来——被忽略的事件本身就是证据。
        if PresentDemo.seconds != nil && !PresentDemo.passive { demoLog("ignored hover inside=\(inside)"); return }
        if state.detail { return }                          // 面板打开时悬停不收放
        hoverIntent?.cancel()
        if inside {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.shapeScreenRect().insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation) else { return }
                self.autoCollapse?.invalidate()
                // 钉住收起态正在显示的那个会话：展开的必须是你刚才看到的那个（HIG：展开态是放大的收起态）。
                if let f = FocusRule.pair(self.store, self.seen, pinned: self.state.pinned).primary {
                    self.state.pinned = f.id
                    self.seen.markSeen(f)
                }
                self.setExpanded(true, reason: "hover-in")
            }
            hoverIntent = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
        } else {
            // 展开时形状在鼠标下面变大，会误报一次「离开」。等一拍再看鼠标还在不在形状里。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                if !self.shapeScreenRect().contains(NSEvent.mouseLocation) { self.setExpanded(false, reason: "hover-out") }
            }
        }
    }

    /// 声明到达：没在展示别的就展开 6 秒；正在展示另一个会话就排队，不顶掉你读到一半的那个。
    private func arrive(_ id: String) {
        if PresentDemo.seconds != nil && !PresentDemo.passive { demoLog("ignored declaration-arrived"); return }
        if state.detail { return }
        let showing = state.expanded ? state.pinned : nil
        if arrivals.offer(id, showing: showing) {
            flash(pinning: id)
        } else {
            demoLog("queued \(id.prefix(8)) behind \(showing.map { String($0.prefix(8)) } ?? "-")")
            layout(animated: true)
        }
    }

    /// 静止展开 6 秒。不算已读 —— 面板在屏幕顶上出现，不是任何人看过的证据。
    private func flash(pinning id: String) {
        if state.detail { return }
        state.pinned = id
        if state.expanded {
            morph(to: targetShapeSize(expanded: true), animated: true, spring: Self.moveSpring)
        } else {
            setExpanded(true, reason: "declaration-arrived")
        }
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.shapeScreenRect().contains(NSEvent.mouseLocation) { self.setExpanded(false, reason: "flash-timeout") }
            }
        }
    }

    /// 页脚或胶囊：切到那个会话并展开。这是你主动点的，算看过。
    private func switchTo(_ id: String) {
        guard let s = store.sessions.first(where: { $0.id == id }) else { return }
        demoLog("switch \(id.prefix(8))")
        autoCollapse?.invalidate(); autoCollapse = nil
        seen.markSeen(s)
        if state.expanded {
            withAnimation(Self.moveSpring) { state.pinned = id }
            morph(to: targetShapeSize(expanded: true), animated: true, spring: Self.moveSpring)
        } else {
            state.pinned = id
            setExpanded(true, reason: "pill")
        }
    }

    /// 撤回：两翼换成「已撤回 / 撤回排队」（由 FocusRule 读 recentWithdraw），停一会儿后弹回刘海。
    /// 若正展开着且是打断，让「你撤回了这一轮」停 1.8 秒再收。
    private func withdraw(_ kind: WillowStore.WithdrawKind, pinning id: String) {
        if PresentDemo.seconds != nil && !PresentDemo.passive { demoLog("ignored withdraw \(kind)"); return }
        demoLog("withdraw \(kind)")
        if state.expanded { state.pinned = id }
        layout(animated: true)
        guard kind == .interrupted, state.expanded, !state.detail else { return }
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.setExpanded(false, reason: "withdraw") }
        }
    }

    private func setExpanded(_ on: Bool, reason: String) {
        guard state.expanded != on else { return }
        // 每次展开/收回都记原因 —— 真实截图里「该展开的时候是收起的」，不记原因就只能猜。
        demoLog("expanded=\(on) reason=\(reason)")
        hoverIntent?.cancel()
        if !on { afterCollapse(pin: state.pinned) }
        let spring = on ? Self.openSpring : Self.closeSpring
        withAnimation(spring) { state.expanded = on }
        morph(to: targetShapeSize(expanded: on), animated: true, spring: spring)
    }

    /// 收起动画走完之后：松开钉住（立刻松开的话，收起途中内容会跳成另一个会话），再轮到排队的下一个。
    private func afterCollapse(pin: String?) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(550))
            guard let self, !self.state.expanded, !self.state.detail else { return }
            if pin != nil, self.state.pinned == pin {
                self.state.pinned = nil
                self.layout(animated: true)
            }
            let alive = Set(FocusRule.live(self.store)
                .filter { self.seen.isUnread($0) || $0.declaration == .inProgress }
                .map(\.id))
            if let next = self.arrivals.next(alive: alive) {
                self.demoLog("dequeued \(next.prefix(8))")
                self.flash(pinning: next)
            }
        }
    }

    /// 点击：灵动岛再长大一档变成面板。不是另开窗口——用户实测原来的标准窗口「跳脱」。
    private func openDetail() {
        guard !state.detail else { return }
        autoCollapse?.invalidate(); autoCollapse = nil
        hoverIntent?.cancel()
        for s in store.sessions { seen.markSeen(s) }
        demoLog("detail=true")
        withAnimation(Self.openSpring) { state.detail = true; state.expanded = true }
        morph(to: DetailView.size, animated: true, spring: Self.openSpring)
        installOutsideMonitor()
    }

    func closeDetail() {
        guard state.detail else { return }
        removeOutsideMonitor()
        demoLog("detail=false")
        withAnimation(Self.closeSpring) { state.detail = false; state.expanded = false }
        morph(to: targetShapeSize(expanded: false), animated: true, spring: Self.closeSpring)
        afterCollapse(pin: state.pinned)
    }

    /// 点面板外面就收起。只监听鼠标按下：全局键盘监听要辅助功能权限，这个 app 不要那个权限。
    private func installOutsideMonitor() {
        removeOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state.detail else { return }
                if !self.shapeScreenRect().contains(NSEvent.mouseLocation) { self.closeDetail() }
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor { NSEvent.removeMonitor(m) }
        outsideMonitor = nil
    }

    // MARK: 给 --present 用

    /// 演示用：直接打开点击后的面板。
    func presentDetail() { openDetail() }

    func presentExpanded() {
        store.reload()
        // 取消任何待执行的自动收回：否则演示期间恰好有一轮开始，那 6 秒的闪现计时器
        // 会在演示展开之后把它收回去。
        autoCollapse?.invalidate()
        autoCollapse = nil
        if let f = FocusRule.pair(store, seen, pinned: nil).primary { state.pinned = f.id }
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
