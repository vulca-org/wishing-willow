import SwiftUI

/// 点击灵动岛之后的面板——灵动岛本身再长大一档，不是另开一个窗口。
///
/// 用户实测原来的面板「跳脱」：灰色标准窗口、红黄绿按钮、中间一道分隔线；左侧两个会话同名分不清、
/// 标题和副标题重复；时长写成「1,911 秒」；也没有「你批准的 / 我读成了」。这里逐条改。
/// 再一轮（「不要有空的地方」）：标题挪进刘海两侧；左栏补上这个会话各轮时长柱与结局计数。
/// 再一轮（「类似工程建筑导图」）：点阵底纹、分节引线、每轮标题行一条引线引到用时、底部图签；
/// 进行中那一轮画时间刻度尺。
struct DetailView: View {
    let store: WillowStore
    let seen: SeenStore
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    var onClose: (() -> Void)? = nil
    @State private var picked: String?
    @State private var shown = Offscreen.isRendering

    /// 含两侧凹肩的形状尺寸；内容宽 = 宽 − 2 × 19。
    static let size = CGSize(width: 600, height: 470)

    private var sessions: [SessionState] { store.sessions }
    private var current: SessionState? {
        if let picked, let s = sessions.first(where: { $0.id == picked }) { return s }
        return sessions.first
    }

