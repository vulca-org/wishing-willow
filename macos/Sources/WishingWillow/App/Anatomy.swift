import AppKit
import SwiftUI

/// `--anatomy <目录>`：导出左翼状态的工程标注图。
///
/// 用户 2026-09-13：「左翼状态展示 ui 设计还是有问题，需要有工程导图的方式把他导出来，每一个元素都要有正确的指代」。
/// 图用的是**真实组件**（DuoGlyph）放大渲染，不是另画的示意——图和屏幕上的东西不会漂成两套。
/// 每个元素先用标注线框出它指的范围（弧段用同心括弧、一排点用括弧、圆心用虚线圈、计时用括线），
/// 引线从括线中点引到说明；下面两排是全部取值：圆心的 7 种状态、外圈的 3 档颜色、四点的 1–4 个会话。
@MainActor
enum Anatomy {
    static func run(outputDirectory: String) -> Int32 {
        let out = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var failures = 0
        for lang in [Lang.zh, Lang.en] {
            Lang.current = lang
            let view = AnatomyView().environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let cg = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
                failures += 1
                continue
            }
            let name = lang == .zh ? "left-wing-anatomy.zh.png" : "left-wing-anatomy.en.png"
            do { try png.write(to: out.appendingPathComponent(name)); print(out.appendingPathComponent(name).path) }
            catch { failures += 1 }
        }
        Lang.current = Lang.resolve()
        return failures == 0 ? 0 : 1
    }
}

struct AnatomyView: View {
    static let size = CGSize(width: 1600, height: 980)
    private static let margin: CGFloat = 60
    private static let column: CGFloat = 330
    private let glyph: CGFloat = 250
    private let cx: CGFloat = 650
    private let cy: CGFloat = 330
    private let sessions = 2

