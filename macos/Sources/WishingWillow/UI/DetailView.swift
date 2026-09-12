import SwiftUI

/// 点击灵动岛之后的面板——灵动岛本身再长大一档，不是另开一个窗口。
///
/// 用户实测原来的面板「跳脱」：灰色标准窗口、红黄绿按钮、中间一道分隔线；左侧两个会话同名分不清、
/// 标题和副标题重复；时长写成「1,911 秒」；也没有「你批准的 / 我读成了」。这里逐条改。
struct DetailView: View {
    let store: WillowStore
    let seen: SeenStore
    var onClose: (() -> Void)? = nil
    @State private var picked: String?

    static let size = CGSize(width: 560, height: 460)

    private var sessions: [SessionState] { store.sessions }
    private var current: SessionState? {
        if let picked, let s = sessions.first(where: { $0.id == picked }) { return s }
        return sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 26)                          // 刘海那一条
            header
            HStack(alignment: .top, spacing: 12) {
                sessionList.frame(width: 172)
                turnList.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .foregroundStyle(Color.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: 头

    private var header: some View {
        HStack(spacing: 8) {
            Text("最近的轮次").font(.system(size: 12, weight: .semibold))
            Text("\(sessions.count) 个会话").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.4))
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) {
                    Text("收起")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
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
        let sub = dupes.contains(s.workspace) ? "\(s.workspace) · \(s.id.prefix(4))" : s.workspace
        return HStack(alignment: .top, spacing: 7) {
            Circle().fill(dotColor(s)).frame(width: 6, height: 6).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(s.isStale ? 0.5 : 1))
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .lineLimit(1).truncationMode(.middle)
                if let u = s.record.updatedAt {
                    Text(Self.ago(u)).font(.system(size: 9.5)).foregroundStyle(Color.white.opacity(0.3))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
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

    private var turnList: some View {
        let entries = current.map { TurnLog.read(sessionId: $0.id, directory: store.directory) } ?? []
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
                        .font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.45)).padding(.top, 6)
                }
                ForEach(history) { t in turnRow(t) }
            }
        }
    }

    private func liveRow(_ s: SessionState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) { badge("进行中"); Spacer(minLength: 0) }
            label("你批准的")
            if s.record.isSystemMessage {
                Text("系统消息（\(PromptSource.describe(s.prompt))），不是你说的")
                    .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.45))
            } else {
                Text(s.prompt ?? "—").font(.system(size: 11.5)).lineLimit(3)
            }
            label("我读成了")
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .symbolEffect(.pulse, options: .repeating)
                Text("模型正在回答").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    }

    private func turnRow(_ t: TurnLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let at = t.at {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.white.opacity(0.4))
                }
                if let tag = t.tag {
                    Text(tag).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.white.opacity(0.75))
                }
                if t.interrupted == true { badge("被打断") }
                Spacer(minLength: 0)
                if let d = t.duration, d >= 1 {
                    Text(Self.duration(d)).font(.system(size: 9.5)).foregroundStyle(Color.white.opacity(0.35))
                }
            }
            label("你批准的")
            if t.isSystemMessage {
                Text("系统消息（\(PromptSource.describe(t.prompt))），不是你说的")
                    .font(.system(size: 11.5)).foregroundStyle(Color.white.opacity(0.45))
            } else {
                Text(t.prompt ?? "—").font(.system(size: 11.5)).lineLimit(3).textSelection(.enabled)
            }
            label("我读成了")
            decodeText(t)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5) }
    }

    /// 「被打断」「问了没答」「没问」「不知道」必须是不同的话——合成一句「无声明」就是在制造沉默。
    @ViewBuilder
    private func decodeText(_ t: TurnLogEntry) -> some View {
        if t.declared {
            Text(t.decode ?? "")
                .font(.system(size: 11.5))
                .foregroundStyle(t.flaggedByModel ? Color.orange : Color.white)
                .lineLimit(3).textSelection(.enabled)
        } else if t.interrupted == true {
            Text("被打断，没来得及写声明").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.45))
        } else if t.reminded == true {
            Text("问了，模型没写声明").font(.system(size: 11)).foregroundStyle(Color.orange)
        } else if t.reminded == false {
            Text("这一轮没问（太短或是系统消息）").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
        } else {
            Text("不知道这一轮问没问").font(.system(size: 11)).foregroundStyle(Color.white.opacity(0.4))
        }
    }

    // MARK: 小件

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.white.opacity(0.38))
    }

    private func badge(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .semibold))
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
