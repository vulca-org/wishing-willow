import SwiftUI

/// Apple 风格的界面件。
///
/// 用户 2026-09-12 夜明确要求「严格遵守 Apple 设计风格，并使用导图的工程设计技巧」，并判定上一版的
/// 加重四角边框、尺寸线式时间刻度尺、圈号、点阵都不符合 Apple 风格。这些装饰全部去掉。
/// 留下的是图纸的**方法**，不是它的**外观**：
/// - 一条对齐线：同一块里所有正文左缘同一个 x；
/// - 4pt 间距网格（4 / 8 / 12 / 16）；
/// - 同心圆角：外框下角 24、内边距 16 → 贴底的内框 8；
/// - 数字一律用 SF 的等宽数字（monospacedDigit），不用等宽字体；
/// - 标注只写可以核对的数；图例与刻度贴着数据。
enum Ink {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.6)
    static let tertiary = Color.white.opacity(0.36)
    static let quaternary = Color.white.opacity(0.2)
    static let fill = Color.white.opacity(0.07)
    static let separator = Color.white.opacity(0.1)
    static let hair: CGFloat = 0.5

    static func number(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

/// 分节标题：左边标题，右边一个可以核对的数——Apple 设置页「标签 … 值」的排法。
struct SectionHeader: View {
    let title: String
    var value: String? = nil
    var valueTint: Color = Ink.tertiary
    var badge: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.secondary)
                .fixedSize()
            if let badge { Badge(text: badge) }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Ink.number(11))
                    .foregroundStyle(valueTint)
                    .lineLimit(1)
            }
        }
    }
}

struct Badge: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint.opacity(0.9))
            .fixedSize()
    }
}

/// 数据条里的一格：上面小号标签，下面数值（可带一个小图形）。
struct StatCell<Accessory: View>: View {
    let label: String
    let value: String
    var tint: Color = Ink.primary
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(value)
                    .font(Ink.number(12.5, .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                accessory()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StatCell where Accessory == EmptyView {
    init(label: String, value: String, tint: Color = Ink.primary) {
        self.init(label: label, value: value, tint: tint) { EmptyView() }
    }
}

struct StatDivider: View {
    var body: some View {
        Rectangle().fill(Ink.separator).frame(width: Ink.hair).padding(.vertical, 8)
    }
}

/// 各块按从上到下的次序淡入、下移 4pt 到位。**不用模糊**：模糊渐显时行与行糊成一片，
/// 用户看到的「文字叠加」就是它（2026-09-12 录屏第 84–88 帧）。
struct Reveal: ViewModifier {
    let order: Int
    let shown: Bool
    let after: Double

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -4)
            .animation(.easeOut(duration: 0.2).delay(after + 0.04 * Double(order)), value: shown)
    }
}

extension View {
    func reveal(_ order: Int, _ shown: Bool, after: Double = 0.1) -> some View {
        modifier(Reveal(order: order, shown: shown, after: after))
    }
}

/// 圆心放什么。iPhone Duo 原版的圆心固定是 Wi-Fi 扇形；用户 2026-09-13 选的方案是圆心随状态换符号，
/// 这样左翼只要一个圆加计时，就能说清「在跑 / 等你 / 结束 / 出事」。
enum StatusCenter: Equatable {
    case live        // 在跑：Wi-Fi 扇形，写得越近越满
    case waiting     // Claude 在等你选择或批准
    case done        // 结束，写了理解
    case flagged     // 结束但问了没写，或 Claude 自标不一致
    case broken      // 插件读不到输入
    case withdrawn   // 你撤回了这一轮
    case idle        // 这一轮没问 / 还没开始

