import Testing
import Foundation
@testable import WishingWillow

/// 形状用例。刻意手写，所以它们只能证明「我理解的形状自洽」——
/// 真值那一关在 LiveStateTests 里，对着磁盘上插件真正写出来的文件跑。
@Suite("状态文件解码")
struct RecordTests {

    private func decode(_ json: String) throws -> WillowRecord {
        try JSONDecoder().decode(WillowRecord.self, from: Data(json.utf8))
    }

    @Test("promptField 是字符串 → 读到了")
    func promptFieldNamed() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","prompt":"要什么","promptField":"prompt","decode":null}"#)
        #expect(r.promptOrigin == .field("prompt"))
        #expect(SessionState(record: r, now: .now).declaration == .undeclared)
    }

    @Test("promptField 存在但为 null → 插件坏了，不是模型没说话")
    func promptFieldNull() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","prompt":null,"promptField":null,"decode":null}"#)
        #expect(r.promptOrigin == .unreadable)
        #expect(SessionState(record: r, now: .now).declaration == .unreadable)
    }

    @Test("没有 promptField 这个键 → 旧 schema，不得报成「坏了」")
    func promptFieldAbsent() throws {
        let r = try decode(#"{"schema":1,"sessionId":"a","prompt":null,"decode":null}"#)
        #expect(r.promptOrigin == .absent)
        #expect(SessionState(record: r, now: .now).declaration == .awaiting)
    }

    @Test("两栏都有 → declared，并且 app 里没有任何地方判定它们是否一致")
    func declared() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","prompt":"找通用逻辑","promptField":"prompt","decode":"去审计那个仓库"}"#)
        #expect(SessionState(record: r, now: .now).declaration == .declared("去审计那个仓库"))
    }

    @Test("标签解码，且 ⚠ 只转发不重算")
    func tagAndFlag() throws {
        let r = try decode(#"{"schema":3,"sessionId":"a","prompt":"写封回信","promptField":"prompt","decode":"⚠ 起草那封信，起草不发送","tag":"起草回信"}"#)
        let st = SessionState(record: r, now: .now)
        #expect(st.tag == "起草回信")
        #expect(st.flaggedByModel == true)

        let plain = try decode(#"{"schema":3,"sessionId":"b","prompt":"写封回信","promptField":"prompt","decode":"起草那封信","tag":"起草回信"}"#)
        #expect(SessionState(record: plain, now: .now).flaggedByModel == false)
    }

    @Test("没有 tag 键的旧记录不得崩，也不得凭空造一个标签")
    func tagAbsent() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","prompt":"x 够长的一句请求","promptField":"prompt","decode":"读成了什么"}"#)
        #expect(SessionState(record: r, now: .now).tag == nil)
    }

    @Test("reminded=false 且无声明 → 这一轮没问，不是「问了没答」")
    func notAsked() throws {
        let skipped = try decode(#"{"schema":5,"sessionId":"a","prompt":"好的 继续吧","promptField":"prompt","reminded":false,"decode":null}"#)
        #expect(SessionState(record: skipped, now: .now).declaration == .notAsked)

        let asked = try decode(#"{"schema":5,"sessionId":"b","prompt":"一句够长需要提醒的请求","promptField":"prompt","reminded":true,"decode":null}"#)
        #expect(SessionState(record: asked, now: .now).declaration == .undeclared)

        let legacy = try decode(#"{"schema":2,"sessionId":"c","prompt":"旧记录没有 reminded 这一位","promptField":"prompt","decode":null}"#)
        #expect(SessionState(record: legacy, now: .now).declaration == .undeclared)
    }

    @Test("origin=system → 系统消息，不当成你批准的；字段说了算；旧记录只按两种信封头兜底")
    func systemOrigin() throws {
        let sys = try decode(#"{"schema":6,"sessionId":"a","prompt":"<task-notification>\n<task-id>x</task-id>","promptField":"prompt","origin":"system","reminded":false}"#)
        #expect(sys.isSystemMessage)
        #expect(PromptSource.describe(sys.prompt) == "后台任务通知")

        let user = try decode(#"{"schema":6,"sessionId":"b","prompt":"<task-notification> 这句是用户自己贴进来的","promptField":"prompt","origin":"user","reminded":true}"#)
        #expect(user.isSystemMessage == false)

        let legacy = try decode(#"{"schema":5,"sessionId":"c","prompt":"<task-notification>\n<task-id>y</task-id>","promptField":"prompt","reminded":false}"#)
        #expect(legacy.isSystemMessage)
    }

    @Test("回答进行中不是「问了没答」：turnEndedAt 键在且为 null → .inProgress；旧记录保持原判")
    func inProgress() throws {
        let running = try decode(#"{"schema":7,"sessionId":"a","prompt":"一句够长需要提醒的请求","promptField":"prompt","reminded":true,"decode":null,"turnEndedAt":null}"#)
        #expect(SessionState(record: running, now: .now).declaration == .inProgress)

        let ended = try decode(#"{"schema":7,"sessionId":"b","prompt":"一句够长需要提醒的请求","promptField":"prompt","reminded":true,"decode":null,"turnEndedAt":"2026-09-12T18:40:00.000Z"}"#)
        #expect(SessionState(record: ended, now: .now).declaration == .undeclared)

        let legacy = try decode(#"{"schema":6,"sessionId":"c","prompt":"旧记录没有 turnEndedAt","promptField":"prompt","reminded":true,"decode":null}"#)
        #expect(SessionState(record: legacy, now: .now).declaration == .undeclared)
    }

    @Test("空白的 decode 等于没有 decode")
    func blankDecode() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","prompt":"x 这是一句够长的请求","promptField":"prompt","decode":"   "}"#)
        #expect(SessionState(record: r, now: .now).declaration == .undeclared)
    }

    @Test("时间戳按插件写的形态解析（带毫秒的 ISO8601）")
    func timestamp() throws {
        let r = try decode(#"{"schema":2,"sessionId":"a","updatedAt":"2026-09-12T13:41:25.028Z","prompt":"x","promptField":"prompt"}"#)
        #expect(r.updatedAt != nil)
    }

    @Test("陈旧判定：三个信号任一成立即陈旧")
    func staleness() throws {
        let base = #"{"schema":2,"sessionId":"a","prompt":"x","promptField":"prompt","pid":%d,"updatedAt":"%@"}"#
        let nowStamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(.now)

        // 活进程 + 刚更新 → 不陈旧
        let live = try decode(String(format: base, Int(ProcessInfo.processInfo.processIdentifier), nowStamp))
        #expect(SessionState(record: live, now: .now).isStale == false)

        // 进程没了 → 陈旧（pid 1 之外的极大值几乎不可能存在）
        let dead = try decode(String(format: base, 999_999, nowStamp))
        #expect(SessionState(record: dead, now: .now).isStale == true)

        // 太久没更新 → 陈旧
        let old = try decode(String(format: base, Int(ProcessInfo.processInfo.processIdentifier), nowStamp))
        #expect(SessionState(record: old, now: .now.addingTimeInterval(SessionState.staleAfter + 60)).isStale == true)
    }

    @Test("半写入的文件不得让整个扫描崩掉")
    func malformed() {
        #expect(throws: (any Error).self) { try decode("{\"sessionId\":") }
    }
}
