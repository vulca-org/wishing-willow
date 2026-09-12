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
    }

    var id: String { record.sessionId }
    let record: WillowRecord
    let now: Date

    var prompt: String? { record.prompt }

    var declaration: Declaration {
        if record.prompt == nil {
            return record.promptOrigin == .unreadable ? .unreadable : .awaiting
        }
        if let d = record.decode, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .declared(d)
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
        guard let updated = record.updatedAt else { return true }
        return now.timeIntervalSince(updated) > Self.staleAfter
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
