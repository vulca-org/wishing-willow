import AppKit
import SwiftUI

@MainActor
@Observable
final class IslandState {
    var expanded = false
    /// 黑色形状此刻的宽和高（含两侧凹肩）。分开存，各走各的弹簧：展开时宽先长、高后长，
    /// 读起来是从刘海往两边、再往下；收起反过来。窗口本身是固定大小的透明舞台。
    var shapeWidth: CGFloat = 0
    var shapeHeight: CGFloat = 0
    var shapeSize: CGSize { CGSize(width: shapeWidth, height: shapeHeight) }
    /// 点击后的面板态：灵动岛再长大一档。
    var detail = false
    /// 声明到达、悬停或切换时的那个会话，展开期间钉住。
    var pinned: String?
    /// 第二个会话的分离胶囊宽度；0 = 不显示。
    var pillWidth: CGFloat = 0
    /// 胶囊离岛的程度：0 = 收在岛里，1 = 停在右侧。出场与收回都走这个值，中间有一段液体连桥。
    var pillOut: CGFloat = 0
    /// 展开（或打开面板）开始那一刻的岛宽。胶囊并入面板时按它定位，不跟着正在变宽的岛往外走。
    var pillAnchorWidth: CGFloat = 0
    /// 鼠标停在胶囊上：胶囊向右长出一段，预览那个会话在做什么。
    var pillHover = false
    /// 鼠标刚进灵动岛、还没到展开的 0.3 秒：岛先微微鼓一下，让人知道它接到了。
    var hovering = false
    /// 给菜单栏让路时往下挪的距离；0 = 贴着刘海。让路时正好是菜单栏的高度：主体顶边贴住菜单栏底边，严丝合缝。
    var dodge: CGFloat = 0
    /// 让到底是多少（开始让路时定下的菜单栏高度）。形状按 dodge / dodgeDepth 从凹肩变成挂在刘海下的胶囊。
    var dodgeDepth: CGFloat = 0
    /// 让路时两端顶角的形态：0 = 凹肩，1 = 全圆。和 dodge 分开排时序（见 NotchShape.capsule）。
    var dodgeCorner: CGFloat = 0
    /// 点开面板那一刻灵动岛上显示的会话。打开面板会把全部会话标成已读，标完再算「主会话」就换人了。
    var detailFocus: String?
}

/// 灵动岛本体：纯黑、顶边贴着屏幕上沿、顶部两角凹肩、下方两角圆，和刘海连成一块。
///
/// 不用玻璃。浅色半透明的 Liquid Glass 放在这里，读起来是一个悬浮窗，
/// 不是刘海长出来的东西 —— 这是用真实截图对照之后改的，不是凭审美。
///
/// 并行会话按 Apple HIG 的多活动做法：主会话贴着摄像头占两翼，第二个会话分离成右侧的小胶囊。
struct IslandView: View {
    let store: WillowStore
    let seen: SeenStore
    let state: IslandState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// 让路时连着物理刘海的那截颈宽；没有物理刘海、或挂在刘海下方让路时为 0（见 NotchShape）。
    let stemWidth: CGFloat
    let onHover: (Bool) -> Void
    let onPillHover: (Bool) -> Void
    let onClick: () -> Void
    let onClose: () -> Void
    let onSwitch: (String) -> Void

    private var open: Bool { state.expanded || state.detail }
    private var radii: (top: CGFloat, bottom: CGFloat) { open ? NotchShape.open : NotchShape.closed }

