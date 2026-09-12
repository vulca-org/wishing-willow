import SwiftUI

@MainActor
@Observable
final class IslandState {
    var expanded = false
    /// 黑色形状此刻该有的尺寸（含两侧凹肩）。窗口只是舞台（瞬间定大小、透明），形状在舞台里用 spring 变化。
    /// 起因：录屏逐帧测过，NSPanel 的窗口尺寸动画根本没发生——宽度一步从 340 跳到 480，没有任何中间值。
    var shapeSize: CGSize = .zero
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
/// 收起时刘海正下方那一块什么都不画：那块是摄像头，画了也看不见。
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

    var body: some View {
        let pair = FocusRule.pair(store, seen, pinned: state.pinned)
        let label = pair.primary.flatMap { FocusRule.label($0, seen, store) }
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // 两翼缩回刘海时整块不画：物理刘海本身是黑的，再画一层只会在肩和圆角处漏出几个像素。
                shape.fill(Color.black.opacity(open || label != nil ? 1 : 0))

                if state.detail {
                    DetailView(store: store, seen: seen, notchWidth: notchWidth, notchHeight: notchHeight, onClose: onClose)
                        .frame(width: DetailView.size.width - 2 * NotchShape.open.top,
                               height: DetailView.size.height, alignment: .top)
                        .transition(.opacity)
                } else if state.expanded {
                    // 内容固定宽度，形状长大时被裁切着逐渐露出——不在长大过程中反复换行。
                    IslandExpandedContent(store: store, seen: seen, pinned: state.pinned,
                                          notchWidth: notchWidth, notchHeight: notchHeight, onSwitch: onSwitch)
                        .frame(width: IslandController.expandedWidth, alignment: .topLeading)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                } else if let f = pair.primary, let l = label {
                    CompactWings(store: store, seen: seen, session: f, label: l,
                                 notchWidth: notchWidth, height: notchHeight)
                        .padding(.horizontal, NotchShape.closed.top)
                        .transition(.opacity)
                }
            }
            .frame(width: state.shapeSize.width, height: state.shapeSize.height, alignment: .top)
            .clipShape(shape)
            // 暗色背景上的一条细边：HIG 的 key line，黑岛压在深色壁纸上时靠它分出边界。
            .overlay { if open { shape.stroke(Color.white.opacity(0.08), lineWidth: 1) } }
            .shadow(color: .black.opacity(open ? 0.7 : 0), radius: 6)
            // 悬停与点击只挂在形状上：舞台在过渡期间比形状大，那片透明边缘不该触发任何事。
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
                    .offset(x: state.shapeSize.width / 2 + IslandController.pillGap + state.pillWidth / 2,
                            y: (notchHeight - IslandController.pillHeight) / 2)
                    .transition(.scale(scale: 0.3, anchor: .leading).combined(with: .opacity))
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
                    // 旧的字朝刘海方向退回去，新的字从外侧进来——撤回时看得出是「收回」。
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
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
            // 结束了的一轮：点 + 声明躺了多久。这正是这个产品要缩短的那个数。
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
/// 按 HIG「展开态是放大的收起态」：刘海两侧的耳朵放收起态的同一组信息（左状态、右标签），
/// 下面才是「你批准的 / 我读成了」，页脚是第二个会话（点一下切过去）。
struct IslandExpandedContent: View {
    let store: WillowStore
    let seen: SeenStore
    var pinned: String? = nil
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    var onSwitch: ((String) -> Void)? = nil

