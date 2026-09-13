import SwiftUI

/// The two rows. No glass, no tint, no score.
///
/// Whether they agree is not computed anywhere in this app. Asking a model to
/// judge its own decoding means asking it to use the same defaults that
/// produced the drift; it would report "aligned" and the reader would be worse
/// off than with no tool at all. So the rows are set side by side at equal
/// weight and the person reads them.
struct TurnView: View {
    let state: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isStale { staleNote }

            if state.record.isSystemMessage {
                row(label: L("这一轮", "This turn"), text: L("系统消息（\(PromptSource.describe(state.prompt))），不是你说的", "System message (\(PromptSource.describe(state.prompt))) — not from you"), tone: .secondary)
            } else {
                row(label: L("你的要求", "Your request"), text: state.prompt, tone: .primary)
            }

            switch state.declaration {
            case .declared(let d):
                row(label: L("Claude 的理解", "Claude’s reading"), text: d, tone: .primary)
            case .undeclared:
                banner(
                    icon: "circle.dotted",
                    title: L("本轮未声明", "No reading this turn"),
                    detail: L("模型没有写出它把这个请求读成了什么。缺席本身就是信号。", "Claude didn’t write how it read this request. The absence is the signal."),
                    tint: .yellow
                )
            case .unreadable:
                banner(
                    icon: "exclamationmark.triangle.fill",
                    title: L("读不到本轮输入", "Can’t read this turn’s input"),
                    detail: L("hook 跑了，但拿不到你说的话 —— 这是插件坏了，不是模型没说话。", "The hook ran but couldn’t get your words — the plugin is broken, Claude isn’t silent."),
                    tint: .red
                )
            case .awaiting:
                banner(
                    icon: "hourglass",
                    title: L("等第一轮", "Waiting for the first turn"),
                    detail: L("插件是在这一轮中间装上的，下一轮开始记录。", "The plugin was installed mid-turn; recording starts next turn."),
                    tint: .secondary
                )
            case .interrupted:
                banner(
                    icon: "arrow.uturn.backward",
                    title: L("你撤回了这一轮", "You withdrew this turn"),
                    detail: L("打断不会写出声明。", "An interrupted turn writes no reading."),
                    tint: .secondary
                )
            case .inProgress:
                banner(
                    icon: "ellipsis",
                    title: L("模型正在回答", "Claude is answering"),
                    detail: L("声明要等这一轮写出来才读得到。", "The reading appears once Claude writes it."),
                    tint: .secondary
                )
            case .notAsked:
                banner(
                    icon: "text.bubble",
                    title: L("这一轮没问", "Not asked this turn"),
                    detail: L("太短或是系统消息，插件没有注入提醒 —— 不是模型没说话。", "Too short or a system message, so no prompt was injected — Claude isn’t silent."),
                    tint: .secondary
                )
            }

            meta
        }
    }

    private func row(label: String, text: String?, tone: HierarchicalShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text ?? "—")
                .font(.system(size: 12))
                .foregroundStyle(tone)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one warning surface, and the second of the three places glass is used.
    private func banner(icon: String, title: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .willowGlass(.rounded(9), tint: tint)
    }

    private var staleNote: some View {
        Text(L("这个会话已经不活跃了，下面是它最后一轮的样子。", "This session is no longer active. Here is its last turn."))
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            if let cwd = state.record.cwd {
                Text(cwd)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
            // 轮次可能是未知的（插件在一轮中间装上）。不知道就显示「—」，
            // 不要把 null 渲染成「第 1 轮」——那是编一个看起来确定的数。
            Text(state.record.turnIndex.map { L("第 \($0 + 1) 轮", "Turn \($0 + 1)") } ?? L("第 — 轮", "Turn —"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}
