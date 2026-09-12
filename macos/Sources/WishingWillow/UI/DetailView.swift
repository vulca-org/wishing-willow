import SwiftUI

/// 点击灵动岛之后的面板——灵动岛本身再长大一档，不是另开一个窗口。
///
/// 用户实测原来的面板「跳脱」：灰色标准窗口、红黄绿按钮、中间一道分隔线；左侧两个会话同名分不清、
/// 标题和副标题重复；时长写成「1,911 秒」；也没有「你批准的 / 我读成了」。这里逐条改。
/// 再一轮（「不要有空的地方」）：标题挪进刘海两侧；左栏会话少时下面整块空着，补上这个会话最近各轮的
/// 时长柱与结局计数；右栏每轮压成三行（时间·标签·时长 / 批准 / 读成）。
struct DetailView: View {
    let store: WillowStore
    let seen: SeenStore
    var notchWidth: CGFloat = 185
    var notchHeight: CGFloat = 32
    var onClose: (() -> Void)? = nil
    @State private var picked: String?

    /// 含两侧凹肩的形状尺寸；内容宽 = 宽 − 2 × 19。
    static let size = CGSize(width: 600, height: 470)

    private var sessions: [SessionState] { store.sessions }
    private var current: SessionState? {
        if let picked, let s = sessions.first(where: { $0.id == picked }) { return s }
        return sessions.first
    }

    var body: some View {
        let entries = current.map { TurnLog.read(sessionId: $0.id, directory: store.directory) } ?? []
        VStack(alignment: .leading, spacing: 0) {
            ears
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    // 列表按会话数定高、多了才滚；剩下的高度全给统计卡——先前列表吃满高度，中间空一大块。
                    sessionList.frame(height: min(CGFloat(sessions.count) * 42, 210), alignment: .top)
                    SessionSummary(entries: entries).frame(maxHeight: .infinity)
                }
                .frame(width: 188)
                turnList(entries).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: 刘海两侧

    private var ears: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("最近的轮次").font(.system(size: 12, weight: .semibold))
                Text("\(sessions.count) 个会话").font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.4))
                Spacer(minLength: 0)
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 6) {
                if let s = current {
                    Text(s.workspace)
                        .font(.system(size: 10.5)).foregroundStyle(Color.white.opacity(0.4))
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

    /// 标题用标签——工作区名说的是「在哪」，不是「在做什么」。同名工作区后面加会话号前四位。
    private func sessionRow(_ s: SessionState, dupes: Set<String>) -> some View {
        let selected = s.id == current?.id
        let title = s.tag ?? FocusRule.lastLoggedTag(s, store) ?? "还没有标签"
        let place = dupes.contains(s.workspace) ? "\(s.workspace) · \(s.id.prefix(4))" : s.workspace
        let sub = s.record.updatedAt.map { "\(place) · \(Self.ago($0))" } ?? place
        return HStack(alignment: .top, spacing: 7) {
            Circle().fill(dotColor(s)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(s.isStale ? 0.5 : 1))
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.white.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { picked = s.id }
    }

    private func dotColor(_ s: SessionState) -> Color {
        if s.isStale { return Color.white.opacity(0.25) }
        if s.declaration == .unreadable { return .red }
        if s.declaration == .inProgress { return Color.white.opacity(0.7) }
        if s.flaggedByModel || s.declaration == .undeclared { return .orange }
        return seen.isUnread(s) ? .white : Color.white.opacity(0.35)
    }

    // MARK: 轮次

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
                        .font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.45)).padding(.top, 6)
                }
                ForEach(history) { t in turnRow(t) }
            }
        }
    }

    private func liveRow(_ s: SessionState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                badge("进行中")
                if let t = store.progress(for: s)?.tag ?? s.tag {
                    Text(t).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                }
                Spacer(minLength: 0)
                if let start = s.record.updatedAt { LiveClock(since: start, size: 10.5, opacity: 0.45) }
            }
            if s.record.isSystemMessage {
                inline("批准", "系统消息（\(PromptSource.describe(s.prompt))），不是你说的", Color.white.opacity(0.45))
            } else {
                inline("批准", s.prompt ?? "—", Color.white)
            }
            LiveTurnSection(started: s.record.updatedAt, progress: store.progress(for: s))
                .padding(.leading, 30)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    }

    private func turnRow(_ t: TurnLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let at = t.at {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.system(size: 10.5, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                if let tag = t.tag {
                    Text(tag).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Color.white.opacity(0.85))
                }
                if t.interrupted == true { badge("被打断") }
                Spacer(minLength: 0)
                if let d = t.duration, d >= 1 {
                    Text(Self.duration(d))
                        .font(.system(size: 10.5)).monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.38))
                }
            }
            if t.isSystemMessage {
                inline("批准", "系统消息（\(PromptSource.describe(t.prompt))），不是你说的", Color.white.opacity(0.45))
            } else {
                inline("批准", t.prompt ?? "—", Color.white)
            }
            decodeLine(t)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    }

    /// 「被打断」「问了没答」「没问」「不知道」必须是不同的话——合成一句「无声明」就是在制造沉默。
    @ViewBuilder
    private func decodeLine(_ t: TurnLogEntry) -> some View {
        if t.declared {
            inline("读成", t.decode ?? "", t.flaggedByModel ? Color.orange : Color.white.opacity(0.85))
        } else if t.interrupted == true {
            inline("读成", "被打断，没来得及写声明", Color.white.opacity(0.45))
        } else if t.reminded == true {
            inline("读成", "问了，模型没写声明", Color.orange)
        } else if t.reminded == false {
            inline("读成", "这一轮没问（太短或是系统消息）", Color.white.opacity(0.4))
        } else {
            inline("读成", "不知道这一轮问没问", Color.white.opacity(0.4))
        }
    }

    // MARK: 小件

    private func inline(_ label: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.36))
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
        return CGFloat(min(1, max(0, log10(max(d, 1)) / log10(3600))))
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
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .frame(width: 22, alignment: .leading)
                    }
                    .frame(height: 10)
                    .offset(y: 5 - plot * t.level)       // 线在这一行的竖直中点，对准刻度位置
                }
                HStack(alignment: .bottom, spacing: 2) {
                    if entries.isEmpty {
                        Text("还没有记录").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.3))
                        Spacer(minLength: 0)
                    }
                    ForEach(entries) { e in
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Self.color(Self.outcome(e)))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, plot * (Self.level(e) ?? 0)))
                    }
                }
                .padding(.trailing, 26)                 // 给刻度字留位
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("这个会话最近 \(entries.count) 轮")
                Spacer(minLength: 0)
                if let longest = entries.compactMap(\.duration).max() {
                    Text("最长 " + DetailView.duration(longest)).monospacedDigit()
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.42))

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
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Color.white.opacity((counts[o] ?? 0) > 0 ? 0.9 : 0.3))
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}
