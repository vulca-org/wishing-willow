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
        // 「没问」和「问了没答」必须分开：把「好的 继续吧」报成「问了，模型没写声明」
        // 是一次假警报，而会被学会忽略的警报等于没有。旧记录没有这一位，保持原判。
        if record.reminded == false { return .notAsked }
        // 还在回答：插件在 Stop 时才写下 turnEndedAt。在那之前「没有声明」只说明模型还没答完，
        // 报成「问了，模型没写声明」就是每一轮开头都冒一次的假警报（用户 2026-09-12 实测抓到的橙色字）。
        if record.hasTurnEndMarker && record.turnEndedAt == nil {
            return liveInterruptedAt == nil ? .inProgress : .interrupted
        }
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
        guard let updated = [record.updatedAt, liveLastEvent].compactMap({ $0 }).max() else { return true }
        return now.timeIntervalSince(updated) > Self.staleAfter
    }

    /// 进程还开着、会话没结束——不管最近有没有动静。「空闲」= 开着但陈旧。
    var isOpen: Bool {
        guard record.endedAt == nil, let pid = record.pid else { return false }
        return Self.processIsAlive(pid)
    }

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
