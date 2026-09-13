import Testing
import Foundation
@testable import WishingWillow

/// 多任务并行时的计数与文案。用户 2026-09-13：3 个以上并行时界面仍写「+1」「另有 1 个」。
/// 查实：计数没错（主会话、胶囊之外还剩 1 个），但读法对不上；另有 2 个开着但空闲的会话哪儿都没显示。
@MainActor
@Suite("并行计数")
struct ParallelCountTests {
    init() { Lang.current = .zh }

    @Test("在跑 = 最近 10 分钟有动静；空闲 = 进程开着但没动静；结束的、进程没了的都不算")
    func counts() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("willow-par-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        func write(_ id: String, pid: Int, ago: TimeInterval, ended: Bool = false) throws {
            var obj: [String: Any] = ["schema": 9, "sessionId": id, "pid": pid, "cwd": "/x/\(id)", "turnId": "t-\(id)",
                                      "updatedAt": iso.format(Date().addingTimeInterval(-ago)),
                                      "prompt": "一句够长的请求", "promptField": "prompt", "origin": "user",
                                      "reminded": true, "decode": "读成了", "tag": "标签\(id)",
                                      "turnEndedAt": iso.format(Date().addingTimeInterval(-ago))]
            if ended { obj["endedAt"] = iso.format(Date()) }
            try JSONSerialization.data(withJSONObject: obj).write(to: d.appendingPathComponent("\(id).json"))
        }
        for id in ["a", "b", "c", "d"] { try write(id, pid: me, ago: 20) }
        try write("idle", pid: me, ago: 3600)
        try write("gone", pid: me, ago: 20, ended: true)
        try write("dead", pid: 99_999_999, ago: 20)

        let store = WillowStore(directory: d)
        store.reload()
        let par = FocusRule.parallel(store)
        #expect(par.running == 4)
        #expect(par.idle == 1)
    }

    @Test("文案说总数：不写「+N」「另有 N 个」")
    func copy() {
        #expect(FocusRule.parallelSummary(running: 1, idle: 0) == "只有这一个在跑")
        #expect(FocusRule.parallelSummary(running: 3, idle: 0) == "共 3 个会话在跑")
        #expect(FocusRule.parallelSummary(running: 3, idle: 2) == "共 3 个会话在跑 · 2 个空闲")
    }
}
