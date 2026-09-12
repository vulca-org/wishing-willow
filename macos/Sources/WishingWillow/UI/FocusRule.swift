import SwiftUI

/// 常亮层显示「哪一个会话」的规则，菜单栏和灵动岛共用一份。
///
/// 两处各写一份，早晚会漂成两套 —— 这个项目要抓的正是这种事。
/// 全部按事实排序，没有一条按内容挑：插件坏了最优先，然后是「没看过且模型标了 ⚠」，
/// 然后是「没看过」，否则最近更新的那个。「已读」压过 ⚠：警报的任务是让你去看，
/// 你看过了它就该闭嘴。
@MainActor
enum FocusRule {
    static func live(_ store: WillowStore) -> [SessionState] {
        store.sessions.filter { !$0.isStale }
    }

    static func focus(_ store: WillowStore, _ seen: SeenStore) -> SessionState? {
        let l = live(store)
        return l.first { $0.declaration == .unreadable }
            ?? l.first { seen.isUnread($0) && $0.flaggedByModel }
            ?? l.first { seen.isUnread($0) }
            ?? l.first
    }

    static func others(_ store: WillowStore) -> Int { max(0, live(store).count - 1) }

    struct Label { let text: String; let carried: Bool }

    /// 只在有话说的时候占宽度。
    ///
    /// 这一轮没问（「好的 继续吧」）时，本轮没有标签，但任务通常还是上一轮那个。
    /// 用该会话**上一个真实写下的标签**，并标记为沿用，读方把它调暗 ——
    /// 不能把上一轮的解码冒充成这一轮的，也不该退回一个被截断的工作区名。
    static func label(_ s: SessionState, _ seen: SeenStore, _ store: WillowStore) -> Label? {
        if s.declaration == .unreadable { return Label(text: "读不到输入", carried: false) }
        guard seen.isUnread(s) else { return nil }
        if let t = s.tag { return Label(text: t, carried: false) }
        if s.declaration == .notAsked, let t = lastLoggedTag(s, store) {
            return Label(text: t, carried: true)
        }
        return Label(text: s.workspace, carried: false)
    }

    static func lastLoggedTag(_ s: SessionState, _ store: WillowStore) -> String? {
        TurnLog.read(sessionId: s.id, directory: store.directory)
            .last { ($0.tag ?? "").isEmpty == false }?.tag
    }
}
