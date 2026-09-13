import Testing
import Foundation
import CoreGraphics
@testable import WishingWillow

/// 用户 2026-09-13 定的两处修正，加菜单栏让路。
/// ① 中途追加：你在 Claude 干活时发的消息，Claude Code 在同一轮里交给 Claude；之后写的理解夹在工具调用之间，
///    桌面端聊天记录不存——找不到不等于没写 → 灰色「无法核对」，不是橙色「没写声明」。排队消息被送达也不再算撤回。
/// ② 在跑判定：状态文件之外，也看聊天记录最后一次写入。
/// ③ 菜单栏自动隐藏：鼠标碰到顶边（不在灵动岛上）时，收起态灵动岛往下让出一条菜单栏的高度。
@MainActor
@Suite("中途追加、在跑判定与菜单栏让路")
struct MidTurnAndDodgeTests {
    init() { Lang.current = .zh }

    private let iso = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private func dir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("willow-midturn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func record(_ extra: [String: Any], id: String, ago: TimeInterval = 20) -> [String: Any] {
        var obj: [String: Any] = ["schema": 10, "sessionId": id, "pid": Int(ProcessInfo.processInfo.processIdentifier),
                                  "cwd": "/x/\(id)", "turnId": "t-\(id)",
                                  "updatedAt": iso.format(Date().addingTimeInterval(-ago)),
                                  "prompt": "提交吧，然后 README 改用收起态直接点开录素材。", "promptField": "prompt",
                                  "origin": "user", "reminded": true, "decode": NSNull(), "tag": NSNull(),
                                  "turnEndedAt": iso.format(Date().addingTimeInterval(-ago)), "midTurn": false]
        obj.merge(extra) { $1 }
        return obj
    }

    private func write(_ obj: [String: Any], _ name: String, in d: URL) throws {
        try JSONSerialization.data(withJSONObject: obj).write(to: d.appendingPathComponent(name))
    }

