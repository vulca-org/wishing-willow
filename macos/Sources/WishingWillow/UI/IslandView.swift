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
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onClose: () -> Void
    let onSwitch: (String) -> Void

    private var open: Bool { state.expanded || state.detail }
    private var radii: (top: CGFloat, bottom: CGFloat) { open ? NotchShape.open : NotchShape.closed }

    /// 内容退场一律快速淡出：收起时先让字消失，形状再收回刘海。
    private static let quickOut = AnyTransition.asymmetric(
        insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.12)))

    var body: some View {
        let pair = FocusRule.pair(store, seen, pinned: state.pinned)
        let label = pair.primary.flatMap { FocusRule.label($0, seen, store) }
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // 缩回刘海时不能画成全透明：窗口里 alpha 为 0 的像素，鼠标事件直接穿过窗口，悬停永远到不了这里。
                // 2026-09-12 真鼠标复现：两次悬停把会话都看过之后灵动岛缩回刘海，第三次悬停刘海，日志里没有 hover-in。
                // 2% 的黑盖在物理刘海上看不见，但足够让窗口接住鼠标。
                shape.fill(Color.black.opacity(open || label != nil ? 1 : 0.02))

                if state.detail {
                    DetailView(store: store, seen: seen, notchWidth: notchWidth, notchHeight: notchHeight, onClose: onClose)
                        .frame(width: DetailView.size.width - 2 * NotchShape.open.top,
                               height: DetailView.size.height, alignment: .top)
                        .transition(Self.quickOut)
                } else if state.expanded {
                    // 内容固定宽度，形状长大时被裁切着逐渐露出——不在长大过程中反复换行。
                    // 各块自己按从上到下的次序长出来（Reveal），这里不再整体淡入。
                    IslandExpandedContent(store: store, seen: seen, pinned: state.pinned,
                                          notchWidth: notchWidth, notchHeight: notchHeight, onSwitch: onSwitch)
                        .frame(width: IslandController.expandedWidth, alignment: .topLeading)
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
            .shadow(color: .black.opacity(open ? 0.7 : 0), radius: 6)
            // 悬停与点击只挂在形状上：舞台比形状大，那片透明边缘不该触发任何事。
            .contentShape(shape)
            .onHover(perform: onHover)
            .onTapGesture { if !state.detail { onClick() } }   // 面板里的点击交给面板自己

            if !open, state.pillWidth > 0, let other = pair.secondary,
               let pill = FocusRule.pill(other, seen, store) {
                SessionPill(pill: pill, extra: FocusRule.extra(store, primary: pair.primary, secondary: other))
                    .frame(width: state.pillWidth, height: IslandController.pillHeight)
                    .background(Capsule().fill(Color.black))
                    .contentShape(Capsule())
                    .onTapGesture { onSwitch(other.id) }
                    // 用布局把胶囊推到右边，不用 offset：居中的一整段宽 = 左内边距 + 胶囊，
                    // 胶囊中心 = 舞台中心 + 内边距 / 2 = 形状右缘 + 间隙 + 胶囊半宽。点击区与画出来的位置同一处。
                    .padding(.leading, state.shapeWidth + 2 * IslandController.pillGap + state.pillWidth)
                    .padding(.top, (notchHeight - IslandController.pillHeight) / 2)
                    // 退场快速淡出：先前缩放退场与正在长大的形状叠在一起，录屏第 52–53 帧右缘多出 130px。
                    .transition(.asymmetric(insertion: .scale(scale: 0.3, anchor: .leading).combined(with: .opacity),
                                            removal: .opacity.animation(.easeOut(duration: 0.08))))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
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
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                StatusGlyph(store: store, seen: seen, session: session)
            }
            .padding(.trailing, 9)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)          // 摄像头那一块，画了也看不见

            HStack(spacing: 0) {
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
            // 6 个汉字在 12pt semibold 约 72pt。翼宽 92 − 9 − 8 = 75，放得下也不贴圆角。
            .padding(.leading, 9)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.35), value: label.text)
    }
}

/// 左翼与展开态左耳的状态符号：只放真的在走或真的发生过的事。
struct StatusGlyph: View {
    let store: WillowStore
    let seen: SeenStore
    let session: SessionState

