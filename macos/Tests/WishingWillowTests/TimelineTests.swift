import Testing
import Foundation
@testable import WishingWillow

/// 展开态的刻度尺画「这一轮」：从按回车到声明写出、到结束。
/// 两件事要钉住：插件在 Stop 时把 updatedAt 改写成结束时刻，起点必须在进行中记下；
/// 结束前最后不到一秒写下的行，结束时要补读，否则刻度尺少画步骤。
@MainActor
@Suite("这一轮的时间线")
struct TimelineTests {
    private let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private func append(_ url: URL, _ line: String) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data((line + "\n").utf8))
        try h.close()
    }

    @Test("一轮结束后留下时间线：起点是按回车那一刻，终点是结束时刻，结束前最后写下的步骤也补读进来")
    func finishedTimeline() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("willow-timeline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let t = d.appendingPathComponent("s.transcript.jsonl")
        let prev = #"{"type":"assistant","timestamp":"2026-09-12T09:00:00.000Z","message":{"content":[{"type":"text","text":"上一轮。"}]}}"# + "\n"
        try Data(prev.utf8).write(to: t)
        let now = Date()
        let started = now.addingTimeInterval(-60), ended = now.addingTimeInterval(-5)
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let state = d.appendingPathComponent("s.json")
        var record: [String: Any] = ["schema": 9, "sessionId": "s", "pid": pid, "cwd": "/x/a", "turnId": "t1",
                                     "updatedAt": iso.format(started), "prompt": "一句够长的请求",
                                     "promptField": "prompt", "origin": "user", "reminded": true, "decode": NSNull(),
                                     "turnEndedAt": NSNull(), "transcriptPath": t.path, "transcriptOffset": prev.utf8.count]
        try JSONSerialization.data(withJSONObject: record).write(to: state)

        let declared = now.addingTimeInterval(-50)
        try append(t, "{\"type\":\"assistant\",\"timestamp\":\"\(iso.format(declared))\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"你批准的：x\\n我读成了：读成了什么\\n标签：改刻度尺\"}]}}")
        let store = WillowStore(directory: d)
        store.reload()
        let first = try #require(store.sessions.first)
        let live = try #require(store.timeline(for: first))
        #expect(live.endedAt == nil)
        #expect(live.progress.declaredAt != nil)
        #expect(live.progress.steps.isEmpty)

        // 结束前写下一次工具调用，app 还没来得及读，Stop 就把状态文件改成结束
        try append(t, "{\"type\":\"assistant\",\"timestamp\":\"\(iso.format(now.addingTimeInterval(-8)))\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"tu1\",\"name\":\"Bash\",\"input\":{\"description\":\"Run tests\"}}]}}")
        record["decode"] = "读成了什么"; record["tag"] = "改刻度尺"
        record["turnEndedAt"] = iso.format(ended); record["updatedAt"] = iso.format(ended)
        try JSONSerialization.data(withJSONObject: record).write(to: state)
        store.reload()

        let s = try #require(store.sessions.first)
        #expect(s.declaration == .declared("读成了什么"))
        let done = try #require(store.timeline(for: s))
        #expect(abs(done.startedAt.timeIntervalSince(started)) < 0.01)
        #expect(abs((done.endedAt ?? .distantPast).timeIntervalSince(ended)) < 0.01)
        #expect(done.progress.steps.count == 1)
    }

    @Test("刻度步长：主刻度间隔不小于约 64pt，按总时长取整数秒")
    func majorStep() {
        #expect(TimelineRuler.majorStep(total: 57, width: 464) == 10)
        #expect(TimelineRuler.majorStep(total: 352, width: 464) == 60)
        #expect(TimelineRuler.majorStep(total: 1912, width: 464) == 300)
    }
}
