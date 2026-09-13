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
        let rules: [(SessionState) -> Bool] = [
            { $0.declaration == .unreadable },
            // 模型停下来等你选：唯一一种「你不回去它就一直等」的状态，排在所有提示前面。
            { store.progress(for: $0)?.pendingChoice != nil },
            { store.recentWithdraw[$0.id] != nil },
            { seen.isUnread($0) && $0.flaggedByModel },
            { seen.isUnread($0) },
        ]
        for rule in rules { if let hit = l.first(where: rule) { return hit } }
        return l.first
    }

    static func others(_ store: WillowStore) -> Int { max(0, live(store).count - 1) }

    /// 第二个会话：进分离胶囊的那个。HIG 的多活动做法——一个贴着摄像头占两翼，另一个分离成小胶囊。
    /// 只挑有话说的：看过且空闲的会话不占胶囊，胶囊里放一个 logo 等于没放。
    static func secondary(_ store: WillowStore, _ seen: SeenStore, primary: SessionState?) -> SessionState? {
        let l = live(store).filter { $0.id != primary?.id }
        let rules: [(SessionState) -> Bool] = [
            { $0.declaration == .unreadable },
            { store.progress(for: $0)?.pendingChoice != nil },
            { store.recentWithdraw[$0.id] != nil },
            { $0.declaration == .inProgress },
            { pill($0, seen, store) != nil },
        ]
        for rule in rules { if let hit = l.first(where: rule) { return hit } }
        return nil
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

    /// 并行计数。在跑 = 最近 10 分钟有动静（灵动岛上展示的那些）；空闲 = 进程还开着、但超过 10 分钟没动静。
    ///
    /// 先前胶囊上写「+N」、展开态写「另有 N 个」，N 是主会话与胶囊之外的数：3 个并行时显示「+1」。
    /// 用户读成「一共只多一个」（2026-09-13）——胶囊里那个本身就是另一个，没人这么数；
    /// 而且开着但空闲的会话（本机当时 2 个）哪儿都不显示。改为说总数，空闲的单独说。
    static func parallel(_ store: WillowStore) -> (running: Int, idle: Int) {
        (live(store).count, store.sessions.filter { $0.isStale && $0.isOpen }.count)
    }

    static func parallelSummary(running: Int, idle: Int) -> String {
        let head = running <= 1 ? "只有这一个在跑" : "共 \(running) 个会话在跑"
        return idle > 0 ? "\(head) · \(idle) 个空闲" : head
    }

    /// 胶囊后面叠几层：主会话占两翼、胶囊是第二个，再往后还在跑的每个叠一层，最多画 2 层。
    static func stackLayers(running: Int) -> Int { min(2, max(0, running - 2)) }

    /// 主会话与胶囊之外还在跑的会话数（界面上不再直接写成「+N」）。
    static func extra(_ store: WillowStore, primary: SessionState?, secondary: SessionState?) -> Int {
        live(store).filter { $0.id != primary?.id && $0.id != secondary?.id }.count
    }

    /// 胶囊里放什么。宽度只够一个符号加两三个字，所以是枚举，不是一句话。
    enum Pill: Equatable {
        case broken
        case choice(plan: Bool, since: Date?)
        case withdraw(interrupted: Bool)
        case running(since: Date?)
        case fresh(tag: String?, flagged: Bool)
        case silent
    }

    static func pill(_ s: SessionState, _ seen: SeenStore, _ store: WillowStore) -> Pill? {
        if s.declaration == .unreadable { return .broken }
        if let c = store.progress(for: s)?.pendingChoice { return .choice(plan: c.kind == .plan, since: c.at) }
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
        if let c = store.progress(for: s)?.pendingChoice {        // 看过也照样显示：它在等你
            return Label(text: c.kind == .plan ? "等你批准" : "等你选择", carried: false)
        }
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
