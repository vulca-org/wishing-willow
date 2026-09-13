import Foundation

/// What a record means, derived fresh every time it is read.
///
/// Nothing here is written back to disk. The plugin deliberately stores no
/// status field: a status the hook can write is a status that can be wrong
/// while the declaration is missing, which restores the silence this whole
/// thing exists to break. The same rule applies on this side of the file.
struct SessionState: Identifiable, Sendable, Equatable {
    enum Declaration: Sendable, Equatable {
        case declared(String)   // 模型声明了，两栏都有
        case undeclared         // 有原话，模型没写声明 —— 这一态是产品的全部意义
        case unreadable         // hook 读不到本轮输入 —— 插件坏了，不是模型没说话
        case awaiting           // 还没有本轮原话（装插件时正好在一轮中间）
        case notAsked           // 这一轮压根没问（太短或是系统消息）—— 不是模型没说话
        case inProgress         // 问了，模型还在回答 —— 声明要等这一轮写出来
        case interrupted        // 你打断了这一轮 —— 不会有声明，也不会有 Stop
        case unverifiable       // 你在它干活时追加的一轮：之后写的理解聊天记录不存，核对不了 —— 不是没写
    }

    var id: String { record.sessionId }
    let record: WillowRecord
    let now: Date
    /// 实时读到的这一轮最后一次落盘时间。状态文件在一轮进行中不更新，
    /// 只看它的话，一轮超过 10 分钟就会被误判过期（今天实测最长一轮 1912 秒）。
    var liveLastEvent: Date? = nil
    /// 实时读到的打断时间。
    var liveInterruptedAt: Date? = nil
    /// 实时读到模型在等你选择。等待期间不落盘，不能按「10 分钟没动静」判过期（本机最长等过 1,357 秒）。
    var liveWaiting = false
    /// 聊天记录文件最后一次写入。插件只在你回车和一轮结束时写状态文件，Claude 在这之外干的活
    /// （后台任务通知、续跑）状态文件不知道——2026-09-13「项目最新剧本审阅」正在调工具，却被算成空闲。
    var transcriptWrittenAt: Date? = nil

    var prompt: String? { record.prompt }
    var tag: String? {
        guard let t = record.tag?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// 模型自己在解码行开头标了 ⚠，意思是它认为两栏不一致。
    ///
    /// 这是**转发**，不是判定。这个 app 里没有任何一处计算两栏是否一致 ——
    /// 让模型判自己的解码，等于让它用产生漂移的那套默认值再答一遍。
    /// 同理：已声明态不用绿色。绿色的意思是「检查过了，没问题」，而我们从不检查。
    var flaggedByModel: Bool {
        guard case .declared(let d) = declaration else { return false }
        return d.hasPrefix("⚠")
    }

    var declaration: Declaration {
        if record.prompt == nil {
            return record.promptOrigin == .unreadable ? .unreadable : .awaiting
        }
        if let d = record.decode, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .declared(d)
        }
        // 还在回答：插件在 Stop 时才写下 turnEndedAt。在那之前「没有声明」只说明模型还没答完，
        // 报成「问了，模型没写声明」就是每一轮开头都冒一次的假警报（用户 2026-09-12 实测抓到的橙色字）。
        // 放在「没问」前面：「继续吧」这类短句、后台任务通知开的一轮也是在跑——先前排在后面，这种轮次整轮显示「已结束 · 这一轮没问」，
        // 不读实时进度、没有「Claude 在做」，和 Claude Code 的「在跑」对不上（2026-09-13 实拍）。没问的事由理解那一栏单独说。
        if record.hasTurnEndMarker && record.turnEndedAt == nil {
            return liveInterruptedAt == nil ? .inProgress : .interrupted
        }
        // 「没问」和「问了没答」必须分开：把「好的 继续吧」报成「问了，模型没写声明」
        // 是一次假警报，而会被学会忽略的警报等于没有。旧记录没有这一位，保持原判。
        if record.reminded == false { return .notAsked }
        // 中途追加的一轮找不到理解，不等于没写：桌面端聊天记录不存夹在工具调用之间的文字（2026-09-13 实测）。
        // 报成橙色「问了没写」是假警报——两天里 5 条橙色全是这种。
        if record.midTurn == true { return .unverifiable }
        return .undeclared
    }

    /// Short label for the session rail: the last path component of `cwd`.
    var workspace: String {
        guard let cwd = record.cwd, !cwd.isEmpty else { return record.sessionId.prefix(8).description }
        return (cwd as NSString).lastPathComponent
    }

    /// Older than this with no update, and we stop claiming to know anything.
    static let staleAfter: TimeInterval = 10 * 60

    /// Computed, never stored. Two independent signals, because either alone lies:
    /// a process can die without touching the file, and a live session can sit
    /// idle for an hour.
    var isStale: Bool {
        if record.endedAt != nil { return true }
        if let pid = record.pid, !Self.processIsAlive(pid) { return true }
        if liveWaiting { return false }
        if isRunning { return false }          // Claude Code 说在跑的，跑长工具不写记录也照样显示
        guard let updated = [record.updatedAt, liveLastEvent, transcriptWrittenAt].compactMap({ $0 }).max() else { return true }
        return now.timeIntervalSince(updated) > Self.staleAfter
    }

    /// 进程还开着、会话没结束——不管最近有没有动静。
    var isOpen: Bool {
        guard record.endedAt == nil, let pid = record.pid else { return false }
        return Self.processIsAlive(pid)
    }

    /// 在跑，口径和 Claude Code 自己的一致：进程开着、这一轮还没结束（插件在 Stop 时才写 turnEndedAt）。
    ///
    /// 2026-09-13 对照 Claude Code 会话列表的 `isRunning`：本机 4 个在跑，与「这一轮没结束」逐个对上。
    /// 先前按「最近 10 分钟有动静」算——刚答完几分钟的算成在跑，跑长工具不写记录的算成空闲，用户说和 Claude Code 对不上。
    /// 一轮开着却一小时没有任何动静，多半是 Stop 钩子没跑到（插件被停用、钩子报错），不再算在跑。
    var isRunning: Bool {
        // 看轮次标记，不看 declaration：「继续吧」这类短句和后台任务通知在 declaration 里是「没问」，轮次照样开着。
        // 用 declaration == .inProgress 会把它们算成空闲（2026-09-13 实拍：SIGIR 会话这一轮开着，面板写「这一轮没问」、计数少算一个）。
        guard isOpen, record.hasTurnEndMarker, record.turnEndedAt == nil, liveInterruptedAt == nil else { return false }
        guard let last = [record.updatedAt, liveLastEvent, transcriptWrittenAt].compactMap({ $0 }).max() else { return false }
        return now.timeIntervalSince(last) < Self.stuckAfter
    }

    static let stuckAfter: TimeInterval = 60 * 60

    var age: TimeInterval? {
        guard let updated = record.updatedAt else { return nil }
        return now.timeIntervalSince(updated)
    }

    /// `kill(pid, 0)` asks the kernel without sending anything. EPERM means the
    /// process exists and belongs to someone else — still alive.
    static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
