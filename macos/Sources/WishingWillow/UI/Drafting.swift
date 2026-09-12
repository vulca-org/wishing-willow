import SwiftUI

/// 图纸语言：细线、引出编号、引线、尺寸线、刻度尺、图签。
///
/// 用户要「类似工程建筑导图的设计方法」。图纸的规矩和这个 app 要做的事对得上：
/// 图纸上每一根尺寸线都量着一个实物，不画没有依据的东西。这里的每个标注也只指向读得到的事实——
/// 时间戳、用时、步数、轮次——不画装饰。
enum Ink {
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.64)
    static let note = Color.white.opacity(0.42)
    static let faint = Color.white.opacity(0.28)
    static let rule = Color.white.opacity(0.16)
    static let hairline = Color.white.opacity(0.09)
    static let hair: CGFloat = 0.5

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// 引出编号。只用在真的有先后的地方：你说的 → 模型读成的 → 模型在做的。
struct Callout: View {
    let number: Int
    var tint: Color = Ink.secondary

    var body: some View {
        Text("\(number)")
            .font(Ink.mono(8.5, .semibold))
            .foregroundStyle(tint)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(tint, lineWidth: 0.75))
    }
}

/// 引线：从分节标题一路引到右侧的标注。
struct LeaderLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// 分节标题：编号 · 标题 ┄┄┄┄ 右侧标注。右侧只放可以核对的数。
struct SectionHeader: View {
    var number: Int? = nil
    let title: String
    var note: String? = nil
    var noteTint: Color = Ink.note
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let number { Callout(number: number) }
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Ink.secondary)
                .fixedSize()
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.white.opacity(0.85))
                    .fixedSize()
            }
            LeaderLine()
                .stroke(Ink.rule, style: StrokeStyle(lineWidth: Ink.hair, dash: [2, 2.5]))
                .frame(minWidth: 12, maxWidth: .infinity)
                .frame(height: 1)
            if let note {
                Text(note)
                    .font(Ink.mono(9.5))
                    .foregroundStyle(noteTint)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 14)
    }
}

/// 角码：四角的 L 形短线，框出一块测量区域。
struct CornerMarks: Shape {
    var length: CGFloat = 6

    func path(in r: CGRect) -> Path {
        let l = length
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

/// 图纸底纹：点阵，淡到只在空处看得见。所有点并成一条路径一次填充。
struct DotGrid: View {
    var spacing: CGFloat = 10

    var body: some View {
        Canvas { ctx, size in
            var dots = Path()
            var y = spacing / 2
            while y < size.height {
                var x = spacing / 2
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(dots, with: .color(Color.white.opacity(0.07)))
        }
        .allowsHitTesting(false)
    }
}

/// 图签里的一格：上面小号等宽的栏名，下面值。
struct TitleCell: View {
    let label: String
    let value: String
    var valueTint: Color = Ink.primary
    var mono = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(Ink.mono(8))
                .tracking(0.6)
                .foregroundStyle(Ink.note)
            Text(value)
                .font(mono ? Ink.mono(10.5) : .system(size: 11, weight: .medium))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

/// 图签的竖分隔线。
struct TitleRule: View {
    var body: some View { Rectangle().fill(Ink.rule).frame(width: Ink.hair) }
}

/// 展开时各块从上到下依次出现，每块从自己的上边中点长出来（由内向外）。
struct Reveal: ViewModifier {
    let order: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.95, anchor: .top)
            .offset(y: shown ? 0 : -6)
            .blur(radius: shown ? 0 : 4)
            .animation(.spring(response: 0.4, dampingFraction: 0.88).delay(0.06 + 0.045 * Double(order)), value: shown)
    }
}

extension View {
    func reveal(_ order: Int, _ shown: Bool) -> some View { modifier(Reveal(order: order, shown: shown)) }
}

/// 这一轮的时间刻度尺。0 是按回车那一刻；右端是现在（进行中）、结束或撤回。
///
/// 上一行是尺寸线：「回车 → 声明」用了多久、声明之后又跑了多久。中间是基线与刻度，
/// 基线上方的短竖线是每一次工具调用，▼ 是声明写出的时刻，蓝色粗段是在等你选择。
/// 刻度步长按总时长挑整数（1 秒 … 2 小时），不画假精度。
struct TimelineRuler: View {
    let timeline: TurnTimeline

    var body: some View {
        if let end = timeline.endedAt {
            RulerCanvas(timeline: timeline, now: end)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                RulerCanvas(timeline: timeline, now: ctx.date)
            }
        }
    }

    /// 主刻度步长：让主刻度间隔不小于约 64pt。
    static func majorStep(total: TimeInterval, width: CGFloat) -> TimeInterval {
        let candidates: [TimeInterval] = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200]
        let fit = max(2.0, Double(width / 64))
        return candidates.first { total / $0 <= fit } ?? 7200
    }
}

struct RulerCanvas: View {
    let timeline: TurnTimeline
    let now: Date
    static let height: CGFloat = 54

