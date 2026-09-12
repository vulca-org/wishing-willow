import SwiftUI

@MainActor
@Observable
final class IslandState {
    var expanded = false
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
            UnevenRoundedRectangle(
                bottomLeadingRadius: state.expanded ? 20 : 10,
                bottomTrailingRadius: state.expanded ? 20 : 10
            )
            .fill(Color.black)

            if state.expanded { expanded } else { compact }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: onClick)
        .environment(\.colorScheme, .dark)
    }

    // MARK: 收起

    private var compact: some View {
        HStack(spacing: 0) {
            // 左翼：其他会话数 + 圆点。先前左翼只有一个点，一大块黑是空的 ——
            // 真实截图里看出来的，「不要空白内容」。
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                let n = FocusRule.others(store)
                if n > 0 {
                    Text("+\(n)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                if let f = focus {
                    Circle().fill(tint(f)).frame(width: 7, height: 7)
                }
            }
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)          // 摄像头那一块，画了也看不见

            // 右翼：≤6 字标签，刚好放得下。
            HStack(spacing: 0) {
                if let f = focus, let l = FocusRule.label(f, seen, store) {
                    Text(l.text)
                        .font(.system(size: 11, weight: .medium))
                        // 沿用上一轮的标签调暗：它说的是这个会话在做什么，不是这一轮读成了什么。
                        .foregroundStyle(f.declaration == .unreadable ? Color.red
                                         : Color.white.opacity(l.carried ? 0.55 : 1))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 28)
    }

    // MARK: 展开

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 7) {
            Color.clear.frame(height: 24)                 // 刘海那一条

            if let s = focus {
                row("你批准的", s.prompt ?? "—", Color.white)
                decodeRow(s)
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
        }
    }

    private func tint(_ s: SessionState) -> Color {
        if s.declaration == .unreadable { return .red }
        guard seen.isUnread(s) else { return Color.white.opacity(0.35) }
        return s.flaggedByModel ? .orange : .white
    }
}