    var body: some View {
        let entries = current.map { TurnLog.read(sessionId: $0.id, directory: store.directory) } ?? []
        let running = current.flatMap { s in s.declaration == .inProgress ? store.timeline(for: s)?.startedAt : nil }
        ZStack(alignment: .top) {
            DotGrid()
                .padding(.top, notchHeight)
                .opacity(shown ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: shown)
            VStack(alignment: .leading, spacing: 0) {
                ears.reveal(0, shown)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "会话", note: "\(sessions.count) 个 · 按最近动静")
                        // 列表按会话数定高、多了才滚；剩下的高度全给统计卡。
                        sessionList.frame(height: min(CGFloat(sessions.count) * 40, 200), alignment: .top)
                        SessionSummary(entries: entries, runningSince: running).frame(maxHeight: .infinity)
                    }
                    .frame(width: 188)
                    .reveal(1, shown)

                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "轮次", note: rangeNote(entries))
                        turnList(entries)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .reveal(2, shown)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                titleBlock(entries)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .reveal(3, shown)
            }
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
        .onAppear { DispatchQueue.main.async { shown = true } }
    }

    // MARK: 刘海两侧

    private var ears: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("最近的轮次").font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                if let s = current {
                    Text(s.workspace)
                        .font(.system(size: 10.5)).foregroundStyle(Ink.note)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let onClose {
                    Button(action: onClose) {
                        Text("收起")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 10).padding(.trailing, 16)
            .frame(maxWidth: .infinity)
        }
        .frame(height: notchHeight)
    }

    // MARK: 会话

    private var sessionList: some View {
        let counts = Dictionary(sessions.map { ($0.workspace, 1) }, uniquingKeysWith: +)
        let dupes = Set(counts.filter { $0.value > 1 }.keys)
        return scrollable {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(sessions) { s in sessionRow(s, dupes: dupes) }
            }
        }
    }

    /// 标题用标签——工作区名说的是「在哪」，不是「在做什么」。右侧是会话号前四位（等宽，可以和图签对上）。
    private func sessionRow(_ s: SessionState, dupes: Set<String>) -> some View {
        let selected = s.id == current?.id
        // 进行中的一轮：状态文件里还没有标签（整轮结束才写），实时读到的先用上。
        let title = store.progress(for: s)?.tag ?? s.tag ?? FocusRule.lastLoggedTag(s, store) ?? "还没有标签"
        let sub = s.record.updatedAt.map { "\(s.workspace) · \(Self.ago($0))" } ?? s.workspace
        return HStack(alignment: .top, spacing: 7) {
            Circle().fill(dotColor(s)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(s.isStale ? 0.5 : 1))
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Ink.note)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Text(String(s.id.prefix(4)))
                .font(Ink.mono(9))
                .foregroundStyle(dupes.contains(s.workspace) ? Ink.secondary : Ink.faint)
                .padding(.top, 2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.white.opacity(0.1) : Color.clear, in: Rectangle())
        .overlay(alignment: .leading) {
            if selected { Rectangle().fill(Color.white.opacity(0.8)).frame(width: 1.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture { picked = s.id }
    }

    private func dotColor(_ s: SessionState) -> Color {
        if s.isStale { return Color.white.opacity(0.25) }
        if s.declaration == .unreadable { return .red }
        if store.progress(for: s)?.pendingChoice != nil { return ChoiceCard.accent }
        if s.declaration == .inProgress { return Color.white.opacity(0.7) }
        if s.flaggedByModel || s.declaration == .undeclared { return .orange }
        return seen.isUnread(s) ? .white : Color.white.opacity(0.35)
    }

    // MARK: 轮次

    private func rangeNote(_ entries: [TurnLogEntry]) -> String? {
        let times = entries.compactMap(\.at)
        guard let first = times.min(), let last = times.max() else { return nil }
        return "\(IslandExpandedContent.clock(first))–\(IslandExpandedContent.clock(last)) · \(entries.count) 轮"
    }

    private func turnList(_ entries: [TurnLogEntry]) -> some View {
        let history = Array(entries.reversed())
        // 进行中的这一轮还没进日志（日志在整轮结束才写）——从状态里补一行，免得看起来像漏记。
        let live: SessionState? = {
            guard let s = current, s.declaration == .inProgress, let turn = s.record.turnId,
                  !entries.contains(where: { $0.turnId == turn }) else { return nil }
            return s
        }()
        return scrollable {
            VStack(alignment: .leading, spacing: 0) {
                if let s = live { liveRow(s) }
                if history.isEmpty && live == nil {
                    Text("这个会话还没有记录下来的轮次。")
                        .font(.system(size: 12)).foregroundStyle(Ink.note).padding(.top, 6)
                }
                ForEach(history) { t in turnRow(t) }
            }
        }
    }

    private func liveRow(_ s: SessionState) -> some View {
        let p = store.progress(for: s)
        return VStack(alignment: .leading, spacing: 4) {
            rowHeader(time: s.record.updatedAt, tag: p?.tag ?? s.tag, badge: "进行中") {
                if let start = s.record.updatedAt { LiveClock(since: start, size: 10.5, opacity: 0.45) }
            }
            if s.record.isSystemMessage {
                inline("批准", "系统消息（\(PromptSource.describe(s.prompt))），不是你说的", Ink.note)
            } else {
                inline("批准", s.prompt ?? "—", Color.white)
            }
            if let d = p?.decode {
                inline("读成", d, d.hasPrefix("⚠") ? Color.orange : Color.white.opacity(0.85))
            } else {
                inline("读成", IslandExpandedContent.phase(p), Ink.note)
            }
            if let tl = store.timeline(for: s) {
                VStack(alignment: .leading, spacing: 5) {
                    if let c = p?.pendingChoice { ChoiceCard(choice: c) }
                    TimelineRuler(timeline: tl)
                    if !tl.progress.steps.isEmpty { StepList(timeline: tl, limit: 3) }
                }
                .padding(.leading, 30)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: Ink.hair) }
    }

    private func turnRow(_ t: TurnLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            rowHeader(time: t.at, tag: t.tag, badge: t.interrupted == true ? "被打断" : nil) {
                if let d = t.duration, d >= 1 {
                    Text(Self.duration(d)).font(Ink.mono(9.5)).foregroundStyle(Ink.note)
                }
            }
            if t.isSystemMessage {
                inline("批准", "系统消息（\(PromptSource.describe(t.prompt))），不是你说的", Ink.note)
            } else {
                inline("批准", t.prompt ?? "—", Color.white)
            }
            decodeLine(t)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.hairline).frame(height: Ink.hair) }
    }

    /// 每轮的标题行：等宽时刻 · 标签 · 徽标 ┄┄┄┄ 右侧的数（用时或走动的计时）。
    private func rowHeader(time: Date?, tag: String?, badge: String?, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 6) {
            if let time {
                Text(time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .font(Ink.mono(10)).foregroundStyle(Ink.note)
                    .fixedSize()
            }
            if let tag {
                Text(tag).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(1)
            }
            if let badge { self.badge(badge) }
            LeaderLine()
                .stroke(Ink.rule, style: StrokeStyle(lineWidth: Ink.hair, dash: [2, 2.5]))
                .frame(minWidth: 10, maxWidth: .infinity)
                .frame(height: 1)
            trailing()
        }
    }

    /// 「被打断」「问了没答」「没问」「不知道」必须是不同的话——合成一句「无声明」就是在制造沉默。
    @ViewBuilder
    private func decodeLine(_ t: TurnLogEntry) -> some View {
        if t.declared {
            inline("读成", t.decode ?? "", t.flaggedByModel ? Color.orange : Color.white.opacity(0.85))
        } else if t.interrupted == true {
            inline("读成", "被打断，没来得及写声明", Ink.note)
        } else if t.reminded == true {
            inline("读成", "问了，模型没写声明", Color.orange)
        } else if t.reminded == false {
            inline("读成", "这一轮没问（太短或是系统消息）", Ink.note)
        } else {
            inline("读成", "不知道这一轮问没问", Ink.note)
        }
    }

    // MARK: 图签

    private func titleBlock(_ entries: [TurnLogEntry]) -> some View {
        let asked = entries.filter { $0.reminded == true && $0.interrupted != true }
        let wrote = asked.filter(\.declared).count
        let longest = entries.compactMap(\.duration).max()
        return HStack(spacing: 0) {
            TitleCell(label: "工作区", value: current?.workspace ?? "—").frame(maxWidth: .infinity, alignment: .leading)
            TitleRule()
            TitleCell(label: "会话", value: current.map { String($0.id.prefix(8)) } ?? "—", mono: true)
                .frame(width: 90, alignment: .leading)
            TitleRule()
            // 日志每个会话只留最近 20 轮（插件 LOG_KEEP），写出来，免得把「只有这些」读成「一共这些」。
            TitleCell(label: "记录", value: "\(entries.count) 轮 · 上限 20").frame(width: 104, alignment: .leading)
            TitleRule()
            TitleCell(label: "写了声明", value: asked.isEmpty ? "—" : "\(wrote)/\(asked.count)").frame(width: 70, alignment: .leading)
            TitleRule()
            TitleCell(label: "最长一轮", value: longest.map(Self.duration) ?? "—").frame(width: 96, alignment: .leading)
        }
        .frame(height: 34)
        .overlay(Rectangle().stroke(Ink.rule, lineWidth: Ink.hair))
        .overlay(CornerMarks(length: 5).stroke(Ink.secondary, lineWidth: 0.75))
    }

    // MARK: 小件

    private func inline(_ label: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Ink.note)
                .frame(width: 24, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private func badge(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Color.white.opacity(0.14), in: Capsule())
            .foregroundStyle(Color.white.opacity(0.85))
            .fixedSize()
    }

    /// ScrollView 在离屏渲染里不布局（整块消失），快照走等价的平铺。
    @ViewBuilder
    private func scrollable(@ViewBuilder _ content: () -> some View) -> some View {
        if Offscreen.isRendering { content() } else { ScrollView { content() }.scrollIndicators(.hidden) }
    }

    static func duration(_ d: TimeInterval) -> String {
        let s = Int(d.rounded())
        if s < 60 { return "\(s) 秒" }
        let m = s / 60, r = s % 60
        if m < 60 { return r == 0 ? "\(m) 分" : "\(m) 分 \(r) 秒" }
        return "\(m / 60) 小时 \(m % 60) 分"
    }

    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60) 分钟前" }
        if s < 86400 { return "\(s / 3600) 小时前" }
        return "\(s / 86400) 天前"
    }
}

