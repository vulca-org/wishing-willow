import SwiftUI

@MainActor
@Observable
final class IslandState {
    var expanded = false
    /// 黑色形状此刻该有的尺寸。窗口只是舞台（瞬间定大小、透明），形状在舞台里用 spring 变化。
    /// 起因：录屏逐帧测过，NSPanel 的窗口尺寸动画根本没发生——宽度一步从 340 跳到 480，没有任何中间值。
    var shapeSize: CGSize = .zero
    /// 点击后的面板态：灵动岛再长大一档。
    var detail = false
}

/// 灵动岛本体：纯黑、顶边贴着屏幕上沿、下方两角圆，和刘海连成一块。
///
/// 不用玻璃。浅色半透明的 Liquid Glass 放在这里，读起来是一个悬浮窗，
/// 不是刘海长出来的东西 —— 这是用真实截图对照之后改的，不是凭审美。
///
/// 收起时刘海正下方那 156pt 什么都不画：那块是摄像头，画了也看不见。
/// 左翼放圆点，右翼放 ≤6 字标签，刚好是右翼放得下的长度。
struct IslandView: View {
    let store: WillowStore
    let seen: SeenStore
    let state: IslandState
    let notchWidth: CGFloat
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onClose: () -> Void

    private var focus: SessionState? { FocusRule.focus(store, seen) }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: state.expanded ? 20 : 10,
                    bottomTrailingRadius: state.expanded ? 20 : 10
                )
                // 两翼缩回刘海时整块不画：物理刘海本身是黑的，再画一层只会在圆角处漏出一两个像素。
                .fill(Color.black.opacity(state.expanded || wingLabel != nil ? 1 : 0))

                if state.detail {
                    DetailView(store: store, seen: seen, onClose: onClose)
                        .frame(width: DetailView.size.width, height: DetailView.size.height, alignment: .top)
                        .transition(.opacity)
                } else if state.expanded {
                    // 内容固定宽度，形状长大时被裁切着逐渐露出——不在长大过程中反复换行。
                    IslandExpandedContent(store: store, seen: seen)
                        .frame(width: IslandController.expandedWidth, alignment: .topLeading)
                        .transition(.opacity)
                } else if let f = focus, let l = wingLabel {
                    compact(f, l)
                        .transition(.opacity)
                }
            }
            .frame(width: state.shapeSize.width, height: state.shapeSize.height, alignment: .top)
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: state.expanded ? 20 : 10,
                bottomTrailingRadius: state.expanded ? 20 : 10
            ))
            // 悬停与点击只挂在形状上：舞台在过渡期间比形状大，那片透明边缘不该触发任何事。
            .contentShape(Rectangle())
            .onHover(perform: onHover)
            .onTapGesture { if !state.detail { onClick() } }   // 面板里的点击交给面板自己
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var wingLabel: FocusRule.Label? { focus.flatMap { FocusRule.label($0, seen, store) } }

    // MARK: 收起

    private func compact(_ f: SessionState, _ l: FocusRule.Label) -> some View {
        HStack(spacing: 0) {
            // 左翼只放状态。先前放「+1」，用户看不懂是什么；会话数挪到展开态的页脚。
            HStack { Spacer(minLength: 0); indicator(f) }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)          // 摄像头那一块，画了也看不见

            // 右翼：标签。换内容时淡入淡出——「回答中」收敛成标签的那一下要看得出来。
            HStack(spacing: 0) {
                Text(l.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(f.declaration == .unreadable ? Color.red
                                     : Color.white.opacity(l.carried ? 0.55 : 1))
                    .lineLimit(1)
                    .id(l.text)
                    // 旧的字朝刘海方向退回去，新的字从外侧进来——撤回时看得出是「收回」。
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                Spacer(minLength: 0)
            }
            .padding(.leading, 8)
            // 6 个汉字在 11pt 约 67pt。翼宽 92 − 8 − 10 = 74，放得下也不贴圆角。
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity)
            .clipped()
        }
        .frame(height: 28)
        .animation(.easeOut(duration: 0.35), value: l.text)
    }

    /// 进行中：会动的省略号 + 从按回车起的计时（这是真的在走的东西）；其余是一个点。
    @ViewBuilder
    private func indicator(_ f: SessionState) -> some View {
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
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                if let start = f.record.updatedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Clock.text(ctx.date.timeIntervalSince(start)))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
            }
        } else {
            Circle().fill(tint(f)).frame(width: 7, height: 7)
        }
    }

    private func tint(_ s: SessionState) -> Color {
        if s.declaration == .unreadable { return .red }
        guard seen.isUnread(s) else { return Color.white.opacity(0.35) }
        return s.flaggedByModel ? .orange : .white
    }
}

