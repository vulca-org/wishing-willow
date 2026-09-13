import Testing
import Foundation
@testable import WishingWillow

/// 展开态右耳两个位置：左边标签位（这一轮在做什么）、右边阶段位（思考中 / 回答中 / 已结束…）。
/// 用户 2026-09-13 悬停时看到两个「思考中」：标签位没有标签时退回了状态词。
@MainActor
@Suite("展开态右耳文字")
struct EarTextTests {
    init() { Lang.current = .zh }

    @Test("进行中还没写出标签：标签位与阶段位不是同一句，标签位标为沿用")
    func noDuplicate() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("willow-ear-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let obj: [String: Any] = ["schema": 9, "sessionId": "s", "pid": Int(ProcessInfo.processInfo.processIdentifier),
                                  "cwd": "/x/a", "turnId": "t1", "updatedAt": iso.format(Date()),
                                  "prompt": "一句够长的请求", "promptField": "prompt", "origin": "user",
                                  "reminded": true, "decode": NSNull(), "turnEndedAt": NSNull()]
        try JSONSerialization.data(withJSONObject: obj).write(to: d.appendingPathComponent("s.json"))
        let store = WillowStore(directory: d)
        store.reload()
        let s = try #require(store.sessions.first)
        #expect(s.declaration == .inProgress)
        let seen = SeenStore(ephemeral: true)
        let tag = IslandExpandedContent.earTag(s, store: store, seen: seen)
        #expect(tag.text != IslandExpandedContent.phaseWord(s, store: store))
        #expect(tag.carried)
    }
}
