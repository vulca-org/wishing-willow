import Foundation

/// One session's state file, exactly as the plugin writes it.
///
/// The reader never writes these files. Everything derived — whether the model
/// declared, whether the session is still alive — is computed here and thrown
/// away, never stored. A stored derivation is a derivation that can be stale
/// while looking authoritative.
struct WillowRecord: Sendable, Equatable {
    /// Where the prompt came from, which is not the same question as what it says.
    ///
    /// The distinction exists because the plugin has already shipped a version
    /// that read the wrong input field, captured nothing, and exited 0 — and a
    /// silent plugin looks exactly like a plugin with nothing to report. When
    /// the key is present and null, the hook ran and could not read the input.
    enum PromptOrigin: Sendable, Equatable {
        case field(String)   // 读到了，来自这个键
        case unreadable      // 键在，值是 null —— hook 读不到本轮输入
        case absent          // 键不在（schema 1，或 Stop 在没有 capture 的情况下兜底写的）
    }

    var schema: Int
    var sessionId: String
    var pid: Int32?
    var cwd: String?
    var turnId: String?
    /// 本轮聊天记录的路径与提交时的字节长度——app 从这里往后实时读这一轮。
    var transcriptPath: String?
    var transcriptOffset: Int?
    var turnIndex: Int?
    var updatedAt: Date?
    var prompt: String?
    var promptOrigin: PromptOrigin
    /// 这一轮插件到底有没有注入提醒。缺了它，「没问」和「问了没答」是同一行。
    var reminded: Bool?
    /// 原话的来历：`user` / `system`。插件写下的事实，读方照它显示。
    var origin: String?
    var decode: String?
    /// 模型自己压出来的 ≤6 字标签。刘海常亮层唯一放得下的东西。
    var tag: String?
    /// 这一轮什么时候结束的。插件在 Stop 时写下；null = 还在回答。
    var turnEndedAt: Date?
    /// 记录里有没有 `turnEndedAt` 这个键。旧记录没有，没法区分「在回答」和「答完了」。
    var hasTurnEndMarker: Bool
    var endedAt: Date?
}

extension WillowRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case schema, sessionId, pid, cwd, turnId, transcriptPath, transcriptOffset, turnIndex, updatedAt, prompt, promptField, reminded, origin, decode, tag, turnEndedAt, endedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        sessionId = try c.decode(String.self, forKey: .sessionId)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        turnId = try c.decodeIfPresent(String.self, forKey: .turnId)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        transcriptOffset = try c.decodeIfPresent(Int.self, forKey: .transcriptOffset)
        turnIndex = try c.decodeIfPresent(Int.self, forKey: .turnIndex)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        reminded = try c.decodeIfPresent(Bool.self, forKey: .reminded)
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        decode = try c.decodeIfPresent(String.self, forKey: .decode)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)

        // `decodeIfPresent` returns nil for both "key missing" and "key is null",
        // and those two mean different things here — so ask the container directly.
        if c.contains(.promptField) {
            if let name = try c.decodeIfPresent(String.self, forKey: .promptField) {
                promptOrigin = .field(name)
            } else {
                promptOrigin = .unreadable
            }
        } else {
            promptOrigin = .absent
        }

        hasTurnEndMarker = c.contains(.turnEndedAt)
        turnEndedAt = try Self.date(c, .turnEndedAt)
        updatedAt = try Self.date(c, .updatedAt)
        endedAt = try Self.date(c, .endedAt)
    }

    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> Date? {
        guard let s = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return Self.parseISO8601(s)
    }

    /// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the latter is
    /// a class with shared mutable state and cannot be a shared constant under
    /// Swift 6 concurrency checking.
    static func parseISO8601(_ s: String) -> Date? {
        // 插件写的是 `new Date().toISOString()`，总带毫秒；另一种形态留个退路。
        if let d = try? Date(s, strategy: .iso8601.year().month().day()
            .dateTimeSeparator(.standard).time(includingFractionalSeconds: true)) { return d }
        return try? Date(s, strategy: .iso8601)
    }
}

/// 原话是不是系统塞进来的。
///
/// 新记录：插件写下的 `origin` 说了算，**不按内容猜**——用户自己贴一段
/// `<task-notification>` 进来，那仍然是用户说的话。
/// 旧记录（没有 `origin` 这一位）：只认两种最常见的信封头兜底。完整规则只在插件里有一份，
/// 读方不维护第二份——这个兜底随旧记录消失而失效，是有意的。
enum PromptSource {
    static func isSystem(origin: String?, prompt: String?) -> Bool {
        if let origin { return origin == "system" }
        guard let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return p.hasPrefix("<task-notification") || p.hasPrefix("[SYSTEM NOTIFICATION")
    }

    static func describe(_ prompt: String?) -> String {
        let p = prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.hasPrefix("<task-notification") ? L("后台任务通知", "background task notice") : L("系统消息", "system message")
    }
}

extension WillowRecord {
    var isSystemMessage: Bool { PromptSource.isSystem(origin: origin, prompt: prompt) }
}