    /// 内容退场一律快速淡出：先让字消失，形状再变。
    private static let quickOut = AnyTransition.asymmetric(
        insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.1)))

    var body: some View {
        let pair = FocusRule.pair(store, seen, pinned: state.pinned)
        let label = pair.primary.flatMap { FocusRule.label($0, seen, store) }
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom,
                               drop: state.dodge, dropDepth: state.dodgeDepth, capsule: state.dodgeCorner, stemWidth: stemWidth)
        // 接鼠标只认主体、不认颈：让路时鼠标横穿刘海底下去点另一侧的菜单，不该算悬停。
        let hitShape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            // 胶囊画在岛的下面：收回时藏进岛里，出场时从岛的右缘滴出去。
            if state.pillWidth > 0, let other = pair.secondary, let pill = FocusRule.pill(other, seen, store) {
                let par = FocusRule.parallel(store)
                PillAssembly(islandWidth: state.shapeWidth, anchorWidth: open ? state.pillAnchorWidth : nil, liquid: !open,
                             pillOut: state.pillOut,
                             pillExtra: state.pillHover ? IslandController.pillPreview : 0,
                             pillWidth: state.pillWidth, notchHeight: notchHeight,
                             bottomRadius: NotchShape.closed.bottom, lift: state.dodge, liftDepth: state.dodgeDepth,
                             onTap: { onSwitch(other.id) }, onHover: onPillHover) {
                    SessionPill(pill: pill,
                                preview: state.pillHover
                                    ? (store.progress(for: other)?.tag ?? other.tag ?? FocusRule.lastLoggedTag(other, store) ?? other.workspace)
                                      + L(" · \(par.running) 个在跑", " · \(par.running) running")
                                    : nil)
                }
            }

            ZStack(alignment: .top) {
                // 缩回刘海时不能画成全透明：窗口里 alpha 为 0 的像素，鼠标事件直接穿过窗口，悬停永远到不了这里。
                // 2% 的黑盖在物理刘海上看不见，但足够让窗口接住鼠标。悬停鼓起时画实。
                shape.fill(Color.black.opacity(open || label != nil || state.hovering ? 1 : 0.02))

                if state.detail {
                    DetailView(store: store, seen: seen, notchWidth: notchWidth, notchHeight: notchHeight, onClose: onClose,
                               focus: state.detailFocus)
                        .frame(width: DetailView.size.width - 2 * NotchShape.open.top,
                               height: DetailView.size.height, alignment: .top)
                        .transition(Self.quickOut)
                } else if state.expanded {
                    // 内容按完整高度排版，形状长大时被裁切着逐渐露出——不在长大途中被压扁、重排。
                    IslandExpandedContent(store: store, seen: seen, pinned: state.pinned,
                                          notchWidth: notchWidth, notchHeight: notchHeight, onSwitch: onSwitch)
                        .frame(width: IslandController.expandedWidth, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(Self.quickOut)
                } else if let f = pair.primary, let l = label {
                    CompactWings(store: store, seen: seen, session: f, label: l,
                                 notchWidth: notchWidth, height: notchHeight)
                        .padding(.horizontal, NotchShape.closed.top)
                        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.1)),
                                                removal: .opacity.animation(.easeOut(duration: 0.1))))
                }
            }
            .frame(width: state.shapeWidth, height: state.shapeHeight, alignment: .top)
            .clipShape(shape)
            // 暗色背景上的一条细边：HIG 的 key line，黑岛压在深色壁纸上时靠它分出边界。
            .overlay { if open { shape.stroke(Color.white.opacity(0.08), lineWidth: 1) } }
            .shadow(color: .black.opacity(open ? 0.55 : 0), radius: 10, y: 4)
            // 悬停与点击只挂在形状上：舞台比形状大，那片透明边缘不该触发任何事。
            .contentShape(hitShape)
            .onHover(perform: onHover)
            .onTapGesture { if !state.detail { onClick() } }   // 面板里的点击交给面板自己
        }
        // 菜单栏滑出来时整体往下让（见 DodgeRule）。偏移在舞台里做，不挪窗口：窗口改位置那一帧会跳。
        .offset(y: state.dodge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// 第二个会话的胶囊，连同它从岛里分离出来的那一段液体连桥。
///
/// Apple 的灵动岛在第二个活动出现时，胶囊是从主岛上「滴」出去的：两块黑色之间先拉出一段细颈再断开。
/// 做法是「模糊 + 按不透明度截断」：把岛身和胶囊画在同一层，先模糊、再按 50% 不透明度截断，
/// 靠得近的两块形状在截断后连成一体。只在分离途中画这一层——停稳后 6pt 的缝不该有连桥。
/// 这个视图遵循 Animatable：弹簧的每一帧都重新算胶囊位置与连桥，而不是只插值最终布局。
// SwiftUI 只在主线程读写 animatableData；Swift 6 要求把这一点写明。
struct PillAssembly<Content: View>: View, @preconcurrency Animatable {
    var islandWidth: CGFloat
    /// 岛正在展开时给定：胶囊按展开前的岛宽定位、原地滑进面板底下。
    /// 先前跟着正在变宽的岛算位置，胶囊被一路往外推，在面板右上角鼓出一块（2026-09-13 逐帧：展开第一帧右缘 +148 px、连续 5 帧左右不对称）。
    let anchorWidth: CGFloat?
    /// 只有收起态之间的分离与收回画液体连桥。并入展开面板时不画：连桥层画的是收起态的岛身，
    /// 和正在长大的面板对不上，它消失那一帧两侧各缩进 23 px。
    let liquid: Bool
    var pillOut: CGFloat
    var pillExtra: CGFloat
    let pillWidth: CGFloat
    let notchHeight: CGFloat
    let bottomRadius: CGFloat
    /// 岛此刻给菜单栏让了多少。连桥层的岛身平时往上伸出画布（免得模糊吃掉顶边）；让路时整层跟着下移，
    /// 再往上伸就是一条黑带盖在菜单栏上，所以让多少就少伸多少。
    /// 让路时胶囊也跟着长到主体那么高、顶边贴住菜单栏，所以 lift 要逐帧插值。
    var lift: CGFloat
    let liftDepth: CGFloat
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    let content: () -> Content

    init(islandWidth: CGFloat, anchorWidth: CGFloat? = nil, liquid: Bool = true, pillOut: CGFloat, pillExtra: CGFloat, pillWidth: CGFloat, notchHeight: CGFloat,
         bottomRadius: CGFloat, lift: CGFloat = 0, liftDepth: CGFloat = 0, onTap: @escaping () -> Void, onHover: @escaping (Bool) -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.lift = lift
        self.liftDepth = liftDepth
        self.islandWidth = islandWidth
        self.anchorWidth = anchorWidth
        self.liquid = liquid
        self.pillOut = pillOut
        self.pillExtra = pillExtra
        self.pillWidth = pillWidth
        self.notchHeight = notchHeight
        self.bottomRadius = bottomRadius
        self.onTap = onTap
        self.onHover = onHover
        self.content = content
    }

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(islandWidth, .init(pillOut, .init(pillExtra, lift))) }
        set {
            islandWidth = newValue.first
            pillOut = newValue.second.first
            pillExtra = newValue.second.second.first
            lift = newValue.second.second.second
        }
    }

    var body: some View {
        GeometryReader { g in
            let w = pillWidth + pillExtra
            let h = IslandController.dodgedPillHeight(dodge: lift, depth: liftDepth, notchHeight: notchHeight)
            let mid = g.size.width / 2
            let base = anchorWidth ?? islandWidth
            let tucked = base / 2 - w / 2 - 8
            let rest = base / 2 + IslandController.pillGap + w / 2
            let cx = mid + tucked + (rest - tucked) * pillOut
            let cy = notchHeight / 2
            ZStack(alignment: .topLeading) {
                if liquid && pillOut > 0.02 && pillOut < 0.97 {
                    Canvas { ctx, size in
                        ctx.addFilter(.alphaThreshold(min: 0.5, color: .black))
                        ctx.addFilter(.blur(radius: 4))
                        ctx.drawLayer { layer in
                            // 岛身：去掉两侧凹肩，顶边伸出画布之外（免得模糊把顶边吃掉），底角与真实形状同半径。
                            let reach = max(0, 24 - lift)
                            let body = CGRect(x: mid - islandWidth / 2 + NotchShape.closed.top, y: -reach,
                                              width: max(0, islandWidth - 2 * NotchShape.closed.top), height: notchHeight + reach)
                            layer.fill(Path(roundedRect: body, cornerRadius: bottomRadius, style: .continuous), with: .color(.black))
                            layer.fill(Path(roundedRect: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h),
                                            cornerRadius: h / 2, style: .continuous), with: .color(.black))
                        }
                    }
                    .allowsHitTesting(false)
                }
                // 先前在胶囊后面叠 1–2 层表示还有会话，用户看到的是「重叠」；会话数改由左翼四点表示。
                content()
                    // 并入面板时字一开始收就淡掉：先前字跟着胶囊滑进岛里，叠在岛的右缘上。
                    .opacity(Double(max(0, min(1, liquid ? (pillOut - 0.45) / 0.4 : (pillOut - 0.8) / 0.2))))
                    .frame(width: w, height: h)
                    .background(Capsule().fill(Color.black))
                    .contentShape(Capsule())
                    .onTapGesture(perform: onTap)
                    .onHover(perform: onHover)
                    .position(x: cx, y: cy)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}

// MARK: 收起

/// 两翼读作一条信息（HIG）：左翼状态贴着摄像头，右翼标签贴着摄像头。
struct CompactWings: View {
    let store: WillowStore
    let seen: SeenStore
    let session: SessionState
    let label: FocusRule.Label
    let notchWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // 两翼内容都在各自翼内居中：先前左翼「图标 + 计时」贴着摄像头、右翼一行字，用户看着左重右轻（2026-09-13）。
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                DemoMark(compact: true)
                WingStatus(store: store, seen: seen, session: session, size: 18)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)          // 摄像头那一块，画了也看不见

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(label.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(session.declaration == .unreadable ? Color.red
                                     : Color.white.opacity(label.carried ? 0.55 : 1))
                    .lineLimit(1)
                    .id(label.text)
                    // 换标签时旧字往上退、新字从下面升上来——竖向，和展开的方向一致。
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .move(edge: .top).combined(with: .opacity)))
                Spacer(minLength: 0)
            }
            // 与左翼同样的内边距并居中。6 个汉字在 12pt semibold 约 72pt，翼宽 92 − 12 = 80，放得下。
            .padding(.leading, 6)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: label.text)
    }
}