    var body: some View {
        Canvas { ctx, size in
            let start = timeline.startedAt
            let total = max(now.timeIntervalSince(start), 1)
            let left: CGFloat = 0.5, right = size.width - 0.5
            let p = timeline.progress
            let dimY: CGFloat = 6, base: CGFloat = 27

            func x(_ d: Date?) -> CGFloat? {
                guard let d else { return nil }
                let t = min(max(d.timeIntervalSince(start), 0), total)
                return left + (right - left) * CGFloat(t / total)
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ w: CGFloat = Ink.hair) {
                var path = Path(); path.move(to: a); path.addLine(to: b)
                ctx.stroke(path, with: .color(color), lineWidth: w)
            }
            func label(_ s: String, _ size: CGFloat = 8.5) -> Text {
                Text(s).font(Ink.mono(size))
            }
            func width(_ s: String) -> CGFloat {
                ctx.resolve(label(s)).measure(in: CGSize(width: 1000, height: 40)).width
            }
            func draw(_ s: String, _ pt: CGPoint, _ anchor: UnitPoint, _ color: Color) {
                ctx.draw(label(s).foregroundStyle(color), at: pt, anchor: anchor)
            }
            /// 尺寸线：两端竖短线，数值标在线的中间断开处；放不下就引到右侧。返回标注右缘。
            @discardableResult
            func dimension(_ xa: CGFloat, _ xb: CGFloat, _ text: String, _ color: Color, after: CGFloat = 0) -> CGFloat {
                line(CGPoint(x: xa, y: dimY - 3.5), CGPoint(x: xa, y: dimY + 3.5), color)
                line(CGPoint(x: xb, y: dimY - 3.5), CGPoint(x: xb, y: dimY + 3.5), color)
                let w = width(text)
                if xb - xa >= w + 12, (xa + xb) / 2 - w / 2 - 3 > after {
                    let mid = (xa + xb) / 2
                    line(CGPoint(x: xa, y: dimY), CGPoint(x: mid - w / 2 - 4, y: dimY), color)
                    line(CGPoint(x: mid + w / 2 + 4, y: dimY), CGPoint(x: xb, y: dimY), color)
                    draw(text, CGPoint(x: mid, y: dimY), .center, color)
                    return mid + w / 2
                }
                line(CGPoint(x: xa, y: dimY), CGPoint(x: xb, y: dimY), color)
                let at = max(xb + 4, after + 8)
                guard at + w <= size.width else { return after }
                draw(text, CGPoint(x: at, y: dimY), .leading, color)
                return at + w
            }

            // 上：尺寸线
            let xe = right
            if let xd = x(p.declaredAt), let dAt = p.declaredAt {
                let used = dimension(left, xd, "回车→声明 " + Clock.text(dAt.timeIntervalSince(start)), Ink.secondary)
                if xe - xd > 24 {
                    dimension(xd, xe, "声明后 " + Clock.text(now.timeIntervalSince(dAt)), Ink.note, after: used)
                }
            } else {
                let text = timeline.endedAt == nil ? "还没写出声明 " : "这一轮没有声明 "
                dimension(left, xe, text + Clock.text(total), timeline.endedAt == nil ? Ink.note : Color.orange.opacity(0.8))
            }

            // 中：基线与刻度
            line(CGPoint(x: left, y: base), CGPoint(x: right, y: base), Ink.faint, 0.75)
            let major = TimelineRuler.majorStep(total: total, width: right - left)
            let minor = major / 5
            if (right - left) * CGFloat(minor / total) >= 5 {
                var t = minor
                while t < total {
                    if t.truncatingRemainder(dividingBy: major) > 0.001, let xm = x(start.addingTimeInterval(t)) {
                        line(CGPoint(x: xm, y: base), CGPoint(x: xm, y: base + 2.5), Ink.hairline)
                    }
                    t += minor
                }
            }
            var t: TimeInterval = 0
            while t <= total + 0.001 {
                if let xm = x(start.addingTimeInterval(t)) {
                    line(CGPoint(x: xm, y: base), CGPoint(x: xm, y: base + 5), Ink.faint)
                    if xe - xm > 26 || t == 0 {
                        let anchor: UnitPoint = xm < 12 ? .topLeading : .top
                        draw(t == 0 ? "0" : Clock.text(t), CGPoint(x: xm, y: base + 7), anchor, Ink.note)
                    }
                }
                t += major
            }

            // 工具调用：基线上方的短竖线
            for step in p.steps {
                if let xs = x(step.at) {
                    line(CGPoint(x: xs, y: base - 6), CGPoint(x: xs, y: base), Color.white.opacity(0.5), 1)
                }
            }

            // 等你选择：从提问到现在的蓝色粗段 + 菱形
            if timeline.endedAt == nil, let c = p.pendingChoice, let xc = x(c.at) {
                line(CGPoint(x: xc, y: base), CGPoint(x: xe, y: base), ChoiceCard.accent, 2)
                var diamond = Path()
                diamond.move(to: CGPoint(x: xc, y: base - 4)); diamond.addLine(to: CGPoint(x: xc + 4, y: base))
                diamond.addLine(to: CGPoint(x: xc, y: base + 4)); diamond.addLine(to: CGPoint(x: xc - 4, y: base)); diamond.closeSubpath()
                ctx.fill(diamond, with: .color(ChoiceCard.accent))
            }

            // 声明：▼
            if let xd = x(p.declaredAt) {
                var tri = Path()
                tri.move(to: CGPoint(x: xd - 4, y: base - 10)); tri.addLine(to: CGPoint(x: xd + 4, y: base - 10))
                tri.addLine(to: CGPoint(x: xd, y: base - 3)); tri.closeSubpath()
                ctx.fill(tri, with: .color(p.decode?.hasPrefix("⚠") == true ? Color.orange : Color.white))
            }

            // 右端游标与下行的起止标注
            line(CGPoint(x: xe, y: 13), CGPoint(x: xe, y: size.height - 11), Ink.secondary, 0.75)
            let endWord = timeline.progress.interruptedAt != nil ? "撤回" : (timeline.endedAt == nil ? "现在" : "结束")
            draw(endWord + " " + Clock.text(total), CGPoint(x: xe, y: size.height), .bottomTrailing, Ink.secondary)
            draw("回车 " + start.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second()),
                 CGPoint(x: left, y: size.height), .bottomLeading, Ink.note)
        }
        .frame(height: Self.height)
    }
}
