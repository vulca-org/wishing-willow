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

/// Claude Code 状态的合一图标，照 iPhone Duo 角落里那个圆：外圈连续弧、中心扇形、底部四个点，
/// 三种形状不抢同一个视觉通道，所以挤在一个小圆里也分得开。
/// - 外圈弧：上下文还剩多少（像电量；剩 20% 变橙、10% 变红）；
/// - 中心扇形：最近一次写入距今多久（像 Wi-Fi，写得越近格数越多）；
/// - 底部四点：最近一次请求的缓存命中（像信号格）。
/// 小地方（刘海旁）用它；点击面板里拆回三个独立指标——iPhone Duo 在展开的大屏上也拆回三个图标。
struct ClaudeStatusGlyph: View {
    let snapshot: ClaudeStatus.Snapshot
    var size: CGFloat = 18

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let since = snapshot.lastWrite.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            glyph(live: ClaudeStatus.liveness(secondsSinceLastWrite: since))
        }
        .help(Self.summary(snapshot))
        .accessibilityElement()
        .accessibilityLabel(Self.summary(snapshot))
    }

    private func glyph(live: Double) -> some View {
        let lw = max(1.5, size * 0.09)
        let lit = ClaudeStatus.dots(cacheHit: snapshot.cacheHit)
        return ZStack {
            Circle().stroke(Ink.quaternary, lineWidth: lw)
            Circle()
                .trim(from: 0, to: max(0.02, snapshot.remaining))
                .stroke(Self.ringColor(snapshot.remaining), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "wifi", variableValue: live)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(Ink.primary)
                .offset(y: -size * 0.05)
            HStack(spacing: size * 0.05) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < lit ? Ink.primary : Ink.quaternary)
                        .frame(width: size * 0.085, height: size * 0.085)
                }
            }
            .offset(y: size * 0.23)
        }
        .padding(lw / 2)
        .frame(width: size, height: size)
    }

    static func ringColor(_ remaining: Double) -> Color {
        switch ClaudeStatus.level(remaining: remaining) {
        case .critical: .red
        case .low: .orange
        case .normal: Ink.primary
        }
    }

    static func summary(_ s: ClaudeStatus.Snapshot) -> String {
        "上下文剩 \(Int((s.remaining * 100).rounded()))%（已用 \(ClaudeStatus.compact(s.contextUsed)) / \(ClaudeStatus.compact(s.window))）"
            + " · 缓存命中 \(Int((s.cacheHit * 100).rounded()))% · 本轮输出 \(ClaudeStatus.compact(s.outputTokens))"
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
                    .fill(ClaudeStatusGlyph.ringColor(1 - used))
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

/// 这一轮的进度条：一根胶囊，分段着色，两端写起止时间。Apple 的做法（音乐的播放进度条、屏幕使用时间的分段条），
/// 不画刻度——精确的数写在分节标题右侧。
/// 灰 = 按回车到写出理解；白 = 写出理解之后；蓝 = Claude 在等你选择。白色圆点是写出理解的那一刻，细缝是每一次工具调用。
struct TurnBar: View {
    let timeline: TurnTimeline

    struct Segment: Equatable {
        enum Kind: Equatable { case before, after, waiting }
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

    var body: some View {
        if let end = timeline.endedAt {
            bar(now: end)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in bar(now: ctx.date) }
        }
    }

    private func bar(now: Date) -> some View {
        let segs = Self.segments(timeline, now: now)
        let steps = timeline.progress.steps.suffix(80).compactMap { Self.fraction($0.at, timeline, now: now) }
        let decl = Self.fraction(timeline.progress.declaredAt, timeline, now: now)
        let total = max(now.timeIntervalSince(timeline.startedAt), 0)
        let endWord = timeline.progress.interruptedAt != nil ? "撤回" : (timeline.endedAt == nil ? "现在" : "结束")
        return VStack(spacing: 5) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.fill)
                    ForEach(Array(segs.enumerated()), id: \.offset) { _, s in
                        Rectangle()
                            .fill(Self.color(s.kind))
                            .frame(width: max(0, CGFloat(s.to - s.from) * w))
                            .offset(x: CGFloat(s.from) * w)
                    }
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, f in
                        Rectangle().fill(Color.black.opacity(0.6)).frame(width: 1).offset(x: CGFloat(f) * w)
                    }
                }
                .clipShape(Capsule())
                .overlay(alignment: .leading) {
                    if let decl {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                            .offset(x: min(max(0, CGFloat(decl) * w - 4), max(0, w - 8)))
                    }
                }
            }
            .frame(height: 6)
            HStack {
                Text("回车 " + timeline.startedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                Spacer(minLength: 8)
                Text("\(endWord) \(Clock.text(total))")
            }
            .font(Ink.number(10))
            .foregroundStyle(Ink.tertiary)
        }
    }

    static func color(_ k: Segment.Kind) -> Color {
        switch k {
        case .before: Color.white.opacity(0.3)
        case .after: Color.white.opacity(0.85)
        case .waiting: ChoiceCard.accent
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
