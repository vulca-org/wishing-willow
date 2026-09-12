import SwiftUI

/// 常亮那一层。它必须小到和别的菜单栏图标一样不起眼，又要在该说话的时候说得清。
///
/// 颜色编的全是事实或转发，**没有一处在判定两栏是否一致**：
/// 红＝读不到输入，琥珀＝模型自己标了 ⚠，亮＝这一轮你还没看过，暗＝看过了。
/// 「未读」这个态是关键：实测 9/9 都写了声明，所以拿「没声明」当告警等于
/// 造了一个永远不亮的灯。而「你还没看过」每轮都成立，是事实，也不需要判断。
struct CompactLabel: View {
    let store: WillowStore
    let seen: SeenStore

    private var live: [SessionState] { store.sessions.filter { !$0.isStale } }

    /// 要显示的那一个。按事实排序，没有一条按内容挑：
    /// 插件坏了最优先，然后是「没看过且模型标了 ⚠」，然后是「没看过」，
    /// 否则最近更新的那个。
    private var focus: SessionState? {
        live.first { $0.declaration == .unreadable }
            ?? live.first { seen.isUnread($0) && $0.flaggedByModel }
            ?? live.first { seen.isUnread($0) }
            ?? live.first
    }

    private var others: Int { max(0, live.count - 1) }

    var body: some View {
        HStack(spacing: 4) {
            if let f = focus {
                Circle().fill(tint(f)).frame(width: 6, height: 6)
                if let t = label(for: f) {
                    Text(t)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if others > 0 {
                    Text("+\(others)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Image(systemName: "leaf")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .fixedSize()
    }

    /// 只在有话说的时候占宽度。**「已读」压过 ⚠**：警报的任务是让你去看，
    /// 你看过了它就该闭嘴 —— 一直亮着的警报会被学会忽略，而被忽略的警报
    /// 等于没有。插件坏了是例外，那不是对某一轮的判断，是工具本身不工作。
    private func label(for s: SessionState) -> String? {
        if s.declaration == .unreadable { return "读不到输入" }
        guard seen.isUnread(s) else { return nil }
        return s.tag ?? s.workspace
    }

    private func tint(_ s: SessionState) -> Color {
        if s.declaration == .unreadable { return .red }
        guard seen.isUnread(s) else { return .secondary }   // 看过了就安静
        return s.flaggedByModel ? .orange : .primary
    }
}
