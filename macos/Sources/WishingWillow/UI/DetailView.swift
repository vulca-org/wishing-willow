import SwiftUI

/// 点击之后的窗口：左边会话，右边这个会话最近的轮次。
///
/// 历史来自插件写的 `<session>.log.jsonl`，最多二十轮。它存在的唯一理由是那个
/// 可证伪的指标 —— 漂移发生在第 N 轮、人第 M 轮才发现，M−N 就是代价。
/// 这个窗口不替你算那个数，它只是把 N 和 M 摆在同一块屏幕上。
struct DetailView: View {
    let store: WillowStore
    let seen: SeenStore
    @State private var picked: String?

    private var current: SessionState? {
        if let picked, let s = store.sessions.first(where: { $0.id == picked }) { return s }
        return store.sessions.first
    }

    private var history: [TurnLogEntry] {
        guard let s = current else { return [] }
        return TurnLog.read(sessionId: s.id, directory: store.directory).reversed()
    }

    var body: some View {
        Group {
            if Offscreen.isRendering {
                // HSplitView 与 List 在离屏渲染里什么都不画。等价布局，不是降级：
                // 快照要能证明内容对，不是证明容器在。
                HStack(alignment: .top, spacing: 0) {
                    list.frame(width: 200)
                    Divider()
                    turns
                }
            } else {
                HSplitView { list; turns }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private var list: some View {
        if Offscreen.isRendering {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(store.sessions) { s in listRow(s) }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List(store.sessions, selection: $picked) { s in
                listRow(s).tag(s.id)
            }
            .frame(minWidth: 180, idealWidth: 200)
        }
    }

    private func listRow(_ s: SessionState) -> some View {
        HStack(spacing: 6) {
                Circle()
                    .fill(s.declaration == .unreadable ? Color.red
                          : s.flaggedByModel ? Color.orange
                          : seen.isUnread(s) ? Color.primary : Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(s.isStale ? 0.4 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.tag ?? s.workspace).font(.system(size: 12)).lineLimit(1)
                    Text(s.workspace).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
    }

    @ViewBuilder
    private var turns: some View {
        if Offscreen.isRendering {
            turnList
        } else {
            ScrollView { turnList }
        }
    }

    private var turnList: some View {
        Group {
            VStack(alignment: .leading, spacing: 12) {
                if history.isEmpty {
                    Text("这个会话还没有记录下来的轮次。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                ForEach(history) { t in row(t) }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ t: TurnLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let at = t.at {
                    Text(at, format: .dateTime.hour().minute())
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if let tag = t.tag {
                    Text(tag).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let d = t.duration, d >= 1 {
                    Text("\(Int(d)) 秒")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(t.prompt ?? "—")
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            // 「没问」和「问了没答」必须分开写。合成一句「无声明」，
            // 这个窗口就在制造它本该打破的那种沉默。
            if t.declared {
                Text(t.decode ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(t.flaggedByModel ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if t.reminded == true {
                Text("问了，模型没写声明").font(.system(size: 11)).foregroundStyle(.orange)
            } else if t.reminded == false {
                Text("这一轮没问（太短或是系统消息）").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                Text("不知道这一轮问没问").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Divider() }
    }
}
