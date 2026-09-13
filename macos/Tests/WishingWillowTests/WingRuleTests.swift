import Testing
import Foundation
@testable import WishingWillow

/// 两翼显示什么，用户实测指出过两处问题：左翼「+1」看不懂，右翼退回被截断的工作区名。
@MainActor
@Suite("两翼显示规则")
struct WingRuleTests {
    init() { Lang.current = .zh }

    private func state(_ json: String) throws -> SessionState {
        SessionState(record: try JSONDecoder().decode(WillowRecord.self, from: Data(json.utf8)), now: .now)
    }

    @Test("回答中→「回答中」；看过了→缩回；没写声明→「没写声明」；有标签→标签；无标签→「有新声明」；绝不显示工作区名")
    func rules() throws {
        let store = WillowStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("willow-wing-\(UUID().uuidString)"))
        let seen = SeenStore(ephemeral: true)
        let cwd = #""cwd":"/x/twitter-content-review-07e443""#

        let running = try state(#"{"schema":8,"sessionId":"a",\#(cwd),"turnId":"t1","prompt":"一句够长的请求","promptField":"prompt","origin":"user","reminded":true,"decode":null,"turnEndedAt":null}"#)
        #expect(FocusRule.label(running, seen, store)?.text == "回答中")

        let declared = try state(#"{"schema":8,"sessionId":"b",\#(cwd),"turnId":"t2","prompt":"一句够长的请求","promptField":"prompt","origin":"user","reminded":true,"decode":"读成了什么","tag":"改岛动效","turnEndedAt":"2026-09-12T19:00:00.000Z"}"#)
        #expect(FocusRule.label(declared, seen, store)?.text == "改岛动效")
        seen.markSeen(sessionId: "b", turnId: "t2")
        #expect(FocusRule.label(declared, seen, store) == nil)

        let undeclared = try state(#"{"schema":8,"sessionId":"c",\#(cwd),"turnId":"t3","prompt":"一句够长的请求","promptField":"prompt","origin":"user","reminded":true,"decode":null,"turnEndedAt":"2026-09-12T19:00:00.000Z"}"#)
        #expect(FocusRule.label(undeclared, seen, store)?.text == "没写声明")

        let noTag = try state(#"{"schema":8,"sessionId":"d",\#(cwd),"turnId":"t4","prompt":"一句够长的请求","promptField":"prompt","origin":"user","reminded":true,"decode":"读成了","turnEndedAt":"2026-09-12T19:00:00.000Z"}"#)
        #expect(FocusRule.label(noTag, seen, store)?.text == "有新声明")

        // 撤回：没有近期撤回事件时，被打断的这一轮两翼缩回刘海；有事件时短暂显示「已撤回」「撤回排队」
        let rec = try JSONDecoder().decode(WillowRecord.self, from: Data(#"{"schema":9,"sessionId":"e",\#(cwd),"turnId":"t5","prompt":"一句够长的请求","promptField":"prompt","origin":"user","reminded":true,"decode":null,"turnEndedAt":null}"#.utf8))
        let interrupted = SessionState(record: rec, now: .now, liveInterruptedAt: .now)
        #expect(interrupted.declaration == .interrupted)
        #expect(FocusRule.label(interrupted, seen, store) == nil)
        store.noteWithdraw(sessionId: "e", kind: .interrupted)
        #expect(FocusRule.label(interrupted, seen, store)?.text == "已撤回")
        store.noteWithdraw(sessionId: "a", kind: .queued)
        #expect(FocusRule.label(running, seen, store)?.text == "撤回排队")

        for s in [running, declared, undeclared, noTag] {
            #expect(FocusRule.label(s, seen, store)?.text.contains("twitter") != true)
        }
    }
}