    @Test("中途追加的一轮找不到理解 → 无法核对（灰、沿用态）；不是中途追加的照旧是没写声明")
    func unverifiable() throws {
        let d = try dir()
        try write(record(["midTurn": true], id: "mid"), "mid.json", in: d)
        try write(record([:], id: "plain"), "plain.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        let seen = SeenStore(ephemeral: true)
        let mid = try #require(store.sessions.first { $0.id == "mid" })
        let plain = try #require(store.sessions.first { $0.id == "plain" })
        #expect(mid.declaration == .unverifiable)
        #expect(plain.declaration == .undeclared)
        let label = try #require(FocusRule.label(mid, seen, store))
        #expect(label.text == "无法核对")
        #expect(label.carried == true)
        #expect(StatusCenter.of(mid, progress: nil, withdrawn: false) == .idle)
        #expect(FocusRule.pill(mid, seen, store) == nil)
        #expect(FocusRule.pill(plain, seen, store) == .silent)
    }

    @Test("轮次日志：中途追加或被接走、又没有理解 → 无法核对；有理解照常；真打断仍是被打断；普通的没写仍是没写")
    func logOutcome() throws {
        func entry(_ json: String) throws -> TurnLogEntry {
            try JSONDecoder().decode(TurnLogEntry.self, from: Data(json.utf8))
        }
        let superseded = try entry(#"{"prompt":"修面板截断","reminded":true,"decode":null,"interrupted":false,"supersededAt":"2026-09-13T10:57:44.000Z","midTurn":false}"#)
        let midTurn = try entry(#"{"prompt":"提交吧","reminded":true,"decode":null,"interrupted":false,"supersededAt":null,"midTurn":true}"#)
        let midDeclared = try entry(#"{"prompt":"提交吧","reminded":true,"decode":"提交并推送","interrupted":false,"midTurn":true}"#)
        let interrupted = try entry(#"{"prompt":"修面板截断","reminded":true,"decode":null,"interrupted":true}"#)
        let silent = try entry(#"{"prompt":"修面板截断","reminded":true,"decode":null,"interrupted":false}"#)
        #expect(SessionChart.outcome(superseded) == .unverifiable)
        #expect(SessionChart.outcome(midTurn) == .unverifiable)
        #expect(SessionChart.outcome(midDeclared) == .declared)
        #expect(SessionChart.outcome(interrupted) == .interrupted)
        #expect(SessionChart.outcome(silent) == .silent)
    }

    @Test("排队消息被送达（先有 queued_command 附件）不算撤回；只有 remove 的才是撤回")
    func queuedDelivery() throws {
        var p = TurnProgress()
        let rows = [
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-13T10:57:11.303Z","content":"提交吧"}"#,
            #"{"type":"attachment","timestamp":"2026-09-13T10:57:11.303Z","attachment":{"type":"queued_command","prompt":"提交吧","commandMode":"prompt"}}"#,
            #"{"type":"queue-operation","operation":"remove","timestamp":"2026-09-13T10:57:44.926Z","content":"提交吧"}"#,
            #"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-13T10:58:00.000Z","content":"算了不用了"}"#,
            #"{"type":"queue-operation","operation":"remove","timestamp":"2026-09-13T10:58:03.000Z","content":"算了不用了"}"#,
        ]
        for r in rows {
            let obj = try JSONSerialization.jsonObject(with: Data(r.utf8)) as? [String: Any]
            p.ingest(obj ?? [:])
        }
        #expect(p.withdrawnQueued == ["算了不用了"])
    }

    @Test("岛上显示谁：状态文件 20 分钟没更新、聊天记录刚写过 → 还显示；聊天记录也 20 分钟没动 → 不显示。这一轮已结束，两次都算空闲、不算在跑")
    func transcriptActivity() throws {
        let d = try dir()
        let t = d.appendingPathComponent("busy.transcript.jsonl")
        try Data("{}\n".utf8).write(to: t)
        try write(record(["transcriptPath": t.path, "decode": "读成了", "tag": "剧本审阅"], id: "busy", ago: 1200), "busy.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        #expect(FocusRule.live(store).count == 1)
        #expect(FocusRule.parallel(store).running == 0)
        #expect(FocusRule.parallel(store).idle == 1)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-1200)], ofItemAtPath: t.path)
        store.reload()
        #expect(FocusRule.live(store).isEmpty)
        #expect(FocusRule.parallel(store).running == 0)
        #expect(FocusRule.parallel(store).idle == 1)
    }

    @Test("主动弹出的精简版只放两行：要求一行、理解最多两行；标 ⚠ 用橙色；原话换行压成空格；还没写出就说还没写出")
    func compactFlashLines() throws {
        let d = try dir()
        try write(record(["prompt": "把目录下的脚本\n都过一遍", "decode": "⚠ 先改代码再说", "tag": "改脚本"], id: "flag"), "flag.json", in: d)
        try write(record(["decode": NSNull(), "turnEndedAt": NSNull()], id: "open"), "open.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        let flag = try #require(store.sessions.first { $0.id == "flag" })
        let lines = IslandExpandedContent.compactLines(flag, store: store)
        #expect(lines.count == 2)
        #expect(lines[0] == .init(label: "要求", text: "把目录下的脚本 都过一遍", tone: .secondary, lines: 1))
        #expect(lines[1] == .init(label: "理解", text: "⚠ 先改代码再说", tone: .warning, lines: 2))
        let open = try #require(store.sessions.first { $0.id == "open" })
        let openLines = IslandExpandedContent.compactLines(open, store: store)
        #expect(openLines.count == 2)
        #expect(openLines[1].text == "还没写出")
        #expect(IslandController.compactWidth < IslandController.expandedWidth)
    }

    @Test("菜单栏让路·开始：鼠标在带子里、不在灵动岛上才去查菜单栏；菜单栏窗口出现（正在滑出或已出来）才让；展开或缩回刘海不查")
    func dodgeStart() {
        let band = DodgeRule.band(screen: CGRect(x: 0, y: 0, width: 1280, height: 832), height: 28)
        #expect(band == CGRect(x: 0, y: 804, width: 1280, height: 28))
        let island = CGRect(x: 440, y: 804, width: 520, height: 28)
        func wants(_ p: CGPoint, active: Bool = true) -> Bool {
            DodgeRule.wantsMenuBarCheck(active: active, pointer: p, band: band, island: island)
        }
        #expect(wants(CGPoint(x: 200, y: 832)))                // 顶边那一行
        #expect(wants(CGPoint(x: 1100, y: 831.5)))
        #expect(wants(CGPoint(x: 1100, y: 815)))               // 带子里任何一行都查：菜单栏出来了才让
        #expect(!wants(CGPoint(x: 600, y: 831)))               // 在灵动岛上：那是悬停
        #expect(!wants(CGPoint(x: 200, y: 700)))               // 不在带子里
        #expect(!wants(CGPoint(x: 200, y: 831), active: false))
        #expect(!DodgeRule.shouldStart(menuBarY: nil))         // 菜单栏还没出来：不让
        #expect(DodgeRule.shouldStart(menuBarY: -17))          // 实测滑出时第一次读到的就是 y = −17
        #expect(DodgeRule.shouldStart(menuBarY: 0))
    }

    @Test("让路形状：不让路时凹肩贴屏幕上沿；让到底时颈顶回到屏幕上沿、刘海底角外侧由倒角填上、两端全圆不再有凹肩；中途与窄岛不出错")
    func dodgeShape() {
        let rect = CGRect(x: 0, y: 0, width: 352, height: 28)     // 刘海 156 + 两翼 92×2 + 两肩 6×2
        let rest = NotchShape(topRadius: 6, bottomRadius: 14).path(in: rect)
        #expect(rest.boundingRect.minY == 0)
        #expect(rest.contains(CGPoint(x: 4, y: 0.5)))             // 凹肩：黑色沿屏幕上沿流出去
        #expect(!rest.contains(CGPoint(x: 176, y: -5)))

        let down = NotchShape(topRadius: 6, bottomRadius: 14, drop: 28, dropDepth: 28, capsule: 1, stemWidth: 156).path(in: rect)
        #expect(down.boundingRect.minY <= -28)                    // 颈顶够到屏幕上沿，和刘海连着
        #expect(down.contains(CGPoint(x: 176, y: -14)))           // 颈
        #expect(down.contains(CGPoint(x: 97, y: -0.5)))           // 刘海左底角外 1pt：倒角填上，不漏亮三角
        #expect(down.contains(CGPoint(x: 255, y: -0.5)))          // 右侧对称
        #expect(!down.contains(CGPoint(x: 97, y: -9)))            // 倒角之外仍是菜单栏
        #expect(!down.contains(CGPoint(x: 4, y: 0.5)))            // 两端不再有凹肩
        #expect(!down.contains(CGPoint(x: 7, y: 1)))              // 左上角是凸圆角
        #expect(down.contains(CGPoint(x: 20, y: 14)))

        let midway = NotchShape(topRadius: 6, bottomRadius: 14, drop: 10, dropDepth: 28, capsule: 1, stemWidth: 156).path(in: rect)
        #expect(midway.boundingRect.minY <= -10)
        #expect(midway.contains(CGPoint(x: 176, y: -5)))          // 途中颈也一直连着刘海，不出现缝

        // 回刘海还差 1pt、顶角仍是全圆：两端不冒凹肩（先前按进度长，两只角先悬在半空再合上，用户 2026-09-13）
        let landing = NotchShape(topRadius: 6, bottomRadius: 14, drop: 1, dropDepth: 28, capsule: 1, stemWidth: 156).path(in: rect)
        #expect(landing.boundingRect.minX >= 6 - 0.01)
        // 贴回上沿、顶角合上之后与原形状一致
        let merged = NotchShape(topRadius: 6, bottomRadius: 14, drop: 0, dropDepth: 28, capsule: 0, stemWidth: 156).path(in: rect)
        #expect(merged.contains(CGPoint(x: 4, y: 0.5)))

        let narrow = NotchShape(topRadius: 6, bottomRadius: 14, drop: 28, dropDepth: 28, capsule: 1, stemWidth: 156)
            .path(in: CGRect(x: 0, y: 0, width: 156, height: 28))
        #expect(narrow.contains(CGPoint(x: 78, y: 14)))
        #expect(narrow.boundingRect.width <= 156.01)
    }

    @Test("让路时右边胶囊保持 24pt，只把顶边对齐到主体顶边（中心 14 → 12）；不让路时在刘海高度里居中")
    func pillFlush() {
        #expect(IslandController.pillHeight == 24)
        #expect(IslandController.dodgedPillCenterY(dodge: 0, depth: 28, notchHeight: 28) == 14)
        #expect(IslandController.dodgedPillCenterY(dodge: 28, depth: 28, notchHeight: 28) == 12)   // 顶边 12 − 12 = 0，和主体顶边齐
        #expect(IslandController.dodgedPillCenterY(dodge: 14, depth: 28, notchHeight: 28) == 13)
    }

    @Test("点开面板：显示灵动岛上正显示的会话，不是列表第一个；面板里点过的优先；那个会话不在了才退回第一个")
    func detailFocus() throws {
        let d = try dir()
        try write(record([:], id: "a", ago: 10), "a.json", in: d)
        try write(record([:], id: "b", ago: 300), "b.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        let first = try #require(store.sessions.first)
        let other = try #require(store.sessions.first { $0.id != first.id })
        #expect(DetailView.current(store.sessions, picked: nil, focus: other.id)?.id == other.id)
        #expect(DetailView.current(store.sessions, picked: first.id, focus: other.id)?.id == first.id)
        #expect(DetailView.current(store.sessions, picked: nil, focus: "gone")?.id == first.id)
    }

    @Test("悬停翻页：底部那一行按在跑顺序循环到下一个会话，全都看过、胶囊规则挑不出第二个时也翻得到，三次走遍再回到开头；只有一个会话时没有这一行")
    func flipThrough() throws {
        let d = try dir()
        for (id, ago) in [("a", 10.0), ("b", 20.0), ("c", 30.0)] {
            try write(record(["decode": "读成了", "tag": "标签\(id)"], id: id, ago: ago), "\(id).json", in: d)
        }
        let store = WillowStore(directory: d)
        store.reload()
        let seen = SeenStore(ephemeral: true)
        for s in store.sessions { seen.markSeen(s) }
        let l = FocusRule.live(store)
        #expect(l.count == 3)
        #expect(FocusRule.secondary(store, seen, primary: l[0]) == nil)
        var visited = [l[0].id]
        var cur = l[0]
        for _ in 0..<3 {
            let next = try #require(FocusRule.flipTarget(store, after: cur))
            visited.append(next.id)
            cur = next
        }
        #expect(Set(visited.prefix(3)) == Set(l.map(\.id)))
        #expect(visited.last == l[0].id)

        let one = try dir()
        try write(record(["decode": "读成了"], id: "solo"), "solo.json", in: one)
        let single = WillowStore(directory: one)
        single.reload()
        #expect(FocusRule.flipTarget(single, after: single.sessions.first) == nil)
    }

    @Test("悬停面板一致：灵动岛没开着时结束的一轮，打开后从聊天记录补出时间线；开着又没问的一轮算进行中（结束后才是没问）")
    func reconstructAndOpenTurn() throws {
        let d = try dir()
        let t = d.appendingPathComponent("done.transcript.jsonl")
        let rows = [
            #"{"type":"assistant","timestamp":"2026-09-13T13:00:05.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"Check state files"}}]}}"#,
            #"{"type":"assistant","timestamp":"2026-09-13T13:00:06.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b/extract.mjs"}}]}}"#,
        ]
        try Data((rows.joined(separator: "\n") + "\n").utf8).write(to: t)
        try write(record(["transcriptPath": t.path, "transcriptOffset": 0, "decode": "读成了", "tag": "查状态"], id: "done"), "done.json", in: d)
        try write(record(["reminded": false, "decode": NSNull(), "turnEndedAt": NSNull()], id: "cont"), "cont.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        let done = try #require(store.sessions.first { $0.id == "done" })
        let tl = try #require(store.timeline(for: done))
        #expect(tl.progress.steps.count == 2)
        let cont = try #require(store.sessions.first { $0.id == "cont" })
        #expect(cont.declaration == .inProgress)
        #expect(cont.isRunning)
        #expect(IslandExpandedContent.oneLine("推送到 GitHub 吧 接下来的问题：\n\n1. 动画") == "推送到 GitHub 吧 接下来的问题： 1. 动画")
        // 没问理解的一轮：进度条整条是中性的「这一轮」，不画紫色「写出理解前」
        let t0 = Date(timeIntervalSince1970: 1_789_300_000)
        let quiet = TurnTimeline(startedAt: t0, endedAt: t0.addingTimeInterval(6), progress: TurnProgress())
        #expect(TurnBar.segments(quiet, now: t0.addingTimeInterval(6), asked: false) == [.init(kind: .turn, from: 0, to: 1)])
        #expect(TurnBar.segments(quiet, now: t0.addingTimeInterval(6)) == [.init(kind: .before, from: 0, to: 1)])
        #expect(TurnBar.name(.turn) == "这一轮")
    }

    @Test("第四行「我补上的」插在理解和标签之间：理解与标签照样读得到，补上的那行不会被当成理解")
    func fillLineParsing() {
        let msg = "你批准的：查一下有没有相关论文\n我读成了：逐项检索有没有撞车\n我补上的：「相关 paper」定为撞车与经典先例；没查会刊收不收\n标签：查撞车文献\n\n正文从这里开始"
        let hit = TranscriptTail.scanMessage(msg)
        #expect(hit?.decode == "逐项检索有没有撞车")
        #expect(hit?.tag == "查撞车文献")
    }

    @Test("菜单栏让路·回位：鼠标在带子里或有下拉菜单开着不回；离开带子后菜单栏开始收（y 往负走）或没了才回；收起态不画东西立刻回；曲线端点对；追赶只往前")
    func dodgeEnd() {
        #expect(!DodgeRule.shouldEnd(active: true, pointerInBand: true, menuBarY: 0, popUpOpen: false))
        #expect(!DodgeRule.shouldEnd(active: true, pointerInBand: false, menuBarY: 0, popUpOpen: false))   // 离开了但菜单栏还没开始收：等它
        #expect(DodgeRule.shouldEnd(active: true, pointerInBand: false, menuBarY: -7, popUpOpen: false))   // 实测开始收时第一次读到 y = −7
        #expect(DodgeRule.shouldEnd(active: true, pointerInBand: false, menuBarY: nil, popUpOpen: false))
        #expect(!DodgeRule.shouldEnd(active: true, pointerInBand: false, menuBarY: -7, popUpOpen: true))
        #expect(DodgeRule.shouldEnd(active: false, pointerInBand: true, menuBarY: 0, popUpOpen: false))
        #expect(DodgeRule.eased(0, down: true) == 0)
        #expect(abs(DodgeRule.eased(1, down: true) - 1) < 1e-9)
        #expect(DodgeRule.eased(0, down: false) == 0)
        #expect(abs(DodgeRule.eased(1, down: false) - 1) < 1e-9)
        #expect(DodgeRule.eased(0.3, down: true) == 0.3)       // 画面上的菜单栏近乎匀速
        #expect(DodgeRule.downDuration < DodgeRule.upDuration)
        // 发现时菜单栏已经走了一截：岛先追到它此刻的位置（实测第一次读到的 y），只往前追、不往回拉
        #expect(abs(DodgeRule.catchUp(current: 0, depth: 28, barY: -17, barHeight: 29, down: true) - 28 * (12.0 / 29) * 0.9) < 0.001)    // 读数四成 → 追到九成
        #expect(abs(DodgeRule.catchUp(current: 28, depth: 28, barY: -7, barHeight: 29, down: false) - 28 * (22.0 / 29)) < 0.001)   // 收回直接追到读数
        #expect(DodgeRule.catchUp(current: 20, depth: 28, barY: -17, barHeight: 29, down: true) == 20)     // 岛已经走得更远：不动
        #expect(DodgeRule.catchUp(current: 5, depth: 28, barY: nil, barHeight: 29, down: false) == 5)
    }
}