/// 这个会话最近各轮：每轮一根柱，高度是时长（对数刻度，1 秒到 1 小时），颜色是结局。
/// 柱下面是五种结局的计数——「写了声明」和「问了没写」放在一起看，比一行行翻快。
struct SessionSummary: View {
    let entries: [TurnLogEntry]      // 旧 → 新
    /// 进行中那一轮按回车的时刻：日志要整轮结束才写，这一轮画成最右边一根虚线柱，按实时时长长高。
    var runningSince: Date? = nil

    enum Outcome: CaseIterable { case declared, flagged, silent, notAsked, interrupted }

    static func outcome(_ e: TurnLogEntry) -> Outcome? {
        if e.interrupted == true { return .interrupted }
        if e.declared { return e.flaggedByModel ? .flagged : .declared }
        if e.reminded == true { return .silent }
        if e.reminded == false { return .notAsked }
        return nil
    }

    private static func name(_ o: Outcome) -> String {
        switch o {
        case .declared: "写了声明"
        case .flagged: "模型自标 ⚠"
        case .silent: "问了没写"
        case .notAsked: "没问"
        case .interrupted: "被打断"
        }
    }

    private static func color(_ o: Outcome?) -> Color {
        switch o {
        case .declared: Color.white.opacity(0.85)
        case .flagged: .orange
        case .silent: Color(red: 1, green: 0.42, blue: 0.36)
        case .notAsked: Color.white.opacity(0.28)
        case .interrupted: Color.white.opacity(0.5)
        case nil: Color.white.opacity(0.18)
        }
    }

