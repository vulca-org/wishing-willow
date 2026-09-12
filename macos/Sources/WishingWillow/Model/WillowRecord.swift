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
    var turnIndex: Int?
    var updatedAt: Date?
    var prompt: String?
    var promptOrigin: PromptOrigin
    var decode: String?
    /// 模型自己压出来的 ≤6 字标签。刘海常亮层唯一放得下的东西。
    var tag: String?
    var endedAt: Date?
}

extension WillowRecord: Decodable {
    private enum CodingKeys: String, CodingKey {
        case schema, sessionId, pid, cwd, turnId, turnIndex, updatedAt, prompt, promptField, decode, tag, endedAt
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        sessionId = try c.decode(String.self, forKey: .sessionId)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        turnId = try c.decodeIfPresent(String.self, forKey: .turnId)
        turnIndex = try c.decodeIfPresent(Int.self, forKey: .turnIndex)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
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