/// 左翼与展开态左耳：iPhone Duo 式的合一状态图标 + 一个真在走的数（计时，或结束了多久）。
/// 图标先前放在展开态右上角，用户指出位置应在折叠态左翼（2026-09-13）。
struct WingStatus: View {
    let store: WillowStore
    let seen: SeenStore
    let session: SessionState
    var size: CGFloat = 18

    var body: some View {
        let s = session
        let p = store.progress(for: s)
        let withdraw = store.recentWithdraw[s.id]
        let snapshot = ClaudeStatus.snapshot(store.timeline(for: s)?.progress, settingsModel: store.settingsModel)
        HStack(spacing: 5) {
            DuoGlyph(snapshot: snapshot, center: StatusCenter.of(s, progress: p, withdrawn: withdraw != nil),
                     sessions: FocusRule.parallel(store).running, size: size)
                .symbolEffect(.bounce, value: withdraw?.at)
            if let w = withdraw, w.kind == .interrupted, let start = s.record.updatedAt, let end = p?.interruptedAt {
                // 打断：计时停在撤回那一刻并划掉。
                Text(Clock.text(end.timeIntervalSince(start)))
                    .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.45))
                    .strikethrough(true, color: Color.white.opacity(0.5))
            } else if let c = p?.pendingChoice {
                // 等你选：计时从提问那一刻算——这是它等了你多久。
                LiveClock(since: c.at ?? s.record.updatedAt ?? .now, size: 12, opacity: 0.8)
            } else if s.declaration == .inProgress, let start = s.record.updatedAt {
                LiveClock(since: start, size: 12, opacity: 0.7)
            } else if s.declaration != .unreadable, let end = s.record.turnEndedAt ?? s.record.updatedAt {
                // 结束了的一轮：结束了多久。旧记录没有 turnEndedAt，退回 updatedAt（提取时与结束时刻同时写下）。
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(Clock.ago(end, now: ctx.date))
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.white.opacity(seen.isUnread(s) ? 0.7 : 0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: StatusCenter.of(s, progress: p, withdrawn: withdraw != nil))
    }
}

