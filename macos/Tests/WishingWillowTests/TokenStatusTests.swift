import Testing
import Foundation
@testable import WishingWillow

/// Claude Code 状态图标（仿 iPhone Duo 的合一状态图标：外圈弧 / 中心扇形 / 底部四个点）。
///
/// 数据来自聊天记录 assistant 行的 message.usage。本机实测：同一条消息流式写成 2–5 行，
/// 每行的 usage 完全相同——不按 message.id 去重，输出 token 会被算成 2–5 倍。
/// 上下文占用的公式取自 Claude Code 自己的实现：input + cache_creation + cache_read。
@MainActor
@Suite("token 状态")
struct TokenStatusTests {
    private func row(_ id: String, input: Int, write: Int, read: Int, output: Int, model: String = "claude-opus-5") -> [String: Any] {
        ["type": "assistant", "timestamp": "2026-09-12T10:00:00.000Z",
         "message": ["id": id, "model": model,
                     "usage": ["input_tokens": input, "cache_creation_input_tokens": write,
                               "cache_read_input_tokens": read, "output_tokens": output],
                     "content": [["type": "text", "text": "x"]]]]
    }

    @Test("同一条消息重复写的行只算一次；上下文取最后一次请求；缓存命中 = 读 / 上下文；子代理里的不算")
    func usageDedupe() {
        var p = TurnProgress()
        let a = row("msg_a", input: 2, write: 1000, read: 99000, output: 300)
        p.ingest(a); p.ingest(a); p.ingest(a)
        p.ingest(row("msg_b", input: 5, write: 2495, read: 547500, output: 1200))
        var side = row("msg_side", input: 1, write: 1, read: 1, output: 99999)
        side["isSidechain"] = true
        p.ingest(side)

        #expect(p.requestCount == 2)
        #expect(p.outputTokens == 1500)
        #expect(p.lastUsage?.context == 550_000)
        #expect(abs((p.lastUsage?.cacheHit ?? 0) - 547_500.0 / 550_000.0) < 1e-9)
        #expect(p.model == "claude-opus-5")
    }

    @Test("上下文窗口：设置里写了 [1m] 或已经用过 20 万以上 → 1M；否则 20 万")
    func contextWindow() {
        #expect(ContextWindow.size(settingsModel: "opus[1m]", observed: 10_000) == 1_000_000)
        #expect(ContextWindow.size(settingsModel: "opus", observed: 550_000) == 1_000_000)
        #expect(ContextWindow.size(settingsModel: nil, observed: 150_000) == 200_000)
    }

    @Test("图标刻度：缓存命中 → 四个点亮几个；距最近一次写入 → 扇形亮几格；剩余上下文 → 外圈颜色")
    func glyphScales() {
        #expect(ClaudeStatus.dots(cacheHit: 0.98) == 4)
        #expect(ClaudeStatus.dots(cacheHit: 0.75) == 3)
        #expect(ClaudeStatus.dots(cacheHit: 0.5) == 2)
        #expect(ClaudeStatus.dots(cacheHit: 0.1) == 1)
        #expect(ClaudeStatus.dots(cacheHit: 0) == 0)

        #expect(ClaudeStatus.liveness(secondsSinceLastWrite: 3) == 1)
        #expect(ClaudeStatus.liveness(secondsSinceLastWrite: 40) == 2.0 / 3.0)
        #expect(ClaudeStatus.liveness(secondsSinceLastWrite: 200) == 1.0 / 3.0)
        #expect(ClaudeStatus.liveness(secondsSinceLastWrite: 900) == 0)

        #expect(ClaudeStatus.level(remaining: 0.45) == .normal)
        #expect(ClaudeStatus.level(remaining: 0.15) == .low)
        #expect(ClaudeStatus.level(remaining: 0.05) == .critical)
    }
}
