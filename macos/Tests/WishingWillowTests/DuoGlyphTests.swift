import Testing
import Foundation
@testable import WishingWillow

/// 折叠态左翼的合一状态图标，照 iPhone Duo 做。几何量自 dev.to「One icon, three signals」封面动图第 22–28 帧；
/// 圆心按用户 2026-09-13 选的方案随状态换符号（Duo 原版圆心固定是 Wi-Fi 扇形）。
@MainActor
@Suite("Duo 状态图标")
struct DuoGlyphTests {
    init() { Lang.current = .zh }

    private func state(_ json: String, interruptedAt: Date? = nil) throws -> SessionState {
        SessionState(record: try JSONDecoder().decode(WillowRecord.self, from: Data(json.utf8)), now: .now,
                     liveInterruptedAt: interruptedAt)
    }

    private let base = #""schema":9,"sessionId":"s","cwd":"/x/a","turnId":"t1","origin":"user","promptField":"prompt""#

    @Test("圆心：在跑=扇形；等你选=问号；写了理解=对勾；自标不一致或问了没写=感叹号(橙)；读不到=感叹号(红)；撤回=回退；没问=横线")
    func centerSymbol() throws {
        let running = try state("{\(base),\"prompt\":\"一句够长的请求\",\"reminded\":true,\"decode\":null,\"turnEndedAt\":null}")
        #expect(StatusCenter.of(running, progress: nil, withdrawn: false) == .live)

        var waiting = TurnProgress()
        waiting.pendingChoice = TurnProgress.Choice(id: "q", kind: .question, at: .now, header: nil, question: nil, options: [], count: 1)
        #expect(StatusCenter.of(running, progress: waiting, withdrawn: false) == .waiting)
        #expect(StatusCenter.of(running, progress: nil, withdrawn: true) == .withdrawn)

        let declared = try state("{\(base),\"prompt\":\"一句够长的请求\",\"reminded\":true,\"decode\":\"读成了\",\"turnEndedAt\":\"2026-09-13T01:00:00.000Z\"}")
        #expect(StatusCenter.of(declared, progress: nil, withdrawn: false) == .done)

        let flagged = try state("{\(base),\"prompt\":\"一句够长的请求\",\"reminded\":true,\"decode\":\"⚠ 读偏了\",\"turnEndedAt\":\"2026-09-13T01:00:00.000Z\"}")
        #expect(StatusCenter.of(flagged, progress: nil, withdrawn: false) == .flagged)

        let silent = try state("{\(base),\"prompt\":\"一句够长的请求\",\"reminded\":true,\"decode\":null,\"turnEndedAt\":\"2026-09-13T01:00:00.000Z\"}")
        #expect(StatusCenter.of(silent, progress: nil, withdrawn: false) == .flagged)

        let notAsked = try state("{\(base),\"prompt\":\"好的\",\"reminded\":false,\"decode\":null,\"turnEndedAt\":\"2026-09-13T01:00:00.000Z\"}")
        #expect(StatusCenter.of(notAsked, progress: nil, withdrawn: false) == .idle)

        let broken = try state(#"{"schema":9,"sessionId":"s","cwd":"/x/a","turnId":"t1","prompt":null,"promptField":null}"#)
        #expect(broken.declaration == .unreadable)
        #expect(StatusCenter.of(broken, progress: nil, withdrawn: false) == .broken)

        let interrupted = try state("{\(base),\"prompt\":\"一句够长的请求\",\"reminded\":true,\"decode\":null,\"turnEndedAt\":null}",
                                    interruptedAt: .now)
        #expect(StatusCenter.of(interrupted, progress: nil, withdrawn: false) == .withdrawn)
    }

    @Test("几何：外圈弧跨 230°、缺口居中在正下方；四个点全在缺口里、从左到右、等距")
    func geometry() {
        let half = (360 - DuoGeometry.arcSpan) / 2
        #expect(DuoGeometry.arcSpan == 230)
        #expect(DuoGeometry.arcStartDegrees == 90 + half)
        #expect(DuoGeometry.dotAngles.count == 4)
        #expect(DuoGeometry.dotAngles.allSatisfy { abs($0) < half })
        #expect(DuoGeometry.dotAngles == DuoGeometry.dotAngles.sorted(by: >))
        let gaps = zip(DuoGeometry.dotAngles, DuoGeometry.dotAngles.dropFirst()).map { $0 - $1 }
        #expect(Set(gaps).count == 1)
    }

    @Test("底部四点 = 并行在跑的会话数：0 个不亮，1–4 亮对应个数，超过 4 个亮满")
    func dotsCountSessions() {
        #expect(DuoGeometry.litDots(running: 0) == 0)
        #expect(DuoGeometry.litDots(running: 1) == 1)
        #expect(DuoGeometry.litDots(running: 3) == 3)
        #expect(DuoGeometry.litDots(running: 4) == 4)
        #expect(DuoGeometry.litDots(running: 9) == 4)
    }
}
