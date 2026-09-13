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
///
/// 窗口是固定大小的透明舞台。**不要设置 `ignoresMouseEvents`**：保持默认时，窗口里 alpha 为 0 的像素
/// 让鼠标事件穿过去，舞台的透明部分不挡菜单栏；显式设成 false 会让整块舞台吞掉点击。
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
    private var pillEmerge: DispatchWorkItem?
    private var pillRetract: DispatchWorkItem?
    private var arrivals = ArrivalQueue()
    private var outsideMonitor: Any?

    private(set) var yielding = false

    static let wing: CGFloat = 92   // 76 贴圆角、84 加内边距后截断成「审幻灯片…」；按 6 字 ≈ 72pt 算
    static let expandedWidth: CGFloat = 500     // 内容宽；形状再加两侧凹肩
    static let maxExpandedHeight: CGFloat = 470
    static let pillHeight: CGFloat = 24
    static let pillGap: CGFloat = 6
    static let pillMax: CGFloat = 120
    /// 鼠标停在胶囊上时向右长出的宽度，用来放那个会话的标签。
    static let pillPreview: CGFloat = 130     // 标签 + 「· 共 N 个」
    /// 悬停那 0.3 秒里岛先鼓起多少。
    static let hoverBump = CGSize(width: 10, height: 2)
    static let shadowPad: CGFloat = 16

    // 弹簧参数的基准取自 boring.notch 源码：打开 (0.42, 0.8)、收起 (0.45, 1.0) 不回弹、内容挪位 (0.38, 0.8)。
    // 用户要「从上到下、由内向外」：宽和高拆开走——展开时宽先到（从刘海向两边），高后到（往下长）；
    // 收起反过来，高先收回、宽再收进刘海。
    static let openWidth = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let openHeight = Animation.spring(response: 0.5, dampingFraction: 0.84)
    static let closeHeight = Animation.spring(response: 0.3, dampingFraction: 1.0)
    static let closeWidth = Animation.spring(response: 0.45, dampingFraction: 1.0)
    static let moveSpring = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// 悬停鼓起：短而有一点回弹，像按下去之前的那一下。
    static let hoverSpring = Animation.spring(response: 0.26, dampingFraction: 0.62)
    /// 胶囊滴出去：有回弹，连桥拉长再断开；收回：不回弹，干脆地吸回岛里。
    static let pillOutSpring = Animation.spring(response: 0.52, dampingFraction: 0.64)
    static let pillInSpring = Animation.spring(response: 0.3, dampingFraction: 0.92)
    static let pillHoverSpring = Animation.spring(response: 0.34, dampingFraction: 0.74)
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
            onPillHover: { [weak self] inside in self?.pillHover(inside) },
            onClick: { [weak self] in self?.openDetail() },
            onClose: { [weak self] in self?.closeDetail() },
            onSwitch: { [weak self] id in self?.switchTo(id) }
        ))
        panel.contentView = host

        store.onDeclarationArrived = { [weak self] s in self?.arrive(s.id, reason: "declaration-arrived") }
        store.onReload = { [weak self] in self?.layout(animated: true) }
        store.onLiveChange = { [weak self] in self?.layout(animated: true) }
        store.onWithdraw = { [weak self] s, kind in self?.withdraw(kind, pinning: s.id) }
        store.onChoiceArrived = { [weak self] s in self?.arrive(s.id, reason: "choice-arrived") }
        store.start()
        placeStage()
        morph(to: targetShapeSize(expanded: false), .move, animated: false)
        updatePill(animated: false)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.placeStage()
                self?.layout(animated: false)
            }
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
        var size = CGSize(width: wings ? g.width + Self.wing * 2 + 2 * NotchShape.closed.top : g.width,
                          height: g.height)
        if state.hovering {
            size.width += Self.hoverBump.width
            size.height += Self.hoverBump.height
        }
        return size
    }

    /// 第二个会话的胶囊宽度。只在收起态出现：展开后它挪进展开态底部那一行。
    private func pillWidth() -> CGFloat {
        guard !state.expanded, !state.detail else { return 0 }
        let pair = FocusRule.pair(store, seen, pinned: state.pinned)
        guard let other = pair.secondary, let pill = FocusRule.pill(other, seen, store) else { return 0 }
        return min(Self.pillMax, SessionPill.width(pill))
    }

    /// 舞台固定大小：装得下点击面板、最高的展开态、带胶囊（含悬停预览）的收起态，外加阴影。
    ///
    /// 先前舞台跟着形状改尺寸。录屏逐帧量展开时宽度 690→816→787→779→814，不是单调长大；
    /// 推断是窗口变大那一帧旧画面贴在新窗口左下角，形状先偏左再弹回中间——用户看到的「从左到右出现」。
    private func stageSize() -> CGSize {
        let g = notchGeometry()
        let compactWithPill = g.width + Self.wing * 2 + 2 * NotchShape.closed.top + Self.hoverBump.width
            + 2 * (Self.pillGap + Self.pillMax + Self.pillPreview + 10)
        let w = max(DetailView.size.width, Self.expandedWidth + 2 * NotchShape.open.top, compactWithPill) + 2 * Self.shadowPad
        let h = max(DetailView.size.height, Self.maxExpandedHeight) + Self.shadowPad
        return CGSize(width: ceil(w), height: ceil(h))
    }

    /// 把舞台放到刘海正下方居中。只在启动和屏幕变化时调用。
    private func placeStage() {
        guard let s = screen() else { return }
        let g = notchGeometry()
        let size = stageSize()
        let drop: CGFloat = yielding ? g.height + 6 : 0      // 让路：挂到刘海下方
        let rect = NSRect(x: g.midX - size.width / 2, y: s.frame.maxY - drop - size.height,
                          width: size.width, height: size.height)
        if panel.frame != rect { panel.setFrame(rect, display: true) }
    }

    /// 黑色形状此刻在屏幕上的矩形。悬停与点外面的判断用它，不用舞台——舞台比形状大。
    private func shapeScreenRect() -> NSRect {
        guard let s = screen() else { return .zero }
        let g = notchGeometry()
        let drop: CGFloat = yielding ? g.height + 6 : 0
        return NSRect(x: g.midX - state.shapeWidth / 2, y: s.frame.maxY - drop - state.shapeHeight,
                      width: state.shapeWidth, height: state.shapeHeight)
    }

    private enum Motion { case open, close, move, hover }

    /// 形状变到 target。宽、高各自一个动画事务。胶囊另由 updatePill 管。
    private func morph(to target: CGSize, _ motion: Motion, animated: Bool = true) {
        guard animated else {
            state.shapeWidth = target.width
            state.shapeHeight = target.height
            return
        }
        switch motion {
        case .open:
            withAnimation(Self.openWidth) { state.shapeWidth = target.width }
            withAnimation(Self.openHeight) { state.shapeHeight = target.height }
        case .close:
            withAnimation(Self.closeHeight) { state.shapeHeight = target.height }
            withAnimation(Self.closeWidth) { state.shapeWidth = target.width }
        case .move, .hover:
            withAnimation(motion == .hover ? Self.hoverSpring : Self.moveSpring) {
                state.shapeWidth = target.width
                state.shapeHeight = target.height
            }
        }
    }

    /// 胶囊出场：先在岛里就位（不动画），下一拍再弹出来；退场：弹回岛里，停稳后再撤掉。
    /// delay：岛刚开始收起时等它收稳再滴出去，否则胶囊和正在缩小的岛挤在一起。
    private func updatePill(animated: Bool, delay: TimeInterval = 0) {
        let want = pillWidth()
        guard animated else {
            pillEmerge?.cancel(); pillEmerge = nil
            pillRetract?.cancel(); pillRetract = nil
            state.pillWidth = want
            state.pillOut = want > 0 ? 1 : 0
            if want == 0 { state.pillHover = false }
            return
        }
        if want > 0 {
            pillRetract?.cancel(); pillRetract = nil
            if let pending = pillEmerge, !pending.isCancelled { return }   // 已经排着一次出场，别提前
            let go = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pillEmerge = nil
                let w = self.pillWidth()
                guard w > 0 else { return }
                if self.state.pillWidth == 0 || self.state.pillOut < 0.05 {
                    self.state.pillWidth = w
                    self.state.pillOut = 0
                    // 插入与动画分两拍：同一拍里插入的视图没有「旧值」，弹簧不会从 0 起跳。
                    DispatchQueue.main.async {
                        withAnimation(Self.pillOutSpring) { self.state.pillOut = 1 }
                    }
                } else {
                    if self.state.pillWidth != w { self.state.pillWidth = w }
                    if self.state.pillOut < 1 { withAnimation(Self.pillOutSpring) { self.state.pillOut = 1 } }
                }
            }
            pillEmerge = go
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: go)
        } else if state.pillWidth > 0 {
            pillEmerge?.cancel(); pillEmerge = nil
            guard pillRetract == nil else { return }
            withAnimation(Self.pillInSpring) {
                state.pillOut = 0
                state.pillHover = false
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pillRetract = nil
                if self.pillWidth() == 0 { self.state.pillWidth = 0 }
            }
            pillRetract = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    private func layout(animated: Bool) {
        let target = targetShapeSize(expanded: state.expanded)
        if !(animated && state.shapeSize == target) {
            morph(to: target, .move, animated: animated)
        }
        updatePill(animated: animated)
    }

    /// 按内容量出展开高度，上下限兜住极端情况。
    private func expandedHeight() -> CGFloat {
        let g = notchGeometry()
        let probe = NSHostingController(rootView:
            IslandExpandedContent(store: store, seen: seen, pinned: state.pinned,
                                  notchWidth: g.width, notchHeight: g.height)
                .frame(width: Self.expandedWidth))
        let fit = probe.sizeThatFits(in: CGSize(width: Self.expandedWidth, height: 10_000))
        return max(72, min(Self.maxExpandedHeight, ceil(fit.height)))
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
            if !state.expanded, !state.hovering {
                // 先鼓一下：鼠标一进来就有回应，不用干等 0.3 秒。
                withAnimation(Self.hoverSpring) { state.hovering = true }
                morph(to: targetShapeSize(expanded: false), .hover)
            }
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
                guard !self.shapeScreenRect().insetBy(dx: -1, dy: -1).contains(NSEvent.mouseLocation) else { return }
                if self.state.expanded {
                    self.setExpanded(false, reason: "hover-out")
                } else if self.state.hovering {
                    withAnimation(Self.hoverSpring) { self.state.hovering = false }
                    self.morph(to: self.targetShapeSize(expanded: false), .hover)
                }
            }
        }
    }

    /// 鼠标停在胶囊上：胶囊向右长出，预览那个会话的标签。
    private func pillHover(_ inside: Bool) {
        if PresentDemo.seconds != nil && !PresentDemo.passive { demoLog("ignored pill hover inside=\(inside)"); return }
        guard state.pillWidth > 0, !state.expanded, !state.detail else { return }
        withAnimation(Self.pillHoverSpring) { state.pillHover = inside }
    }

    /// 声明到达：没在展示别的就展开 6 秒；正在展示另一个会话就排队，不顶掉你读到一半的那个。
    private func arrive(_ id: String, reason: String) {
        if PresentDemo.seconds != nil && !PresentDemo.passive { demoLog("ignored \(reason)"); return }
        if state.detail { return }
        let showing = state.expanded ? state.pinned : nil
        // 正在展示的就是这个会话（例如声明之后又弹出选择题）：当场刷新、重置计时，不走排队。
        if showing == id {
            demoLog("refresh \(id.prefix(8)) reason=\(reason)")
            flash(pinning: id, reason: reason)
            return
        }
        if arrivals.offer(id, showing: showing) {
            flash(pinning: id, reason: reason)
        } else {
            demoLog("queued \(id.prefix(8)) behind \(showing.map { String($0.prefix(8)) } ?? "-")")
            layout(animated: true)
        }
    }

    /// 静止展开 6 秒。不算已读 —— 面板在屏幕顶上出现，不是任何人看过的证据。
    private func flash(pinning id: String, reason: String = "declaration-arrived") {
        if state.detail { return }
        state.pinned = id
        if state.expanded {
            morph(to: targetShapeSize(expanded: true), .move)
        } else {
            setExpanded(true, reason: reason)
        }
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.shapeScreenRect().contains(NSEvent.mouseLocation) { self.setExpanded(false, reason: "flash-timeout") }
            }
        }
    }

    /// 底部那一行或胶囊：切到那个会话并展开。这是你主动点的，算看过。
    private func switchTo(_ id: String) {
        guard let s = store.sessions.first(where: { $0.id == id }) else { return }
        demoLog("switch \(id.prefix(8))")
        autoCollapse?.invalidate(); autoCollapse = nil
        seen.markSeen(s)
        if state.expanded {
            withAnimation(Self.moveSpring) { state.pinned = id }
            morph(to: targetShapeSize(expanded: true), .move)
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
        withAnimation(on ? Self.openWidth : Self.closeHeight) {
            state.expanded = on
            state.hovering = false
        }
        morph(to: targetShapeSize(expanded: on), on ? .open : .close)
        // 展开时胶囊立刻吸回岛里；收起时等岛收稳（约 0.3 秒）再滴出去。
        updatePill(animated: true, delay: on ? 0 : 0.3)
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
        withAnimation(Self.openWidth) {
            state.detail = true
            state.expanded = true
            state.hovering = false
        }
        morph(to: DetailView.size, .open)
        updatePill(animated: true)
        installOutsideMonitor()
    }

    func closeDetail() {
        guard state.detail else { return }
        removeOutsideMonitor()
        demoLog("detail=false")
        withAnimation(Self.closeHeight) { state.detail = false; state.expanded = false }
        morph(to: targetShapeSize(expanded: false), .close)
        updatePill(animated: true, delay: 0.3)
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

    /// 演示用：收起（胶囊随后滴出去）。
    func presentCollapse() { setExpanded(false, reason: "present") }

    /// 演示用：模拟鼠标停在胶囊上 / 离开。
    func presentPillHover(_ on: Bool) {
        guard state.pillWidth > 0 else { demoLog("pill hover skipped: no pill"); return }
        demoLog("pill hover=\(on)")
        withAnimation(Self.pillHoverSpring) { state.pillHover = on }
    }

    /// 演示用：模拟悬停鼓起 / 复原（不展开）。
    func presentHoverBump(_ on: Bool) {
        demoLog("hover bump=\(on)")
        withAnimation(Self.hoverSpring) { state.hovering = on }
        morph(to: targetShapeSize(expanded: false), .hover)
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