    static func of(_ s: SessionState, progress: TurnProgress?, withdrawn: Bool) -> StatusCenter {
        if s.declaration == .unreadable { return .broken }
        if withdrawn || s.declaration == .interrupted { return .withdrawn }
        if progress?.pendingChoice != nil { return .waiting }
        switch s.declaration {
        case .inProgress: return .live
        case .declared: return s.flaggedByModel ? .flagged : .done
        case .undeclared: return .flagged
        case .notAsked, .awaiting: return .idle
        case .unreadable, .interrupted: return .broken
        }
    }
}

/// iPhone Duo 合一状态图标的几何。量自 dev.to「One icon, three signals」封面动图第 22–28 帧（640×360，放大 3 倍逐帧看）：
/// 外圈是一段约 230° 的粗弧，缺口居中在正下方；四个圆点排在缺口里，和弧落在同一个圆上，相邻约隔 20°；
/// 弧宽约为外径的 5.3%、点径约 7.9%（相邻两点之间的空隙约等于一个点径）；Wi-Fi 扇形居中，宽约为外径的 44%。
/// 先前那版画成整圈加圈内四点；第二版比例又画粗了约 1.7 倍，20pt 下四个点挤成一团（2026-09-13 放大截图）。
enum DuoGeometry {
    static let arcSpan: Double = 230
    /// 相对正下方的角度（度），从左到右。
    static let dotAngles: [Double] = [30, 10, -10, -30]
    static let lineRatio: CGFloat = 0.058
    static let dotSizeRatio: CGFloat = 0.082
    static let symbolRatio: CGFloat = 0.42
    /// 弧从左下端起、顺时针经过顶部到右下端。SwiftUI 的 trim 从 3 点钟方向起算，正下方是 90°。
    static var arcStartDegrees: Double { 90 + (360 - arcSpan) / 2 }

    /// 底部四点亮几个：并行在跑的 Claude Code 会话数，满 4 表示 4 个及以上。
    /// 先前是缓存命中率——数据准，但对用户没有可操作的含义（用户 2026-09-13 选定改为会话数）。
    static func litDots(running: Int) -> Int { min(4, max(0, running)) }
}

/// 折叠态左翼的合一状态图标，照 iPhone Duo 角落里那个圆画：外圈弧、底部四点、圆心符号，三种形状各走一个视觉通道。
/// - 外圈弧：上下文还剩多少（像电量；剩 20% 变橙、10% 变红）。没有 token 数据时只画暗轨道，不假装知道；
/// - 底部四点：几个 Claude Code 会话在跑（像信号格那样计数，满 4 = 4 个及以上）；
/// - 圆心：状态符号（StatusCenter）；在跑时是 Wi-Fi 扇形，最近一次写入越近越满。换符号时用 SF Symbols 的替换动效。
struct DuoGlyph: View {
    var snapshot: ClaudeStatus.Snapshot?
    let center: StatusCenter
    /// 并行在跑的会话数（含这一个）。
    var sessions: Int = 1
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let since = snapshot?.lastWrite.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            glyph(live: ClaudeStatus.liveness(secondsSinceLastWrite: since))
        }
        .frame(width: size, height: size)
        .help(summary)
        .accessibilityElement()
        .accessibilityLabel(summary)
    }

    private func glyph(live: Double) -> some View {
        let lw = max(1.1, size * DuoGeometry.lineRatio)
        let dot = max(1.6, size * DuoGeometry.dotSizeRatio)
        let r = size / 2 - dot / 2
        let span = DuoGeometry.arcSpan / 360
        let lit = DuoGeometry.litDots(running: sessions)
        let symbol = Self.symbol(center, live: live)
        return ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(Ink.quaternary, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(DuoGeometry.arcStartDegrees))
                .frame(width: 2 * r, height: 2 * r)
            if let remaining = snapshot?.remaining {
                Circle()
                    .trim(from: 0, to: span * max(0.03, remaining))
                    .stroke(Self.ringColor(remaining), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    .rotationEffect(.degrees(DuoGeometry.arcStartDegrees))
                    .frame(width: 2 * r, height: 2 * r)
            }
            ForEach(Array(DuoGeometry.dotAngles.enumerated()), id: \.offset) { i, a in
                let theta = (90 + a) * .pi / 180
                Circle()
                    .fill(i < lit ? Ink.primary : Ink.quaternary)
                    .frame(width: dot, height: dot)
                    .offset(x: r * CGFloat(cos(theta)), y: r * CGFloat(sin(theta)))
            }
            Image(systemName: symbol.name, variableValue: symbol.variable)
                .font(.system(size: size * DuoGeometry.symbolRatio, weight: .bold))
                .foregroundStyle(symbol.tint)
                .contentTransition(.symbolEffect(.replace))
                .offset(y: -size * 0.03)
        }
        .frame(width: size, height: size)
    }

    static func symbol(_ c: StatusCenter, live: Double) -> (name: String, variable: Double?, tint: Color) {
        switch c {
        case .live: ("wifi", live, Ink.primary)
        case .waiting: ("questionmark", nil, ChoiceCard.accent)
        case .done: ("checkmark", nil, Ink.primary)
        case .flagged: ("exclamationmark", nil, .orange)
        case .broken: ("exclamationmark", nil, .red)
        case .withdrawn: ("arrow.uturn.backward", nil, Ink.secondary)
        case .idle: ("minus", nil, Ink.tertiary)
        }
    }

    static func ringColor(_ remaining: Double) -> Color {
        switch ClaudeStatus.level(remaining: remaining) {
        case .critical: .red
        case .low: .orange
        case .normal: Ink.primary
        }
    }

    private var summary: String {
        let running = L("\(sessions) 个会话在跑", "\(sessions) session\(sessions == 1 ? "" : "s") running")
        guard let s = snapshot else { return L("还没有这一轮的 token 数据", "No token data for this turn yet") + " · " + running }
        return L("上下文剩 \(Int((s.remaining * 100).rounded()))%（已用 \(ClaudeStatus.compact(s.contextUsed)) / \(ClaudeStatus.compact(s.window))）",
                 "Context \(Int((s.remaining * 100).rounded()))% left (\(ClaudeStatus.compact(s.contextUsed)) of \(ClaudeStatus.compact(s.window)) used)")
            + " · " + running
    }
}