/// 展开态的内容，单独成一个视图：控制器要先量出它的真实高度再定面板大小。
/// 先前高度写死 156pt，内容一短底部就空出一大块黑——「不要空白内容」。
struct IslandExpandedContent: View {
    let store: WillowStore
    let seen: SeenStore

    private var focus: SessionState? { FocusRule.focus(store, seen) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear.frame(height: 24)                 // 刘海那一条

            if let s = focus {
                if s.record.isSystemMessage {
                    // 不是人说的话，不能挂在「你批准的」下面。
                    row("这一轮", "系统消息（\(PromptSource.describe(s.prompt))），不是你说的", Color.white.opacity(0.55))
                } else {
                    row("你批准的", s.prompt ?? "—", Color.white)
                }
                decodeRow(s)
                    .id(String(describing: s.declaration))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                HStack(spacing: 6) {
                    Text(s.workspace)
                    let n = FocusRule.others(store)
                    if n > 0 { Text("· 另有 \(n) 个会话") }
                    Spacer(minLength: 0)
                    Text("点击看历史")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(1)
            } else {
                Text("没有活动的会话")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ label: String, _ text: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.45))
            Text(text)
                .font(.system(size: 12.5))
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
        case .interrupted:
            LiveTurnSection(started: s.record.updatedAt, progress: store.progress(for: s))
        case .inProgress:
            // 假进度条去掉了——它暗示一个并不存在的完成度。这里只放真的在发生的事。
            LiveTurnSection(started: s.record.updatedAt, progress: store.progress(for: s))
        }
    }

}


enum Clock {
    static func text(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
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
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                    Text("你撤回了这一轮").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    if let started {
                        Text("跑了 " + Clock.text(cut.timeIntervalSince(started)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                }
                .foregroundStyle(Color.white)
                if let d = progress?.decode {
                    Text("撤回前读成了：" + d)
                        .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.45)).lineLimit(2)
                }
            } else if let d = progress?.decode {
                HStack(spacing: 6) {
                    Text("我读成了").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                    Text("实时")
                        .font(.system(size: 8.5, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                Text(d)
                    .font(.system(size: 12.5))
                    .foregroundStyle(d.hasPrefix("⚠") ? Color.orange : Color.white)
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                Text("我读成了").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.45))
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .symbolEffect(.pulse, options: .repeating)
                    Text(phase).font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if let started {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(Clock.text(ctx.date.timeIntervalSince(started)))
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
            }
            if let steps = progress?.steps, !steps.isEmpty {
                let recent = Array(steps.suffix(3))
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { i, st in
                        let current = i == recent.count - 1
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.white.opacity(current && progress?.interruptedAt == nil ? 0.9 : 0.28))
                                .frame(width: 5, height: 5)
                            Text(st.text)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(current && progress?.interruptedAt == nil ? 0.85 : 0.4))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let at = st.at, let started {
                                Text("+" + Clock.text(at.timeIntervalSince(started)))
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.3))
                            }
                        }
                    }
                    if steps.count > 3 {
                        Text("共 \(steps.count) 步")
                            .font(.system(size: 9.5)).foregroundStyle(Color.white.opacity(0.3))
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
