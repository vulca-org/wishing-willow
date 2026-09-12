import Foundation

/// 一次请求的 token 用量，取自聊天记录 assistant 行的 `message.usage`。
///
/// 本机实测：同一条消息流式写成 2–5 行，每行的 usage 完全相同。累计时必须按 message.id 去重，
/// 否则输出 token 会被算成 2–5 倍。
struct TokenUsage: Sendable, Equatable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0

    /// 上下文占用。公式与 Claude Code 自己的实现一致：它的状态栏数据里
    /// `total_input_tokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens`。
    var context: Int { input + cacheWrite + cacheRead }

    /// 这一次请求里有多少上下文是从缓存读的。
    var cacheHit: Double { context > 0 ? Double(cacheRead) / Double(context) : 0 }

    init(input: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheWrite = cacheWrite
        self.cacheRead = cacheRead
        self.output = output
    }

    init?(json: [String: Any]?) {
        guard let j = json else { return nil }
        func n(_ k: String) -> Int { (j[k] as? NSNumber)?.intValue ?? 0 }
        self.init(input: n("input_tokens"), cacheWrite: n("cache_creation_input_tokens"),
                  cacheRead: n("cache_read_input_tokens"), output: n("output_tokens"))
    }
}

/// 上下文窗口有多大。
///
/// 聊天记录里的模型名只写 `claude-opus-5`，不带 `[1m]`，从记录本身看不出窗口。
/// 依据两件读得到的事：设置里的 model（本机是 `opus[1m]`）；或者这个会话已经用过 20 万以上——那只可能是 1M 窗口。
/// 会话里用 /model 临时换过模型的情况读不到，界面上把窗口大小写出来，好让人核对。
enum ContextWindow {
    static func size(settingsModel: String?, observed: Int) -> Int {
        if settingsModel?.contains("[1m]") == true || observed > 200_000 { return 1_000_000 }
        return 200_000
    }

    static func settingsModel(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let url = home.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["model"] as? String
    }
}

/// 状态图标的刻度，仿 iPhone Duo 的合一状态图标：一个小圆里三种不同的形状，各走各的视觉通道——
/// 外圈连续弧 = 上下文还剩多少（像电量）；中心扇形 = 最近一次写入距今多久（像 Wi-Fi）；底部四个点 = 缓存命中（像信号格）。
enum ClaudeStatus {
    enum Level: Sendable, Equatable { case normal, low, critical }

    static func dots(cacheHit: Double) -> Int {
        if cacheHit >= 0.9 { return 4 }
        if cacheHit >= 0.7 { return 3 }
        if cacheHit >= 0.4 { return 2 }
        return cacheHit > 0 ? 1 : 0
    }

    static func liveness(secondsSinceLastWrite s: TimeInterval) -> Double {
        if s <= 10 { return 1 }
        if s <= 60 { return 2.0 / 3.0 }
        if s <= 300 { return 1.0 / 3.0 }
        return 0
    }

    /// 与 iPhone 电量的做法一致：低于 20% 变色，低于 10% 变红。上下文快满时 Claude Code 会自动压缩。
    static func level(remaining: Double) -> Level {
        if remaining <= 0.1 { return .critical }
        if remaining <= 0.2 { return .low }
        return .normal
    }

    struct Snapshot: Sendable, Equatable {
        var contextUsed: Int
        var window: Int
        var cacheHit: Double
        var outputTokens: Int
        var requests: Int
        var lastWrite: Date?

        var usedFraction: Double { window > 0 ? min(1, Double(contextUsed) / Double(window)) : 0 }
        var remaining: Double { 1 - usedFraction }
    }

    static func snapshot(_ p: TurnProgress?, settingsModel: String?) -> Snapshot? {
        guard let p, let last = p.lastUsage else { return nil }
        return Snapshot(contextUsed: last.context,
                        window: ContextWindow.size(settingsModel: settingsModel, observed: last.context),
                        cacheHit: last.cacheHit, outputTokens: p.outputTokens, requests: p.requestCount,
                        lastWrite: p.lastEventAt)
    }

    /// 552K、1M、11.8K、940。
    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 {
            let m = Double(n) / 1_000_000
            return m == m.rounded() ? "\(Int(m))M" : String(format: "%.1fM", m)
        }
        if n >= 10_000 { return "\(n / 1000)K" }
        if n >= 1000 { return String(format: "%.1fK", Double(n) / 1000) }
        return "\(n)"
    }
}