/// 演示模式（--present）的标记。演示画的是造出来的会话与题目，直接画在真屏幕上会被当成真的——
/// 2026-09-13 用户在灵动岛上看到演示里的选择题，去 Claude Code 里找不到对应的问题。
struct DemoMark: View {
    /// 折叠态两翼宽度有限，只放一个黄点；展开态和面板里写字。
    var compact = false

    var body: some View {
        // README 素材（--backdrop）的底色盖满整屏，不会被当成真屏幕上的会话，不画标记。
        if PresentDemo.seconds != nil, !Backdrop.isOn, compact {
            Circle().fill(Color.yellow).frame(width: 6, height: 6).help(L("演示数据", "Demo data"))
        } else if PresentDemo.seconds != nil, !Backdrop.isOn {
            Text(L("演示", "Demo"))
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Color.yellow, in: Capsule())
                .foregroundStyle(Color.black)
                .fixedSize()
        }
    }
}

/// 面板里拆开写的上下文：一根细胶囊表示已用多少。
struct ContextGauge: View {
    let used: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.quaternary)
                Capsule()
                    .fill(DuoGlyph.ringColor(1 - used))
                    .frame(width: max(3, g.size.width * used))
            }
        }
        .frame(width: 26, height: 4)
    }
}

/// 面板里拆开写的缓存命中：四个点。
struct CacheDots: View {
    let hit: Double

    var body: some View {
        let lit = ClaudeStatus.dots(cacheHit: hit)
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(i < lit ? Ink.primary : Ink.quaternary).frame(width: 4, height: 4)
            }
        }
    }
}