    var body: some View {
        let f = session
        if let w = store.recentWithdraw[f.id] {
            // 撤回：箭头跳一下；打断时计时停在撤回那一刻并划掉。
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .symbolEffect(.bounce, value: w.at)
                if w.kind == .interrupted, let start = f.record.updatedAt,
                   let end = store.progress(for: f)?.interruptedAt {
                    Text(Clock.text(end.timeIntervalSince(start)))
                        .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.45))
                        .strikethrough(true, color: Color.white.opacity(0.5))
                }
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if let c = store.progress(for: f)?.pendingChoice {
            // 等你选择：换成会动的问号，计时从模型提问那一刻算——这是它等了你多久。
            HStack(spacing: 5) {
                Image(systemName: c.kind == .plan ? "checklist" : "questionmark.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ChoiceCard.accent)
                    .symbolEffect(.pulse, options: .repeating)
                if let at = c.at ?? f.record.updatedAt { LiveClock(since: at, opacity: 0.8) }
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        } else if f.declaration == .inProgress {
            HStack(spacing: 5) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .symbolEffect(.pulse, options: .repeating)
                if let start = f.record.updatedAt { LiveClock(since: start) }
            }
        } else if f.declaration == .unreadable {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.red)
        } else {
            // 结束了的一轮：点 + 声明躺了多久。
            HStack(spacing: 5) {
                Circle().fill(tint(f)).frame(width: 7, height: 7)
                // 旧记录没有 turnEndedAt；提取时 updatedAt 与结束时刻同时写下，退回它。
                if let end = f.record.turnEndedAt ?? f.record.updatedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text(Clock.ago(end, now: ctx.date))
                            .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private func tint(_ s: SessionState) -> Color {
        guard seen.isUnread(s) else { return Color.white.opacity(0.35) }
        if s.declaration == .undeclared { return .orange }
        return s.flaggedByModel ? .orange : .white
    }
}

/// 第二个会话的分离胶囊。宽度只够一个符号加两三个字。
struct SessionPill: View {
    let pill: FocusRule.Pill
    let extra: Int

    var body: some View {
        HStack(spacing: 5) {
            switch pill {
            case .broken:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.red)
                Text("读不到")
            case .choice(let plan, let since):
                Image(systemName: plan ? "checklist" : "questionmark.bubble.fill").foregroundStyle(ChoiceCard.accent)
                if let since { LiveClock(since: since, opacity: 0.9) } else { Text(plan ? "等批准" : "等你选") }
            case .withdraw:
                Image(systemName: "arrow.uturn.backward")
                Text("撤回")
            case .running(let since):
                Image(systemName: "ellipsis").symbolEffect(.pulse, options: .repeating)
                if let since { LiveClock(since: since, opacity: 0.9) } else { Text("回答中") }
            case .fresh(_, let flagged):
                Circle().fill(flagged ? Color.orange : Color.white).frame(width: 6, height: 6)
                Text("新声明")
            case .silent:
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("没写")
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 9)
    }
}

// MARK: 展开

/// 展开态的内容，单独成一个视图：控制器要先量出它的真实高度再定形状大小。
///
/// 按图纸的画法排：刘海两侧的耳朵放收起态的同一组信息；下面三节带引出编号，因为它们真的有先后——
/// ① 你批准的 → ② 我读成了 → ③ 模型在做的。每节标题后面一条引线，引到右侧一个可以核对的数
/// （回车时刻、声明写出的偏移、步数与首次落盘）。第 ③ 节是这一轮的时间刻度尺。底部是图签。
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
                let timeline = store.timeline(for: s)
                VStack(alignment: .leading, spacing: 11) {
                    approved(s, timeline).reveal(1, shown)
                    decoded(s, timeline).reveal(2, shown)
                    if let timeline { working(timeline).reveal(3, shown) }
                    titleBlock(s, pair.secondary).reveal(4, shown)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 14)
            } else {
                Text("没有活动的会话")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .reveal(1, shown)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { DispatchQueue.main.async { shown = true } }
    }

