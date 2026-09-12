import SwiftUI

@MainActor
@Observable
final class IslandState {
    var expanded = false
    /// 黑色形状此刻该有的尺寸。窗口只是舞台（瞬间定大小、透明），形状在舞台里用 spring 变化。
    /// 起因：录屏逐帧测过，NSPanel 的窗口尺寸动画根本没发生——宽度一步从 340 跳到 480，没有任何中间值。
    var shapeSize: CGSize = .zero
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

                if state.expanded {
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
            .onTapGesture(perform: onClick)
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
                    .transition(.opacity.combined(with: .move(edge: .leading)))
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

    /// 回答中是会动的省略号——运动表示「事情还在进行」；其余是一个点。
    @ViewBuilder
    private func indicator(_ f: SessionState) -> some View {
        if f.declaration == .inProgress {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.75))
                .symbolEffect(.pulse, options: .repeating)
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
        case .inProgress:
            // 加载态：会动的省略号 + 一条扫光占位。声明到达时整行被真正的解码替换，淡入。
            VStack(alignment: .leading, spacing: 5) {
                Text("我读成了")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                HStack(spacing: 6) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .symbolEffect(.pulse, options: .repeating)
                    Text("模型正在回答，声明写出来会出现在这里")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                ShimmerBar().frame(width: 280, height: 7)
            }
        }
    }

}

/// 加载占位条：一道光从左到右扫过。只在「回答中」出现——运动表示事情还在进行。
struct ShimmerBar: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t.truncatingRemainder(dividingBy: 1.4) / 1.4)
            GeometryReader { geo in
                let w = geo.size.width
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .overlay(alignment: .leading) {
                        LinearGradient(colors: [.clear, Color.white.opacity(0.25), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: w * 0.35)
                            .offset(x: -w * 0.35 + w * 1.35 * phase)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}
