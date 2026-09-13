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

    @Test("在跑判定：状态文件 20 分钟没更新、聊天记录刚写过 → 在跑；聊天记录也 20 分钟没动 → 空闲")
    func transcriptActivity() throws {
        let d = try dir()
        let t = d.appendingPathComponent("busy.transcript.jsonl")
        try Data("{}\n".utf8).write(to: t)
        try write(record(["transcriptPath": t.path, "decode": "读成了", "tag": "剧本审阅"], id: "busy", ago: 1200), "busy.json", in: d)
        let store = WillowStore(directory: d)
        store.reload()
        #expect(FocusRule.parallel(store).running == 1)
        #expect(FocusRule.parallel(store).idle == 0)

        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-1200)], ofItemAtPath: t.path)
        store.reload()
        #expect(FocusRule.parallel(store).running == 0)
        #expect(FocusRule.parallel(store).idle == 1)
    }

    @Test("菜单栏让路：碰到最顶上那一行、不在灵动岛上 → 让；带子里但没碰顶边 → 不让（菜单栏还没出来）；落在灵动岛上 → 不让（那是悬停）；展开或缩回刘海 → 不让")
    func dodgeStart() {
        let band = DodgeRule.band(screen: CGRect(x: 0, y: 0, width: 1280, height: 832), height: 28)
        #expect(band == CGRect(x: 0, y: 804, width: 1280, height: 28))
        let island = CGRect(x: 440, y: 804, width: 520, height: 28)
        let now = Date()
        func start(_ p: CGPoint, active: Bool = true) -> Bool {
            DodgeRule.next(dodging: false, active: active, pointer: p, band: band, island: island,
                           outSince: nil, now: now, menuOpen: false).dodge
        }
        #expect(start(CGPoint(x: 200, y: 832)) == true)       // 顶边那一行
        #expect(start(CGPoint(x: 1100, y: 831.5)) == true)
        #expect(start(CGPoint(x: 1100, y: 815)) == false)     // 带子里，但没碰到顶边
        #expect(start(CGPoint(x: 600, y: 831)) == false)      // 在灵动岛上
        #expect(start(CGPoint(x: 200, y: 700)) == false)      // 不在带子里
        #expect(start(CGPoint(x: 200, y: 831), active: false) == false)
    }

    @Test("让路形状：不让路时凹肩贴屏幕上沿；让到底时颈顶回到屏幕上沿、刘海底角外侧由倒角填上、两端全圆不再有凹肩；中途与窄岛不出错")
    func dodgeShape() {
        let rect = CGRect(x: 0, y: 0, width: 352, height: 28)     // 刘海 156 + 两翼 92×2 + 两肩 6×2
        let rest = NotchShape(topRadius: 6, bottomRadius: 14).path(in: rect)
        #expect(rest.boundingRect.minY == 0)
        #expect(rest.contains(CGPoint(x: 4, y: 0.5)))             // 凹肩：黑色沿屏幕上沿流出去
        #expect(!rest.contains(CGPoint(x: 176, y: -5)))

        let down = NotchShape(topRadius: 6, bottomRadius: 14, drop: 28, dropDepth: 28, stemWidth: 156).path(in: rect)
        #expect(down.boundingRect.minY <= -28)                    // 颈顶够到屏幕上沿，和刘海连着
        #expect(down.contains(CGPoint(x: 176, y: -14)))           // 颈
        #expect(down.contains(CGPoint(x: 97, y: -0.5)))           // 刘海左底角外 1pt：倒角填上，不漏亮三角
        #expect(down.contains(CGPoint(x: 255, y: -0.5)))          // 右侧对称
        #expect(!down.contains(CGPoint(x: 97, y: -9)))            // 倒角之外仍是菜单栏
        #expect(!down.contains(CGPoint(x: 4, y: 0.5)))            // 两端不再有凹肩
        #expect(!down.contains(CGPoint(x: 7, y: 1)))              // 左上角是凸圆角
        #expect(down.contains(CGPoint(x: 20, y: 14)))

        let midway = NotchShape(topRadius: 6, bottomRadius: 14, drop: 10, dropDepth: 28, stemWidth: 156).path(in: rect)
        #expect(midway.boundingRect.minY <= -10)
        #expect(midway.contains(CGPoint(x: 176, y: -5)))          // 途中颈也一直连着刘海，不出现缝

        let narrow = NotchShape(topRadius: 6, bottomRadius: 14, drop: 28, dropDepth: 28, stemWidth: 156)
            .path(in: CGRect(x: 0, y: 0, width: 156, height: 28))
        #expect(narrow.contains(CGPoint(x: 78, y: 14)))
        #expect(narrow.boundingRect.width <= 156.01)
    }

    @Test("菜单栏让路：让开后鼠标在带子里一直让；离开不到 0.35 秒不回；超过才回；有菜单开着不回")
    func dodgeEnd() {
        let band = DodgeRule.band(screen: CGRect(x: 0, y: 0, width: 1280, height: 832), height: 28)
        let island = CGRect(x: 440, y: 804, width: 520, height: 28)
        let t0 = Date()
        let inBand = DodgeRule.next(dodging: true, active: true, pointer: CGPoint(x: 600, y: 820), band: band, island: island,
                                    outSince: nil, now: t0, menuOpen: false)
        #expect(inBand.dodge == true)
        #expect(inBand.outSince == nil)
        let justLeft = DodgeRule.next(dodging: true, active: true, pointer: CGPoint(x: 600, y: 700), band: band, island: island,
                                      outSince: nil, now: t0, menuOpen: false)
        #expect(justLeft.dodge == true)
        #expect(justLeft.outSince == t0)
        let later = DodgeRule.next(dodging: true, active: true, pointer: CGPoint(x: 600, y: 700), band: band, island: island,
                                   outSince: t0, now: t0.addingTimeInterval(0.4), menuOpen: false)
        #expect(later.dodge == false)
        let menu = DodgeRule.next(dodging: true, active: true, pointer: CGPoint(x: 600, y: 600), band: band, island: island,
                                  outSince: t0, now: t0.addingTimeInterval(2), menuOpen: true)
        #expect(menu.dodge == true)
        let collapsed = DodgeRule.next(dodging: true, active: false, pointer: CGPoint(x: 200, y: 831), band: band, island: island,
                                       outSince: nil, now: t0, menuOpen: false)
        #expect(collapsed.dodge == false)
    }
}