    // 刘海两侧：左耳 = 工作区 … 状态（贴摄像头），右耳 = 标签（贴摄像头）… 阶段。
    private func ears(_ s: SessionState?) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let s {
                    Text(s.workspace)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Ink.note)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    StatusGlyph(store: store, seen: seen, session: s)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 18).padding(.trailing, 10)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                if let s {
                    Text(earTag(s))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(s.flaggedByModel ? Color.orange : Color.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(phaseWord(s))
                        .font(Ink.mono(9.5))
                        .foregroundStyle(Ink.note)
                        .lineLimit(1)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 10).padding(.trailing, 18)
            .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    private func earTag(_ s: SessionState) -> String {
        // 等你选择时「等你选择」已经在阶段位上，标签位放这一轮在做什么——先前两处写了同一句。
        if let p = store.progress(for: s), p.pendingChoice != nil {
            return p.tag ?? s.tag ?? FocusRule.lastLoggedTag(s, store) ?? "还没有标签"
        }
        return FocusRule.label(s, seen, store)?.text ?? s.tag ?? FocusRule.lastLoggedTag(s, store) ?? "还没有标签"
    }

    private func phaseWord(_ s: SessionState) -> String {
        if store.recentWithdraw[s.id] != nil { return "撤回" }
        switch s.declaration {
        case .unreadable: return "插件读不到"
        case .interrupted: return "被打断"
        case .awaiting: return "等待开始"
        case .inProgress:
            guard let p = store.progress(for: s) else { return "回答中" }
            if let c = p.pendingChoice { return c.kind == .plan ? "等你批准" : "等你选择" }
            if p.decode != nil { return "实时" }
            return p.firstWriteAt == nil ? "思考中" : "回答中"
        case .declared, .undeclared, .notAsked: return "已结束"
        }
    }

    // MARK: ① 你批准的

    private func approved(_ s: SessionState, _ tl: TurnTimeline?) -> some View {
        let system = s.record.isSystemMessage
        let start = tl?.startedAt ?? (s.declaration == .inProgress ? s.record.updatedAt : nil)
        let note = [start.map { Self.clock($0) + " 回车" }, system ? nil : s.prompt.map { "\($0.count) 字" }]
            .compactMap { $0 }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(number: 1, title: system ? "这一轮" : "你批准的", note: note.isEmpty ? nil : note)
            // 不是人说的话，不能挂在「你批准的」下面。
            para(system ? "系统消息（\(PromptSource.describe(s.prompt))），不是你说的" : (s.prompt ?? "—"),
                 system ? Ink.secondary : Ink.primary)
        }
    }

    // MARK: ② 我读成了

    /// 「没问」「问了没答」「插件坏了」必须是三句不同的话。
    @ViewBuilder
    private func decoded(_ s: SessionState, _ tl: TurnTimeline?) -> some View {
        let p = store.progress(for: s)
        VStack(alignment: .leading, spacing: 4) {
            switch s.declaration {
            case .declared(let d):
                SectionHeader(number: 2, title: "我读成了", note: declaredNote(s, tl),
                              noteTint: s.flaggedByModel ? .orange : Ink.note)
                para(d, s.flaggedByModel ? .orange : Ink.primary)
            case .undeclared:
                SectionHeader(number: 2, title: "我读成了", note: "已结束 · 没有声明", noteTint: .orange)
                para("问了，模型没写声明", .orange)
            case .unreadable:
                SectionHeader(number: 2, title: "我读成了", note: "插件读不到输入", noteTint: .red)
                para("读不到本轮输入 —— 插件坏了，不是模型没说话", .red)
            case .awaiting:
                SectionHeader(number: 2, title: "我读成了", note: "等待开始")
                para("等这一轮开始", Ink.note)
            case .notAsked:
                SectionHeader(number: 2, title: "我读成了", note: "这一轮没问")
                para("这一轮没问（太短或是系统消息）", Ink.note)
            case .interrupted:
                SectionHeader(number: 2, title: "我读成了", note: offsetNote(p?.interruptedAt, tl).map { "撤回于 " + $0 })
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Ink.secondary)
                    Text("你撤回了这一轮").font(.system(size: 13.5, weight: .medium)).foregroundStyle(Ink.primary)
                }
                .padding(.leading, 20)
                if let d = p?.decode { para("撤回前读成了：" + d, Ink.note) }
            case .inProgress:
                if let d = p?.decode {
                    SectionHeader(number: 2, title: "我读成了", note: offsetNote(p?.declaredAt, tl).map { $0 + " 写出" },
                                  badge: "实时")
                    para(d, d.hasPrefix("⚠") ? .orange : Ink.primary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    SectionHeader(number: 2, title: "我读成了", note: "还没写出")
                    HStack(spacing: 6) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Ink.secondary)
                            .symbolEffect(.pulse, options: .repeating)
                        Text(Self.phase(p)).font(.system(size: 13)).foregroundStyle(Ink.secondary)
                        Spacer(minLength: 0)
                        if let start = s.record.updatedAt { LiveClock(since: start, size: 11.5, opacity: 0.5) }
                    }
                    .padding(.leading, 20)
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: p?.decode)
    }

    private func declaredNote(_ s: SessionState, _ tl: TurnTimeline?) -> String {
        var parts: [String] = []
        if let at = offsetNote(tl?.progress.declaredAt, tl) { parts.append(at + " 写出") }
        parts.append(s.flaggedByModel ? "⚠ 模型自标不一致" : "已结束")
        return parts.joined(separator: " · ")
    }

    private func offsetNote(_ d: Date?, _ tl: TurnTimeline?) -> String? {
        guard let d, let start = tl?.startedAt else { return nil }
        return "+" + Clock.text(d.timeIntervalSince(start))
    }

    // MARK: ③ 在做 / 做了

    private func working(_ tl: TurnTimeline) -> some View {
        let p = tl.progress
        let live = tl.endedAt == nil && p.interruptedAt == nil
        var note = ["\(p.steps.count) 步"]
        if let first = p.firstWriteAt { note.append("首次落盘 +" + Clock.text(first.timeIntervalSince(tl.startedAt))) }
        return VStack(alignment: .leading, spacing: 6) {
            SectionHeader(number: 3, title: live ? "在做" : "做了", note: note.joined(separator: " · "))
            VStack(alignment: .leading, spacing: 6) {
                if live, let c = p.pendingChoice {
                    ChoiceCard(choice: c)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                }
                TimelineRuler(timeline: tl)
                if !(live && p.pendingChoice != nil), !p.steps.isEmpty {
                    StepList(timeline: tl, limit: 2)
                }
            }
            .padding(.leading, 20)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: p.pendingChoice)
        .animation(.easeOut(duration: 0.25), value: p.steps.count)
    }

    // MARK: 图签

    /// 图签：工作区 / 会话 / 本会话写了声明的轮数 / 另一个会话（点一下切过去）。
    private func titleBlock(_ s: SessionState, _ other: SessionState?) -> some View {
        let log = TurnLog.read(sessionId: s.id, directory: store.directory)
        let asked = log.filter { $0.reminded == true && $0.interrupted != true }
        let wrote = asked.filter(\.declared).count
        return HStack(spacing: 0) {
            TitleCell(label: "工作区", value: s.workspace).frame(width: 112, alignment: .leading)
            TitleRule()
            TitleCell(label: "会话", value: String(s.id.prefix(8)), mono: true).frame(width: 84, alignment: .leading)
            TitleRule()
            TitleCell(label: "写了声明", value: asked.isEmpty ? "—" : "\(wrote)/\(asked.count) 轮").frame(width: 74, alignment: .leading)
            TitleRule()
            otherCell(s, other).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 34)
        .overlay(Rectangle().stroke(Ink.rule, lineWidth: Ink.hair))
        .overlay(CornerMarks(length: 5).stroke(Ink.secondary, lineWidth: 0.75))
    }

    @ViewBuilder
    private func otherCell(_ s: SessionState, _ other: SessionState?) -> some View {
        if let other, let pill = FocusRule.pill(other, seen, store) {
            Button { onSwitch?(other.id) } label: {
                HStack(spacing: 6) {
                    TitleCell(label: "另一会话 · 点击切换",
                              value: other.tag ?? FocusRule.lastLoggedTag(other, store) ?? other.workspace)
                    Spacer(minLength: 0)
                    SessionPill(pill: pill, extra: FocusRule.extra(store, primary: s, secondary: other))
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .padding(.trailing, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            let n = FocusRule.others(store)
            TitleCell(label: "其余会话 · 点击看历史", value: n > 0 ? "\(n) 个，暂时没有新东西" : "只有这一个在跑",
                      valueTint: Ink.secondary)
        }
    }

    // MARK: 小件

    private func para(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)                       // 与编号后的标题对齐：悬挂缩进
    }

    static func phase(_ p: TurnProgress?) -> String {
        guard let p else { return "模型正在回答" }
        if p.firstWriteAt == nil { return "思考中" }
        return p.steps.isEmpty ? "开始回答，还没写出声明" : "在执行，还没写出声明"
    }

    static func clock(_ d: Date) -> String {
        d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

/// 最近几步：左边一列等宽的时间偏移，像施工日志；最新一步亮，其余暗。
struct StepList: View {
    let timeline: TurnTimeline
    var limit = 2

    var body: some View {
        let steps = timeline.progress.steps
        let recent = Array(steps.suffix(limit))
        let live = timeline.endedAt == nil && timeline.progress.interruptedAt == nil
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(recent.enumerated()), id: \.offset) { i, st in
                let current = live && i == recent.count - 1
                HStack(spacing: 6) {
                    Text(st.at.map { "+" + Clock.text($0.timeIntervalSince(timeline.startedAt)) } ?? "")
                        .font(Ink.mono(9.5))
                        .foregroundStyle(Ink.note)
                        .frame(width: 42, alignment: .trailing)
                    Rectangle()
                        .fill(current ? Color.white.opacity(0.9) : Ink.faint)
                        .frame(width: 6, height: 0.75)
                    Text(st.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(current ? Color.white.opacity(0.88) : Ink.note)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if i == 0, steps.count > recent.count {
                        Text("最近 \(recent.count) / 共 \(steps.count)")
                            .font(Ink.mono(9))
                            .foregroundStyle(Ink.faint)
                    }
                }
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
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60) 分" }
        return "\(s / 3600) 时"
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
        }
    }
}

/// 模型在等你选：题面与选项。灵动岛没法往 Claude Code 里输入，不替你选，只负责把你叫回去。
/// 颜色另起一个蓝：橙色是「读偏了」、红色是「插件坏了」，而「轮到你了」不是任何一种错误。
struct ChoiceCard: View {
    let choice: TurnProgress.Choice
    static let accent = Color(red: 0.45, green: 0.78, blue: 1.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: choice.kind == .plan ? "checklist" : "questionmark.bubble.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.accent)
                    .symbolEffect(.pulse, options: .repeating)
                Text(choice.kind == .plan ? "模型在等你批准计划" : "模型在等你选择")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white)
                if choice.count > 1 {
                    Text("共 \(choice.count) 题").font(Ink.mono(9.5)).foregroundStyle(Ink.note)
                }
                Spacer(minLength: 0)
                if let at = choice.at { LiveClock(since: at, size: 11, opacity: 0.55) }
            }
            if let q = choice.question {
                Text(q).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.9)).lineLimit(2)
            }
            if !choice.options.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(choice.options.prefix(4).enumerated()), id: \.offset) { i, o in
                        HStack(spacing: 4) {
                            Text(String(UnicodeScalar(UInt8(65 + i))))
                                .font(Ink.mono(9, .semibold))
                                .foregroundStyle(Self.accent)
                            Text(o)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Self.accent.opacity(0.35), lineWidth: Ink.hair))
                    }
                    if choice.options.count > 4 {
                        Text("+\(choice.options.count - 4)").font(Ink.mono(9.5)).foregroundStyle(Ink.note)
                    }
                }
            }
            Text(choice.kind == .plan ? "回 Claude Code 里批准" : "回 Claude Code 里选")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Self.accent.opacity(0.9))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Self.accent.opacity(0.08)))
        .overlay(Rectangle().stroke(Self.accent.opacity(0.28), lineWidth: Ink.hair))
        .overlay(CornerMarks(length: 6).stroke(Self.accent, lineWidth: 1))
    }
}