/// 这一轮的进度条。
///
/// 用户对前两版的评价：尺寸线式刻度尺「信息、刻度不错，视觉效果不好」；分段胶囊「颜色应该有区分」。
/// 这一版把两者合起来：上面是一根分段胶囊，三段用三种色相拉开（Apple 暗色系统色）——
/// 紫 = 按回车到写出理解、薄荷绿 = 写出理解之后、蓝 = Claude 在等你回应；段与段之间留 1pt 缝，
/// 工具调用是段内的细缝，白色圆点是写出理解的那一刻。下面是主次刻度和时间标注，右端是「现在 / 结束 / 撤回」。
/// 最下一行是各段时长的图例——颜色和数字挨在一起，不用对着色块去猜。
struct TurnBar: View {
    let timeline: TurnTimeline

    struct Segment: Equatable {
        enum Kind: Equatable, CaseIterable { case before, after, waiting }
        let kind: Kind
        let from: Double
        let to: Double
    }

    static func fraction(_ d: Date?, _ tl: TurnTimeline, now: Date) -> Double? {
        guard let d else { return nil }
        let total = max(now.timeIntervalSince(tl.startedAt), 1)
        return min(1, max(0, d.timeIntervalSince(tl.startedAt) / total))
    }

    static func segments(_ tl: TurnTimeline, now: Date) -> [Segment] {
        let d = fraction(tl.progress.declaredAt, tl, now: now)
        let c = tl.endedAt == nil ? fraction(tl.progress.pendingChoice?.at, tl, now: now) : nil
        let end = c ?? 1
        var out: [Segment] = []
        if let d, d < end {
            out.append(Segment(kind: .before, from: 0, to: d))
            out.append(Segment(kind: .after, from: d, to: end))
        } else {
            out.append(Segment(kind: .before, from: 0, to: end))
        }
        if let c { out.append(Segment(kind: .waiting, from: c, to: 1)) }
        return out
    }

    /// 主刻度步长：让主刻度间隔不小于约 56pt，按总时长取整数秒（1 秒 … 2 小时），不画假精度。
    static func majorStep(total: TimeInterval, width: CGFloat) -> TimeInterval {
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        let fit = max(2.0, Double(width / 56))
        return candidates.first { total / $0 <= fit } ?? 7200
    }

    static func color(_ k: Segment.Kind) -> Color {
        switch k {
        case .before: Color(red: 0.75, green: 0.35, blue: 0.95)     // systemPurple（暗色）
        case .after: Color(red: 0.0, green: 0.86, blue: 0.76)       // systemMint（暗色）
        case .waiting: Color(red: 0.04, green: 0.52, blue: 1.0)     // systemBlue（暗色）
        }
    }

    static func name(_ k: Segment.Kind) -> String {
        switch k {
        case .before: L("写出理解前", "Before reading")
        case .after: L("写出理解后", "After reading")
        case .waiting: L("等你回应", "Waiting on you")
        }
    }