    /// 对数刻度上的位置：1 秒 = 0，1 分 = 0.5，1 小时 = 1。时长不知道的轮次返回 nil，画成最矮的灰柱，不假装知道。
    static func level(_ e: TurnLogEntry) -> CGFloat? {
        guard let d = e.duration, d > 0 else { return nil }
        return level(duration: d)
    }

    static func level(duration d: TimeInterval) -> CGFloat {
        CGFloat(min(1, max(0, log10(max(d, 1)) / log10(3600))))
    }

    private struct Tick: Hashable { let name: String; let level: CGFloat }
    private static let ticks = [Tick(name: "1 秒", level: 0), Tick(name: "1 分", level: 0.5), Tick(name: "1 时", level: 1)]

    /// 柱与刻度线用同一把尺子，随可用高度缩放：卡片把左栏剩下的高度吃满，图就跟着长高。
    private var chart: some View {
        GeometryReader { geo in
            let plot = max(0, geo.size.height - 1)
            ZStack(alignment: .bottomLeading) {
                ForEach(Self.ticks, id: \.self) { t in
                    HStack(spacing: 4) {
                        Rectangle().fill(Color.white.opacity(t.level == 0 ? 0.16 : 0.08)).frame(height: 0.5)
                        Text(t.name)
                            .font(Ink.mono(8.5))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .frame(width: 22, alignment: .leading)
                    }
                    .frame(height: 10)
                    .offset(y: 5 - plot * t.level)       // 线在这一行的竖直中点，对准刻度位置
                }
                HStack(alignment: .bottom, spacing: 2) {
                    if entries.isEmpty && runningSince == nil {
                        Text("还没有记录").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.3))
                        Spacer(minLength: 0)
                    }
                    ForEach(entries) { e in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(Self.color(Self.outcome(e)))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, plot * (Self.level(e) ?? 0)))
                    }
                    if let since = runningSince {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(3, plot * Self.level(duration: ctx.date.timeIntervalSince(since))))
                        }
                        .frame(maxWidth: entries.isEmpty ? 14 : .infinity)
                    }
                    if entries.isEmpty && runningSince != nil { Spacer(minLength: 0) }
                }
                .padding(.trailing, 26)                 // 给刻度字留位
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("各轮时长")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Ink.secondary)
                Text("对数刻度").font(Ink.mono(8.5)).foregroundStyle(Ink.note)
                Spacer(minLength: 0)
                // 卡片只有 188pt 宽：两句并排会折成两行挤着标题，有进行中的轮次时只说虚线是什么。
                Text(runningSince == nil ? "旧 → 新" : "虚线=进行中").font(Ink.mono(8.5)).foregroundStyle(Ink.note)
                    .lineLimit(1).fixedSize()
            }

            chart
                .frame(minHeight: 48, maxHeight: .infinity)
                .padding(.top, 4)

            let counts = Dictionary(grouping: entries.compactMap(Self.outcome)) { $0 }.mapValues(\.count)
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 3) {
                ForEach(Outcome.allCases, id: \.self) { o in
                    GridRow {
                        Circle().fill(Self.color(o)).frame(width: 6, height: 6)
                        Text(Self.name(o)).font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.6))
                        Text("\(counts[o] ?? 0)")
                            .font(Ink.mono(10.5, .semibold))
                            .foregroundStyle(Color.white.opacity((counts[o] ?? 0) > 0 ? 0.9 : 0.3))
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(Rectangle().fill(Color.white.opacity(0.035)))
        .overlay(Rectangle().stroke(Ink.hairline, lineWidth: Ink.hair))
        .overlay(CornerMarks(length: 5).stroke(Ink.faint, lineWidth: 0.75))
    }
}