/// 第二个会话的分离胶囊。平时只放一个符号加两三个字；鼠标停上去时向右长出，预览那个会话的标签。
struct SessionPill: View {
    let pill: FocusRule.Pill
    var preview: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            switch pill {
            case .broken:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
            case .choice(let plan, let since):
                Image(systemName: plan ? "checklist" : "questionmark.bubble.fill").foregroundStyle(ChoiceCard.accent)
                if let since { LiveClock(since: since, opacity: 0.9) }
            case .withdraw:
                Image(systemName: "arrow.uturn.backward")
            case .running(let since):
                Image(systemName: "ellipsis").symbolEffect(.pulse, options: .repeating)
                if let since { LiveClock(since: since, opacity: 0.9) }
            case .fresh(_, let flagged):
                Circle().fill(flagged ? Color.orange : Color.white).frame(width: 6, height: 6)
            case .silent:
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            if let title = Self.title(pill) { Text(title) }
            if let preview {
                Text(preview)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
                    // 等胶囊先长出来再出字：同时出现时中间帧挤成「没写ledger」（2026-09-13 帧对照）。
                    .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.18).delay(0.14)),
                                            removal: .opacity.animation(.easeOut(duration: 0.08))))
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 9)
    }

    /// 胶囊里写的字；在跑、等你选且知道起点时写计时，返回 nil。
    static func title(_ pill: FocusRule.Pill) -> String? {
        switch pill {
        case .broken: L("读不到", "Can’t read")
        case .choice(let plan, let since): since == nil ? (plan ? L("等批准", "Approve") : L("等你选", "Your turn")) : nil
        case .withdraw: L("撤回", "Withdrawn")
        case .running(let since): since == nil ? L("回答中", "Answering") : nil
        case .fresh: L("新声明", "New reading")
        case .silent: L("没写", "No reading")
        }
    }

    /// 胶囊宽度按字量算：中文三个字 76 放得下，英文「New reading」放不下——2026-09-13 截图里截成了「New rea…」。
    /// 图标约 14、间距 5、左右内边距各 9，再留 4 的余量。计时（「12:34」）76 放得下。
    static func width(_ pill: FocusRule.Pill) -> CGFloat {
        guard let t = title(pill) else { return 76 }
        let text = (t as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        return max(76, ceil(text) + 14 + 5 + 18 + 4)
    }
}