    var body: some View {
        let pair = FocusRule.pair(store, seen, pinned: pinned)
        VStack(alignment: .leading, spacing: 0) {
            ears(pair.primary)
            VStack(alignment: .leading, spacing: 10) {
                if let s = pair.primary {
                    if s.record.isSystemMessage {
                        // 不是人说的话，不能挂在「你批准的」下面。
                        row("这一轮", "系统消息（\(PromptSource.describe(s.prompt))），不是你说的", Color.white.opacity(0.55))
                    } else {
                        row("你批准的", s.prompt ?? "—", Color.white)
                    }
                    decodeRow(s)
                        .id(String(describing: s.declaration))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    footer(s, pair.secondary)
                } else {
                    Text("没有活动的会话")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 刘海两侧：左耳 = 工作区 … 状态（贴摄像头），右耳 = 标签（贴摄像头）… 阶段。
    private func ears(_ s: SessionState?) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let s {
                    Text(s.workspace)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
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
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.42))
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
        FocusRule.label(s, seen, store)?.text ?? s.tag ?? FocusRule.lastLoggedTag(s, store) ?? "还没有标签"
    }

    private func phaseWord(_ s: SessionState) -> String {
        if store.recentWithdraw[s.id] != nil { return "撤回" }
        switch s.declaration {
        case .unreadable: return "插件读不到"
        case .interrupted: return "被打断"
        case .awaiting: return "等待开始"
        case .inProgress:
            guard let p = store.progress(for: s) else { return "回答中" }
            if p.decode != nil { return "实时" }
            return p.firstWriteAt == nil ? "思考中" : "回答中"
        case .declared, .undeclared, .notAsked: return "已结束"
        }
    }

    private func row(_ label: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(color)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 「没问」「问了没答」「插件坏了」必须是三句不同的话。
    @ViewBuilder
    private func decodeRow(_ s: SessionState) -> some View {
        switch s.declaration {
        case .declared(let d):
            row("我读成了", d, s.flaggedByModel ? .orange : .white)
        case .undeclared:
            row("我读成了", "问了，模型没写声明", .orange)
        case .unreadable:
            row("我读成了", "读不到本轮输入 —— 插件坏了，不是模型没说话", .red)
        case .awaiting:
            row("我读成了", "等这一轮开始", Color.white.opacity(0.5))
        case .notAsked:
            row("我读成了", "这一轮没问（太短或是系统消息）", Color.white.opacity(0.5))
        case .interrupted, .inProgress:
            // 假进度条去掉了——它暗示一个并不存在的完成度。这里只放真的在发生的事。
            LiveTurnSection(started: s.record.updatedAt, progress: store.progress(for: s))
        }
    }

    /// 页脚：有第二个会话就放它（点一下切过去）；否则说清楚其余会话的状况。
    @ViewBuilder
    private func footer(_ s: SessionState, _ other: SessionState?) -> some View {
        if let other, let pill = FocusRule.pill(other, seen, store) {
            Button { onSwitch?(other.id) } label: {
                HStack(spacing: 8) {
                    SessionPill(pill: pill, extra: 0)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                    Text(other.tag ?? FocusRule.lastLoggedTag(other, store) ?? "还没有标签")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.88))
                        .lineLimit(1)
                    Text(other.workspace)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    let more = FocusRule.extra(store, primary: s, secondary: other)
                    if more > 0 {
                        Text("另有 \(more) 个").font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.38))
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                // 同心圆角：外框下角 24、内缩 12 → 内框 12。
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 6) {
                let n = FocusRule.others(store)
                Text(n > 0 ? "另有 \(n) 个会话，暂时没有新东西" : "只有这一个会话在跑")
                Spacer(minLength: 0)
                Text("点击看历史")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Color.white.opacity(0.4))
            .lineLimit(1)
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

/// 进行中这一轮的实时区块：阶段 + 计时，声明写出后换成声明（标「实时」），下面是最近三个真实步骤。
///
/// 阶段只说读得到的事实：还没落盘就是在思考（思考块没有文字，读不到想了什么）；
/// 开始落盘还没声明；声明写出。步骤来自工具调用，时间是距按回车的偏移。
struct LiveTurnSection: View {
    let started: Date?
    let progress: TurnProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let cut = progress?.interruptedAt {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text("你撤回了这一轮").font(.system(size: 13.5, weight: .medium))
                    Spacer(minLength: 0)
                    if let started {
                        Text("跑了 " + Clock.text(cut.timeIntervalSince(started)))
                            .font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .foregroundStyle(Color.white)
                if let d = progress?.decode {
                    Text("撤回前读成了：" + d)
                        .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(2)
                }
            } else if let d = progress?.decode {
                HStack(spacing: 6) {
                    Text("我读成了").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                    Text("实时")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                Text(d)
                    .font(.system(size: 13.5))
                    .foregroundStyle(d.hasPrefix("⚠") ? Color.orange : Color.white)
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("我读成了").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .symbolEffect(.pulse, options: .repeating)
                    Text(phase).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if let started { LiveClock(since: started, size: 11.5, opacity: 0.5) }
                }
            }
            if let steps = progress?.steps, !steps.isEmpty {
                let recent = Array(steps.suffix(3))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { i, st in
                        let current = i == recent.count - 1 && progress?.interruptedAt == nil
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(current ? 0.9 : 0.28))
                                .frame(width: 5, height: 5)
                            Text(st.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color.white.opacity(current ? 0.85 : 0.4))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let at = st.at, let started {
                                Text("+" + Clock.text(at.timeIntervalSince(started)))
                                    .font(.system(size: 10, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(Color.white.opacity(0.3))
                            }
                        }
                    }
                    if steps.count > 3 {
                        Text("共 \(steps.count) 步")
                            .font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.3))
                    }
                }
                .padding(.top, 2)
            }
        }
        .animation(.easeOut(duration: 0.3), value: progress?.decode)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: progress?.interruptedAt)
        .animation(.easeOut(duration: 0.25), value: progress?.steps.count)
    }

    private var phase: String {
        guard let p = progress else { return "模型正在回答" }
        if p.firstWriteAt == nil { return "思考中" }
        return p.steps.isEmpty ? "开始回答，还没写出声明" : "在执行，还没写出声明"
    }
}
