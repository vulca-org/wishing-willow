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

    static func focus(_ store: WillowStore, _ seen: SeenStore, pinned: String? = nil) -> SessionState? {
        let l = live(store)
        // 钉住的会话优先：声明到达或撤回时，展开的必须是那个会话，不是排第一的。
        if let pinned, let p = l.first(where: { $0.id == pinned }) { return p }
        return l.first { $0.declaration == .unreadable }
            ?? l.first { store.recentWithdraw[$0.id] != nil }
            ?? l.first { seen.isUnread($0) && $0.flaggedByModel }
            ?? l.first { seen.isUnread($0) }
            ?? l.first
    }

    static func others(_ store: WillowStore) -> Int { max(0, live(store).count - 1) }

    /// 第二个会话：进分离胶囊的那个。HIG 的多活动做法——一个贴着摄像头占两翼，另一个分离成小胶囊。
    /// 只挑有话说的：看过且空闲的会话不占胶囊，胶囊里放一个 logo 等于没放。
    static func secondary(_ store: WillowStore, _ seen: SeenStore, primary: SessionState?) -> SessionState? {
        let l = live(store).filter { $0.id != primary?.id }
        return l.first { $0.declaration == .unreadable }
            ?? l.first { store.recentWithdraw[$0.id] != nil }
            ?? l.first { $0.declaration == .inProgress }
            ?? l.first { pill($0, seen, store) != nil }
    }

    /// 收起态的一对：主会话占两翼，第二个进胶囊。
    /// 主会话无话可说（看过且空闲）而另一个有话说时，把那个提成主会话——
    /// 否则屏幕上是一个缩回的空刘海加一个挤在旁边的小胶囊。钉住的不提换。
    static func pair(_ store: WillowStore, _ seen: SeenStore, pinned: String?) -> (primary: SessionState?, secondary: SessionState?) {
        let p = focus(store, seen, pinned: pinned)
        let s = secondary(store, seen, primary: p)
        if pinned == nil, let p, label(p, seen, store) == nil, let s {
            return (s, secondary(store, seen, primary: s))
        }
        return (p, s)
    }

    /// 主会话与胶囊之外还在跑的会话数，胶囊上写成「+N」。
    static func extra(_ store: WillowStore, primary: SessionState?, secondary: SessionState?) -> Int {
        live(store).filter { $0.id != primary?.id && $0.id != secondary?.id }.count
    }

    /// 胶囊里放什么。宽度只够一个符号加两三个字，所以是枚举，不是一句话。
    enum Pill: Equatable {
        case broken
        case withdraw(interrupted: Bool)
        case running(since: Date?)
        case fresh(tag: String?, flagged: Bool)
        case silent
    }

    static func pill(_ s: SessionState, _ seen: SeenStore, _ store: WillowStore) -> Pill? {
        if s.declaration == .unreadable { return .broken }
        if let w = store.recentWithdraw[s.id] { return .withdraw(interrupted: w.kind == .interrupted) }
        if s.declaration == .inProgress { return .running(since: s.record.updatedAt) }
        guard seen.isUnread(s) else { return nil }
        if s.declaration == .undeclared { return .silent }
        if case .declared = s.declaration { return .fresh(tag: s.tag, flagged: s.flaggedByModel) }
        return nil
    }

    struct Label { let text: String; let carried: Bool }

    /// 只在有话说的时候占宽度。
    ///
    /// 这一轮没问（「好的 继续吧」）时，本轮没有标签，但任务通常还是上一轮那个。
    /// 用该会话**上一个真实写下的标签**，并标记为沿用，读方把它调暗 ——
    /// 不能把上一轮的解码冒充成这一轮的，也不该退回一个被截断的工作区名。
    static func label(_ s: SessionState, _ seen: SeenStore, _ store: WillowStore) -> Label? {
        if s.declaration == .unreadable { return Label(text: "读不到输入", carried: false) }
        if let w = store.recentWithdraw[s.id] {
            return Label(text: w.kind == .interrupted ? "已撤回" : "撤回排队", carried: true)
        }
        if s.declaration == .interrupted { return nil }       // 撤回提示过后缩回刘海
        // 回答中：声明还没有，就老实说在回答。先前退回工作区名，截断成「twitter-cont…」，没有信息。
        if s.declaration == .inProgress {
            let p = store.progress(for: s)
            if let t = p?.tag { return Label(text: t, carried: false) }      // 声明刚写出——临时标签
            if p?.decode != nil { return Label(text: "有新声明", carried: false) }
            if let p, p.firstWriteAt == nil { return Label(text: "思考中", carried: true) }
            return Label(text: "回答中", carried: true)
        }
        guard seen.isUnread(s) else { return nil }          // 看过了 → 两翼缩回刘海，不遮东西
        if s.declaration == .undeclared { return Label(text: "没写声明", carried: false) }
        if let t = s.tag { return Label(text: t, carried: false) }
        if s.declaration == .notAsked, let t = lastLoggedTag(s, store) {
            return Label(text: t, carried: true)
        }
        if case .declared = s.declaration { return Label(text: "有新声明", carried: false) }
        return nil                                          // 绝不退回工作区名
    }

    static func lastLoggedTag(_ s: SessionState, _ store: WillowStore) -> String? {
        TurnLog.read(sessionId: s.id, directory: store.directory)
            .last { ($0.tag ?? "").isEmpty == false }?.tag
    }
}