    private var snapshot: ClaudeStatus.Snapshot {
        ClaudeStatus.Snapshot(contextUsed: 540_000, window: 1_000_000, cacheHit: 0.98, outputTokens: 2900,
                              requests: 3, lastWrite: Date())
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(white: 0.07), Color(white: 0.03)], startPoint: .top, endPoint: .bottom)

            header.position(x: Self.size.width / 2, y: 62)

            // 放大的左翼：图标 + 计时，衬一段黑色翼。放大倍数不一（图标 ×14、计时 ×7.7），实际大小见下方那一枚。
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 44, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: 680, height: 350)
                .position(x: cx + 150, y: cy)
            DuoGlyph(snapshot: snapshot, center: .live, sessions: sessions, size: glyph)
                .position(x: cx, y: cy)
            Text("0:15")
                .font(.system(size: 92, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.7))
                .position(x: timerX, y: cy)

            marks

            ForEach(callouts) { c in
                calloutBlock(c)
                    .frame(width: Self.column, height: 110, alignment: c.left ? .topTrailing : .topLeading)
                    .position(x: c.left ? Self.margin + Self.column / 2 : Self.size.width - Self.margin - Self.column / 2,
                              y: c.shoulderY - 11 + 55)
            }

            reading.position(x: cx + 150, y: cy + 262)

            variants
                .frame(width: Self.size.width - 2 * Self.margin, height: 300, alignment: .topLeading)
                .position(x: Self.size.width / 2, y: cy + 310 + 150)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(L("左翼状态 · 每个元素指什么", "Left wing · what each element means"))
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.white)
            Text(L("折叠态灵动岛左翼，照 iPhone Duo 的合一状态图标画：一段弧、一个符号、一排点，三种形状各说一件事",
                   "Collapsed island, left wing — modelled on iPhone Duo’s combined status icon: an arc, a symbol and a row of dots, three shapes for three facts"))
                .font(.system(size: 16))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    // MARK: 标注
    //
    // 工程图的规矩：先框出被指的范围，再引线；引线不交叉、不穿过别的元素。
    // 第一版引线交叉、穿过计时，实心锚点压住一个点；第二版改成空心圈，但圈只指一个点——
    // 「亮段」指到的是弧上某一点、「四点」指到的是其中一个点，读者分不清指的是一段还是一粒（2026-09-13）。
    // 现在：弧段用同心括弧量出起止，四点用一段括弧兜住一整排，圆心用虚线圈，计时用括线。

    private var timerX: CGFloat { cx + 330 }
    private var timerHalfWidth: CGFloat { 100 }
    private var dot: CGFloat { glyph * DuoGeometry.dotSizeRatio }
    private var line: CGFloat { glyph * DuoGeometry.lineRatio }
    private var radius: CGFloat { glyph / 2 - dot / 2 }
    private var bracketRadius: CGFloat { radius + max(line, dot) / 2 + 14 }
    private var glyphCenter: CGPoint { CGPoint(x: cx, y: cy) }
    /// 圆心符号在图标里上移了 3%（DuoGlyph 里的 offset）。
    private var symbolCenter: CGPoint { CGPoint(x: cx, y: cy - glyph * 0.03) }
    private var symbolRing: CGFloat { glyph * 0.32 }
    private var leftEdge: CGFloat { Self.margin + Self.column + 18 }
    private var rightEdge: CGFloat { Self.size.width - Self.margin - Self.column - 18 }

    /// 屏幕角度（度）：0 = 3 点钟方向，顺时针为正，90 = 正下方。与 DuoGlyph 的 trim + rotation 同一套。
    private func at(_ degrees: Double, _ r: CGFloat, _ c: CGPoint) -> CGPoint {
        let a = degrees * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
    }

    /// 沿径向从锚点走到指定高度，作为引线的拐点。
    private func radialElbow(_ anchor: CGPoint, _ degrees: Double, toY y: CGFloat) -> CGPoint {
        let a = degrees * .pi / 180
        let d = (y - anchor.y) / CGFloat(sin(a))
        return CGPoint(x: anchor.x + d * CGFloat(cos(a)), y: y)
    }

    private var arcStart: Double { DuoGeometry.arcStartDegrees }
    private var arcEnd: Double { DuoGeometry.arcStartDegrees + DuoGeometry.arcSpan }
    private var litEnd: Double { arcStart + DuoGeometry.arcSpan * max(0.03, snapshot.remaining) }
    private var dotHalfDegrees: Double { asin(Double(dot / 2 / radius)) * 180 / .pi }
    private var capDegrees: Double { asin(Double(line / 2 / radius)) * 180 / .pi }
    private var dotsReach: Double { (DuoGeometry.dotAngles.map { abs($0) }.max() ?? 30) + dotHalfDegrees + 3 }
    /// 圆心的引线从左下缺口出去：最左一个点的外沿与弧起点的圆头之间的正中。
    private var centreExit: Double { ((90 + dotsReach - 3) + (arcStart - capDegrees)) / 2 }

    private struct Callout: Identifiable {
        let id: Int
        let title: String
        let body: String
        let left: Bool
        let shoulderY: CGFloat
        let path: [CGPoint]
    }

    private var litCallout: Callout {
        let mid = (arcStart + litEnd - 3) / 2
        let anchor = at(mid, bracketRadius, glyphCenter)
        let y = cy - 110
        return Callout(id: 0, title: L("外圈弧 · 亮段", "Arc · lit part"),
                       body: L("这个会话的上下文还剩多少。剩 20% 变橙，剩 10% 变红（快到自动压缩了）",
                               "How much context this session has left. Orange at 20%, red at 10% (auto-compact is near)"),
                       left: true, shoulderY: y,
                       path: [anchor, radialElbow(anchor, mid, toY: y), CGPoint(x: leftEdge, y: y)])
    }

    private var dimCallout: Callout {
        let mid = (litEnd + 3 + arcEnd) / 2
        let anchor = at(mid, bracketRadius, glyphCenter)
        let y = cy - 110
        return Callout(id: 1, title: L("外圈弧 · 暗段", "Arc · dim part"),
                       body: L("已经用掉的上下文。还没有 token 数据时整段都暗，不假装知道",
                               "Context already used. All dim until there is token data — no guessing"),
                       left: false, shoulderY: y,
                       path: [anchor, radialElbow(anchor, mid, toY: y), CGPoint(x: rightEdge, y: y)])
    }

    private var centreCallout: Callout {
        let anchor = at(centreExit, symbolRing, symbolCenter)
        let y = cy + 110
        return Callout(id: 2, title: L("圆心", "Centre"),
                       body: L("这一轮的状态，七种见下方。在跑时是扇形：10 秒内写过满格，1 分钟内两格，5 分钟内一格",
                               "This turn’s state — seven, shown below. Running is a fan: full if Claude wrote in the last 10 s, two bars within 1 min, one within 5 min"),
                       left: true, shoulderY: y,
                       path: [anchor, radialElbow(anchor, centreExit, toY: y), CGPoint(x: leftEdge, y: y)])
    }

    private var dotsCallout: Callout {
        let anchor = at(90, bracketRadius, glyphCenter)
        let y = cy + 215
        return Callout(id: 3, title: L("底部四点", "Four dots"),
                       body: L("几个 Claude Code 会话在跑，这一个也算\n亮满 4 个 = 4 个及以上",
                               "How many Claude Code sessions are running, this one included\nAll four lit = four or more"),
                       left: true, shoulderY: y,
                       path: [anchor, CGPoint(x: anchor.x, y: y), CGPoint(x: leftEdge, y: y)])
    }

    private var timerCallout: Callout {
        let anchor = CGPoint(x: timerX, y: cy + 50)
        let y = cy + 215
        return Callout(id: 4, title: L("计时", "Clock"),
                       body: L("在跑：从你按回车起算\n等你回应：已经等了多久\n结束：结束了多久（刚刚 / 12 分）",
                               "Running: since you pressed Return\nWaiting on you: how long it has waited\nEnded: how long ago (now / 12m)"),
                       left: false, shoulderY: y,
                       path: [anchor, CGPoint(x: anchor.x, y: y), CGPoint(x: rightEdge, y: y)])
    }

    private var callouts: [Callout] { [litCallout, dimCallout, centreCallout, dotsCallout, timerCallout] }

    private func arcPath(_ a0: Double, _ a1: Double, _ r: CGFloat, _ c: CGPoint) -> Path {
        var p = Path()
        let steps = max(2, Int(abs(a1 - a0) / 2))
        for i in 0...steps {
            let q = at(a0 + (a1 - a0) * Double(i) / Double(steps), r, c)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }

    private func bracket(_ a0: Double, _ a1: Double) -> Path {
        var p = arcPath(a0, a1, bracketRadius, glyphCenter)
        for a in [a0, a1] {
            p.move(to: at(a, bracketRadius - 7, glyphCenter))
            p.addLine(to: at(a, bracketRadius + 7, glyphCenter))
        }
        return p
    }

    private var marks: some View {
        Canvas { ctx, _ in
            let ink = GraphicsContext.Shading.color(Color.white.opacity(0.55))
            let thin = StrokeStyle(lineWidth: 1.2, lineCap: .round)

            ctx.stroke(bracket(arcStart, litEnd - 3), with: ink, style: thin)
            ctx.stroke(bracket(litEnd + 3, arcEnd), with: ink, style: thin)
            ctx.stroke(bracket(90 - dotsReach, 90 + dotsReach), with: ink, style: thin)

            let ring = Path(ellipseIn: CGRect(x: symbolCenter.x - symbolRing, y: symbolCenter.y - symbolRing,
                                              width: 2 * symbolRing, height: 2 * symbolRing))
            ctx.stroke(ring, with: ink, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))

            var bar = Path()
            let barY = cy + 50
            bar.move(to: CGPoint(x: timerX - timerHalfWidth, y: barY - 8))
            bar.addLine(to: CGPoint(x: timerX - timerHalfWidth, y: barY))
            bar.addLine(to: CGPoint(x: timerX + timerHalfWidth, y: barY))
            bar.addLine(to: CGPoint(x: timerX + timerHalfWidth, y: barY - 8))
            ctx.stroke(bar, with: ink, style: thin)

            for c in callouts {
                var p = Path()
                p.addLines(c.path)
                ctx.stroke(p, with: ink, style: thin)
                if let a = c.path.first {
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - 3.5, y: a.y - 3.5, width: 7, height: 7)), with: .color(.white))
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .allowsHitTesting(false)
    }

    private func calloutBlock(_ c: Callout) -> some View {
        VStack(alignment: c.left ? .trailing : .leading, spacing: 6) {
            Text(c.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.white)
            Text(c.body)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.62))
                .multilineTextAlignment(c.left ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 实际大小的一枚，和这一枚的读法。放大图的各部分倍数不同，没有这一枚读者会误判它在屏幕上多大。
    private var reading: some View {
        let left = Int((snapshot.remaining * 100).rounded())
        return HStack(spacing: 14) {
            HStack(spacing: 5) {
                DuoGlyph(snapshot: snapshot, center: .live, sessions: sessions, size: 18)
                Text("0:15")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.black, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            Text(L("实际大小。读作：上下文剩 \(left)%，\(sessions) 个会话在跑，刚写过，这一轮已跑 15 秒",
                   "Actual size. Reads: \(left)% context left, \(sessions) sessions running, wrote just now, 15 s into the turn"))
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize()
        }
    }

    // MARK: 全部取值
    //
    // 先前一整句「元组数组 + map + AnyView」让类型检查器跑满 10 分钟没出结果（2026-09-13）。
    // 拆成带明确类型的小结构，每排一个属性。两排共用 7 列，列与列上下对齐；上一版三组挤在左半边，右半边空着。

    private struct CenterSample: Identifiable { let id: Int; let center: StatusCenter; let caption: String }
    private struct ArcSample: Identifiable { let id: Int; let remaining: Double; let caption: String }

    private let sample: CGFloat = 64
    private var colWidth: CGFloat { (Self.size.width - 2 * Self.margin) / 7 }

    private var centerSamples: [CenterSample] {
        [
            CenterSample(id: 0, center: .live, caption: L("在跑", "Running")),
            CenterSample(id: 1, center: .waiting, caption: L("等你回应", "Waiting on you")),
            CenterSample(id: 2, center: .done, caption: L("写了理解", "Reading written")),
            CenterSample(id: 3, center: .flagged, caption: L("没写 / 自标不一致", "Not written / flagged")),
            CenterSample(id: 4, center: .broken, caption: L("插件读不到", "Plugin can’t read")),
            CenterSample(id: 5, center: .withdrawn, caption: L("你撤回了", "You withdrew")),
            CenterSample(id: 6, center: .idle, caption: L("这一轮没问", "Not asked")),
        ]
    }

    private var arcSamples: [ArcSample] {
        [
            ArcSample(id: 0, remaining: 0.6, caption: L("还剩 60%", "60% left")),
            ArcSample(id: 1, remaining: 0.15, caption: L("剩 15% · 橙", "15% · orange")),
            ArcSample(id: 2, remaining: 0.06, caption: L("剩 6% · 红", "6% · red")),
        ]
    }

    private func arcSnapshot(_ remaining: Double) -> ClaudeStatus.Snapshot {
        ClaudeStatus.Snapshot(contextUsed: Int((1 - remaining) * 1_000_000), window: 1_000_000,
                              cacheHit: 0.9, outputTokens: 0, requests: 1, lastWrite: Date())
    }

    private var variants: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Text(L("全部取值", "Every value")).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                Text(L("每排只变一个量，其余照上图", "one variable per row, everything else as above"))
                    .font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.45))
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            }
            .padding(.leading, (colWidth - sample) / 2)
            .padding(.trailing, (colWidth - sample) / 2)
            centerRow
            HStack(alignment: .top, spacing: 0) {
                arcRow
                dotsRow
            }
        }
    }

    private var centerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowTitle(L("圆心 · 7 种状态", "Centre · 7 states"))
            HStack(spacing: 0) {
                ForEach(centerSamples) { s in
                    sampleCell(DuoGlyph(snapshot: snapshot, center: s.center, sessions: sessions, size: sample), s.caption)
                }
            }
        }
    }

    private var arcRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowTitle(L("外圈弧 · 3 档颜色", "Arc · 3 colour levels"))
            HStack(spacing: 0) {
                ForEach(arcSamples) { s in
                    sampleCell(DuoGlyph(snapshot: arcSnapshot(s.remaining), center: .live, sessions: sessions, size: sample), s.caption)
                }
            }
        }
    }

    private var dotsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowTitle(L("底部四点 · 在跑的会话数", "Four dots · sessions running"))
            HStack(spacing: 0) {
                ForEach(1...4, id: \.self) { n in
                    sampleCell(DuoGlyph(snapshot: snapshot, center: .done, sessions: n, size: sample),
                               n == 4 ? L("4 个及以上", "4 or more") : L("\(n) 个", "\(n)"))
                }
            }
        }
    }

    private func rowTitle(_ s: String) -> some View {
        Text(s).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.55))
            .padding(.leading, (colWidth - sample) / 2)
    }

    private func sampleCell(_ g: DuoGlyph, _ caption: String) -> some View {
        VStack(spacing: 10) {
            g.frame(width: sample, height: sample)
            Text(caption).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.72)).fixedSize()
        }
        .frame(width: colWidth)
    }
}
