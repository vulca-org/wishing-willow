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
                row(label: "这一轮", text: "系统消息（\(PromptSource.describe(state.prompt))），不是你说的", tone: .secondary)
            } else {
                row(label: "你批准的", text: state.prompt, tone: .primary)
            }

            switch state.declaration {
            case .declared(let d):
                row(label: "我读成了", text: d, tone: .primary)
            case .undeclared:
                banner(
                    icon: "circle.dotted",
                    title: "本轮未声明",
                    detail: "模型没有写出它把这个请求读成了什么。缺席本身就是信号。",
                    tint: .yellow
                )
            case .unreadable:
                banner(
                    icon: "exclamationmark.triangle.fill",
                    title: "读不到本轮输入",
                    detail: "hook 跑了，但拿不到你说的话 —— 这是插件坏了，不是模型没说话。",
                    tint: .red
                )
            case .awaiting:
                banner(
                    icon: "hourglass",
                    title: "等第一轮",
                    detail: "插件是在这一轮中间装上的，下一轮开始记录。",
                    tint: .secondary
                )
            case .interrupted:
                banner(
                    icon: "arrow.uturn.backward",
                    title: "你撤回了这一轮",
                    detail: "打断不会写出声明。",
                    tint: .secondary
                )
            case .inProgress:
                banner(
                    icon: "ellipsis",
                    title: "模型正在回答",
                    detail: "声明要等这一轮写出来才读得到。",
                    tint: .secondary
                )
            case .notAsked:
                banner(
                    icon: "text.bubble",
                    title: "这一轮没问",
                    detail: "太短或是系统消息，插件没有注入提醒 —— 不是模型没说话。",
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
        Text("这个会话已经不活跃了，下面是它最后一轮的样子。")
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
            Text(state.record.turnIndex.map { "第 \($0 + 1) 轮" } ?? "第 — 轮")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }
}