// MARK: 展开

/// 展开态的内容，单独成一个视图：控制器要先量出它的真实高度再定形状大小。
///
/// Apple 的排法：刘海两侧的耳朵放收起态的同一组信息（左耳是合一状态图标与计时）；
/// 下面三块依次是「你的要求 / Claude 的理解 / Claude 在做」，每块左边标题、右边一个可以核对的数；
/// 进度是一根分段胶囊；底部一条数据条。所有正文左缘在同一条对齐线上（x = 16）。
/// 称谓按用户要求改过：先前的「你批准的 / 我读成了」里的「我」指模型，放在一个第三方看板上读着别扭。
struct IslandExpandedContent: View {
    let store: WillowStore
    let seen: SeenStore
    var pinned: String? = nil
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    var onSwitch: ((String) -> Void)? = nil

    @State private var shown = Offscreen.isRendering

    var body: some View {
        let pair = FocusRule.pair(store, seen, pinned: pinned)
        VStack(alignment: .leading, spacing: 0) {
            ears(pair.primary).reveal(0, shown)
            if let s = pair.primary {
                let tl = store.timeline(for: s)
                VStack(alignment: .leading, spacing: 12) {
                    request(s, tl).reveal(1, shown)
                    reading(s, tl).reveal(2, shown)
                    if let tl { working(tl, asked: s.record.reminded != false).reveal(3, shown) }
                    stats(s, tl).reveal(4, shown)
                    if let other = FocusRule.flipTarget(store, after: s) {
                        otherRow(s, other, FocusRule.pill(other, seen, store)).reveal(5, shown)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            } else {
                Text(L("没有活动的会话", "No active sessions"))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
                    .padding(16)
                    .reveal(1, shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { DispatchQueue.main.async { shown = true } }
    }

    // 刘海两侧：左耳 = 工作区 … 合一状态图标与计时（贴摄像头，与折叠态左翼同一相对位置），右耳 = 标签（贴摄像头）… 阶段。
    private func ears(_ s: SessionState?) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let s {
                    DemoMark()
                    Text(s.workspace)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    WingStatus(store: store, seen: seen, session: s, size: 20)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                if let s {
                    let tag = Self.earTag(s, store: store, seen: seen)
                    // 标签先占位、放不下时缩到 0.8 再截断；阶段词保持原宽。英文标签（插件允许 ≤14 字符）先前被阶段词挤成「Fix upload t…」。
                    Text(tag.text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(s.flaggedByModel ? Color.orange : (tag.carried ? Ink.tertiary : Ink.primary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(Self.phaseWord(s, store: store))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 10).padding(.trailing, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    /// 标签位只放「这一轮在做什么」。「思考中 / 回答中 / 等你选择」这类状态词在右边的阶段位上。
    /// 先前没有标签时退回 FocusRule.label（它在进行中返回的正是状态词），于是「思考中」写了两遍（用户 2026-09-13 悬停时看到）。
    /// 进行中还没写出标签：用上一轮的标签并调暗，标明是沿用的。
    static func earTag(_ s: SessionState, store: WillowStore, seen: SeenStore) -> (text: String, carried: Bool) {
        let p = store.progress(for: s)
        if let t = p?.tag ?? s.tag { return (t, false) }
        if s.declaration == .inProgress || s.declaration == .interrupted || p?.pendingChoice != nil {
            return (FocusRule.lastLoggedTag(s, store) ?? L("还没有标签", "No tag yet"), true)
        }
        if let l = FocusRule.label(s, seen, store), l.text != phaseWord(s, store: store) { return (l.text, l.carried) }
        return (FocusRule.lastLoggedTag(s, store) ?? L("还没有标签", "No tag yet"), true)
    }

    static func phaseWord(_ s: SessionState, store: WillowStore) -> String {
        if store.recentWithdraw[s.id] != nil { return L("撤回", "Withdrawn") }
        switch s.declaration {
        case .unreadable: return L("插件读不到", "Plugin can’t read")
        case .interrupted: return L("被打断", "Interrupted")
        case .awaiting: return L("等待开始", "Waiting to start")
        case .inProgress:
            guard let p = store.progress(for: s) else { return L("回答中", "Answering") }
            if let c = p.pendingChoice { return c.kind == .plan ? L("等你批准", "Awaiting approval") : L("等你选择", "Your turn") }
            if p.decode != nil { return L("实时", "Live") }
            return p.firstWriteAt == nil ? L("思考中", "Thinking") : L("回答中", "Answering")
        case .declared, .undeclared, .notAsked, .unverifiable: return L("已结束", "Ended")
        }
    }

    // MARK: 你的要求

    private func request(_ s: SessionState, _ tl: TurnTimeline?) -> some View {
        let system = s.record.isSystemMessage
        let start = tl?.startedAt ?? (s.declaration == .inProgress ? s.record.updatedAt : nil)
        let value = [start.map(Self.clock), system ? nil : s.prompt.map { L("\($0.count) 字", "\($0.count) chars") }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: system ? L("这一轮", "This turn") : L("你的要求", "Your request"), value: value.isEmpty ? nil : value)
            // 不是人说的话，不能挂在「你的要求」下面。
            para(system ? L("系统消息（\(PromptSource.describe(s.prompt))），不是你说的", "System message (\(PromptSource.describe(s.prompt))) — not from you") : (s.prompt.map(Self.oneLine) ?? "—"),
                 system ? Ink.secondary : Ink.primary)
        }
    }

    // MARK: Claude 的理解

    /// 「没问」「问了没答」「插件坏了」必须是三句不同的话。
    @ViewBuilder
    private func reading(_ s: SessionState, _ tl: TurnTimeline?) -> some View {
        let p = store.progress(for: s)
        VStack(alignment: .leading, spacing: 4) {
            switch s.declaration {
            case .declared(let d):
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: declaredNote(s, tl),
                              valueTint: s.flaggedByModel ? .orange : Ink.tertiary)
                para(d, s.flaggedByModel ? .orange : Ink.primary)
            case .undeclared:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("已结束 · 没有写", "Ended · none written"), valueTint: .orange)
                para(L("问了，Claude 没写理解", "Asked, but Claude wrote no reading"), .orange)
            case .unverifiable:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("中途追加 · 无法核对", "Sent mid-turn · can’t verify"))
                para(L("这条是 Claude 干活时追加的。之后写的理解不会存进聊天记录，这一轮核对不了——不代表没写。",
                       "You sent this while Claude was working. A reading written after it isn’t saved to the transcript, so this turn can’t be checked — that doesn’t mean none was written."),
                     Ink.tertiary)
            case .unreadable:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("插件读不到输入", "Plugin can’t read the input"), valueTint: .red)
                para(L("读不到本轮输入 —— 插件坏了，不是 Claude 没说话", "Can’t read this turn’s input — the plugin is broken, Claude isn’t silent"), .red)
            case .awaiting:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("等待开始", "Waiting to start"))
                para(L("等这一轮开始", "Waiting for this turn to start"), Ink.tertiary)
            case .notAsked:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("这一轮没问", "Not asked this turn"))
                para(L("这一轮没问（太短或是系统消息）", "Not asked (too short, or a system message)"), Ink.tertiary)
            case .interrupted:
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: offsetNote(p?.interruptedAt, tl).map { L("撤回于 ", "Withdrawn at ") + $0 })
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                    Text(L("你撤回了这一轮", "You withdrew this turn")).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Ink.primary)
                }
                if let d = p?.decode { para(L("撤回前的理解：", "Reading before you withdrew: ") + d, Ink.tertiary) }
            case .inProgress where s.record.reminded == false:
                // 在跑但这一轮没问：不会写理解，不能挂「还没写出」。
                SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("这一轮没问", "Not asked this turn"))
                para(L("这一轮没问（太短或是系统消息）", "Not asked (too short, or a system message)"), Ink.tertiary)
            case .inProgress:
                if let d = p?.decode {
                    SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: offsetNote(p?.declaredAt, tl).map { $0 + L(" 写出", " written") },
                                  badge: L("实时", "Live"))
                    para(d, d.hasPrefix("⚠") ? .orange : Ink.primary)
                        .transition(.opacity)
                } else {
                    SectionHeader(title: L("Claude 的理解", "Claude’s reading"), value: L("还没写出", "Not written yet"))
                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Ink.secondary)
                            .symbolEffect(.pulse, options: .repeating)
                        Text(Self.phase(p)).font(.system(size: 13)).foregroundStyle(Ink.secondary)
                        Spacer(minLength: 0)
                        if let start = s.record.updatedAt { LiveClock(since: start, size: 11.5, opacity: 0.5) }
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: p?.decode)
    }

    private func declaredNote(_ s: SessionState, _ tl: TurnTimeline?) -> String {
        var parts: [String] = []
        if let at = offsetNote(tl?.progress.declaredAt, tl) { parts.append(at + L(" 写出", " written")) }
        parts.append(s.flaggedByModel ? L("⚠ Claude 自标不一致", "⚠ Claude flagged a mismatch") : L("已结束", "Ended"))
        return parts.joined(separator: " · ")
    }

    private func offsetNote(_ d: Date?, _ tl: TurnTimeline?) -> String? {
        guard let d, let start = tl?.startedAt else { return nil }
        return "+" + Clock.text(d.timeIntervalSince(start))
    }

    // MARK: Claude 在做

    private func working(_ tl: TurnTimeline, asked: Bool) -> some View {
        let p = tl.progress
        let live = tl.endedAt == nil && p.interruptedAt == nil
        var value = [L("\(p.steps.count) 步", "\(p.steps.count) steps")]
        if let first = p.firstWriteAt { value.append(L("首次落盘 +", "first write +") + Clock.text(first.timeIntervalSince(tl.startedAt))) }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: live ? L("Claude 在做", "Claude is working") : L("Claude 做了", "What Claude did"), value: value.joined(separator: " · "))
            if live, let c = p.pendingChoice {
                ChoiceCard(choice: c).transition(.opacity)
            }
            TurnBar(timeline: tl, asked: asked)
            if !(live && p.pendingChoice != nil), !p.steps.isEmpty {
                StepList(timeline: tl, limit: 2)
            }
        }
        .animation(.snappy(duration: 0.3), value: p.pendingChoice)
        .animation(.easeOut(duration: 0.25), value: p.steps.count)
    }

    // MARK: 数据条

    private func stats(_ s: SessionState, _ tl: TurnTimeline?) -> some View {
        let status = ClaudeStatus.snapshot(tl?.progress, settingsModel: store.settingsModel)
        let log = TurnLog.read(sessionId: s.id, directory: store.directory)
        let asked = log.filter { $0.reminded == true && $0.interrupted != true }
        let wrote = asked.filter(\.declared).count
        return HStack(spacing: 0) {
            StatCell(label: status.map { L("上下文 · \(ClaudeStatus.compact($0.window)) 窗口", "Context · \(ClaudeStatus.compact($0.window))") } ?? L("上下文", "Context"),
                     value: status.map { "\(ClaudeStatus.compact($0.contextUsed)) · \(Self.percent($0.usedFraction))" } ?? "—",
                     tint: status.map { DuoGlyph.ringColor($0.remaining) } ?? Ink.tertiary)
            StatDivider()
            StatCell(label: L("缓存命中", "Cache hits"), value: status.map { Self.percent($0.cacheHit) } ?? "—")
            StatDivider()
            StatCell(label: L("本轮输出", "Output this turn"), value: status.map { ClaudeStatus.compact($0.outputTokens) } ?? "—")
            StatDivider()
            StatCell(label: L("写了理解", "Readings written"), value: asked.isEmpty ? "—" : L("\(wrote)/\(asked.count) 轮", "\(wrote)/\(asked.count) turns"))
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.fill))
    }

    private func otherRow(_ s: SessionState, _ other: SessionState, _ pill: FocusRule.Pill?) -> some View {
        Button { onSwitch?(other.id) } label: {
            HStack(spacing: 10) {
                if let pill {
                    SessionPill(pill: pill)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                } else {
                    // 看过且没在答的会话在收起态不占胶囊：照胶囊的样子画（灰点 + 阶段词，同字号同内边距）。
                    // 先前是一段细字，和别的会话翻到这里时的胶囊摆在一起像两套 UI（2026-09-13 实拍）。
                    HStack(spacing: 5) {
                        Circle().fill(Color.white.opacity(0.35)).frame(width: 6, height: 6)
                        Text(Self.phaseWord(other, store: store))
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.progress(for: other)?.tag ?? other.tag ?? FocusRule.lastLoggedTag(other, store) ?? L("还没有标签", "No tag yet"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Text(other.workspace)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Ink.tertiary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 6)
                // 说总数，不说「另有 N 个」：3 个并行时那句话写的是「另有 1 个」，读起来像一共只多一个。
                let par = FocusRule.parallel(store)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(L("\(par.running) 个在跑", "\(par.running) running")).font(Ink.number(10.5, .medium)).foregroundStyle(Ink.secondary)
                    if par.idle > 0 {
                        Text(L("\(par.idle) 个空闲", "\(par.idle) idle")).font(Ink.number(10)).foregroundStyle(Ink.tertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.fill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 小件

    /// 只放两行的原话：换行压成空格。带换行的要求先前第一行后面空一行、正文被挤掉（2026-09-13 实拍）。
    static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s*\\n+\\s*", with: " ", options: .regularExpression)
    }

    private func para(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func phase(_ p: TurnProgress?) -> String {
        guard let p else { return L("Claude 正在回答", "Claude is answering") }
        if p.firstWriteAt == nil { return L("思考中", "Thinking") }
        return p.steps.isEmpty ? L("开始回答，还没写出理解", "Started answering, no reading yet") : L("在执行，还没写出理解", "Working, no reading yet")
    }

    static func clock(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    static func percent(_ f: Double) -> String { "\(Int((f * 100).rounded()))%" }
}

/// 最近几步：左边工具符号，中间在做什么，右边距按回车多久。最新一步亮，其余暗。
struct StepList: View {
    let timeline: TurnTimeline
    var limit = 2

    var body: some View {
        let steps = timeline.progress.steps
        let recent = Array(steps.suffix(limit))
        let first = steps.count - recent.count
        let live = timeline.endedAt == nil && timeline.progress.interruptedAt == nil
        VStack(alignment: .leading, spacing: 4) {
            // 每一步用它在整轮步骤数组里的下标当身份（步骤只追加、不删）。
            // 先前用可见行号：新步骤到达时同一行的文字原地交叉淡变，录屏里「Find retry」和「Run upload tests」叠在一起（2026-09-13 动图帧对照）。
            ForEach(first..<steps.count, id: \.self) { k in
                let st = steps[k]
                let current = live && k == steps.count - 1
                HStack(spacing: 8) {
                    Image(systemName: ToolSymbol.name(st.tool))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(current ? Ink.primary : Ink.tertiary)
                        .frame(width: 14)
                        .symbolEffect(.pulse, options: .repeating, isActive: current)
                    Text(st.text)
                        .font(.system(size: 12))
                        .foregroundStyle(current ? Ink.primary : Ink.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if let at = st.at {
                        Text("+" + Clock.text(at.timeIntervalSince(timeline.startedAt)))
                            .font(Ink.number(10.5))
                            .foregroundStyle(Ink.tertiary)
                    }
                }
                // 旧行直接消失、下面的行上移、新行随后淡入：任何一帧里两行字都不会叠在同一个位置。
                .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)), removal: .identity))
            }
        }
    }
}

enum Clock {
    static func text(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// 两翼用的短写法：刚刚 / 12 分 / 3 时。
    static func ago(_ d: Date, now: Date = Date()) -> String {
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return L("刚刚", "now") }
        if s < 3600 { return L("\(s / 60) 分", "\(s / 60)m") }
        return L("\(s / 3600) 时", "\(s / 3600)h")
    }
}

/// 每秒走一格的计时。数字换的时候滚动过去（HIG：数字内容用数字过渡），不是整块闪一下。
struct LiveClock: View {
    let since: Date
    var size: CGFloat = 11
    var opacity: Double = 0.6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let t = Clock.text(ctx.date.timeIntervalSince(since))
            Text(t)
                .font(.system(size: size, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.white.opacity(opacity))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: t)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Claude 在等你选：题面与选项。灵动岛没法往 Claude Code 里输入，不替你选，只负责把你叫回去。
/// 颜色另起一个蓝：橙色是「读偏了」、红色是「插件坏了」，而「轮到你了」不是任何一种错误。
struct ChoiceCard: View {
    let choice: TurnProgress.Choice
    static let accent = Color(red: 0.45, green: 0.78, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: choice.kind == .plan ? "checklist" : "questionmark.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text(choice.kind == .plan ? L("Claude 在等你批准计划", "Claude is waiting for plan approval") : L("Claude 在等你选择", "Claude is waiting for your choice"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                if choice.count > 1 {
                    Text(L("共 \(choice.count) 题", "\(choice.count) questions")).font(.system(size: 10.5)).foregroundStyle(Ink.tertiary)
                }
                Spacer(minLength: 0)
                if let at = choice.at { LiveClock(since: at, size: 11, opacity: 0.55) }
            }
            if let q = choice.question {
                Text(q)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !choice.options.isEmpty {
                ViewThatFits(in: .horizontal) {
                    options(choice.options.prefix(4))
                    options(choice.options.prefix(2))
                }
            }
            Label(choice.kind == .plan ? L("回到 Claude Code 里批准", "Approve in Claude Code") : L("回到 Claude Code 里选择", "Answer in Claude Code"),
                  systemImage: "arrow.uturn.left")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Self.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.accent.opacity(0.12)))
    }

    private func options(_ shown: ArraySlice<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, o in
                Text(o)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .fixedSize()
            }
            if choice.options.count > shown.count {
                Text("+\(choice.options.count - shown.count)")
                    .font(Ink.number(10.5))
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }
}
