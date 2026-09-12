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

    /// 只在有话说的时候占宽度。
    static func label(_ s: SessionState, _ seen: SeenStore) -> String? {
        if s.declaration == .unreadable { return "读不到输入" }
        guard seen.isUnread(s) else { return nil }
        return s.tag ?? s.workspace
    }
}