    var body: some View {
        if let end = timeline.endedAt {
            content(now: end)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in content(now: ctx.date) }
        }
    }

    private func content(now: Date) -> some View {
        let segs = Self.segments(timeline, now: now)
        let total = max(now.timeIntervalSince(timeline.startedAt), 1)
        return VStack(alignment: .leading, spacing: 7) {
            // 高度要装下：轨道 5+8、刻度 3+5、标签 2+约 11。先前给 30，标签画到 34，下半截被裁（2026-09-13 实拍）。
            Canvas { ctx, size in draw(&ctx, size: size, segs: segs, total: total, now: now) }
                .frame(height: 36)
            legend(segs, total: total)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, segs: [Segment], total: TimeInterval, now: Date) {
        let w = size.width
        let barY: CGFloat = 5, barH: CGFloat = 8
        let track = Path(roundedRect: CGRect(x: 0, y: barY, width: w, height: barH), cornerRadius: barH / 2)
        ctx.fill(track, with: .color(Ink.fill))

        var bar = ctx
        bar.clip(to: track)
        for (i, s) in segs.enumerated() {
            let x0 = CGFloat(s.from) * w + (i > 0 ? 1 : 0)
            let x1 = CGFloat(s.to) * w
            guard x1 > x0 else { continue }
            bar.fill(Path(CGRect(x: x0, y: barY, width: x1 - x0, height: barH)), with: .color(Self.color(s.kind)))
        }
        for step in timeline.progress.steps.suffix(120) {
            guard let f = Self.fraction(step.at, timeline, now: now) else { continue }
            bar.fill(Path(CGRect(x: CGFloat(f) * w - 0.5, y: barY, width: 1, height: barH)), with: .color(.black.opacity(0.45)))
        }

        // 写出理解的那一刻：白色圆点压在两段交界处。
        if let d = Self.fraction(timeline.progress.declaredAt, timeline, now: now) {
            let x = min(max(5, CGFloat(d) * w), w - 5)
            let knob = Path(ellipseIn: CGRect(x: x - 5, y: barY + barH / 2 - 5, width: 10, height: 10))
            ctx.fill(knob, with: .color(.white))
            ctx.stroke(knob, with: .color(.black), lineWidth: 1.5)
        }

        // 刻度：主刻度带时间，次刻度五等分（间隔太密就不画）。
        let tickY = barY + barH + 3
        let major = Self.majorStep(total: total, width: w)
        let minor = major / 5
        func line(_ x: CGFloat, _ h: CGFloat, _ c: Color) {
            var p = Path(); p.move(to: CGPoint(x: x, y: tickY)); p.addLine(to: CGPoint(x: x, y: tickY + h))
            ctx.stroke(p, with: .color(c), lineWidth: 0.5)
        }
        if w * CGFloat(minor / total) >= 6 {
            var t = minor
            while t < total {
                if t.truncatingRemainder(dividingBy: major) > 0.01 { line(w * CGFloat(t / total), 2.5, Ink.quaternary) }
                t += minor
            }
        }
        let endWord = timeline.progress.interruptedAt != nil ? L("撤回", "Withdrawn")
            : (timeline.endedAt == nil ? L("现在", "Now") : L("结束", "Ended"))
        let endText = ctx.resolve(Text("\(endWord) \(Clock.text(total))").font(Ink.number(9.5, .semibold)).foregroundStyle(Ink.secondary))
        let endWidth = endText.measure(in: CGSize(width: 200, height: 20)).width
        var t: TimeInterval = 0
        while t <= total + 0.01 {
            let x = w * CGFloat(t / total)
            line(min(max(0.25, x), w - 0.25), 5, Ink.tertiary)
            if t == 0 || x < w - endWidth - 10 {
                let label = ctx.resolve(Text(t == 0 ? "0" : Clock.text(t)).font(Ink.number(9)).foregroundStyle(Ink.tertiary))
                ctx.draw(label, at: CGPoint(x: max(0, x), y: tickY + 7), anchor: t == 0 ? .topLeading : .top)
            }
            t += major
        }
        line(w - 0.25, 5, Ink.secondary)
        ctx.draw(endText, at: CGPoint(x: w, y: tickY + 7), anchor: .topTrailing)
    }

    private func legend(_ segs: [Segment], total: TimeInterval) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Self.color(s.kind))
                        .frame(width: 8, height: 8)
                    Text(Self.name(s.kind)).font(.system(size: 10.5)).foregroundStyle(Ink.secondary)
                    Text(Clock.text((s.to - s.from) * total)).font(Ink.number(10.5, .semibold)).foregroundStyle(Ink.primary)
                }
                .fixedSize()
            }
            Spacer(minLength: 6)
            Text(L("回车 ", "Sent ") + timeline.startedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                .font(Ink.number(10))
                .foregroundStyle(Ink.tertiary)
                .lineLimit(1)
        }
    }
}

/// 工具调用配 SF Symbol：一眼分得出是在跑命令、读文件还是改文件。
enum ToolSymbol {
    static func name(_ tool: String?) -> String {
        switch tool ?? "" {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": "pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Agent", "Task": "person.2"
        case "AskUserQuestion": "questionmark.bubble"
        case "ExitPlanMode", "TodoWrite": "checklist"
        default: "circle.dotted"
        }
    }
}
