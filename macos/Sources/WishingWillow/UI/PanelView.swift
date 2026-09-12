import SwiftUI

/// The panel that drops out of the menu bar.
///
/// Layout rule, held throughout: glass goes on the chrome — the session rail,
/// the warning banner, the footer button — and never on the two rows of text.
/// Those two rows are the entire product, and they are compared by reading
/// them, so they sit on a plain, opaque surface at full contrast.
struct PanelView: View {
    let store: WillowStore
    @State private var pinned: String?

    private var selected: SessionState? {
        if let pinned, let s = store.sessions.first(where: { $0.id == pinned }) { return s }
        return store.sessions.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.sessions.isEmpty {
                EmptyStateView(directoryExists: store.directoryExists, path: store.directory.path)
            } else {
                SessionRail(sessions: store.sessions, selected: selected?.id, pick: { pinned = $0 })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)

                if let s = selected {
                    TurnView(state: s)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                }
            }

            Divider()
            footer
        }
        .frame(width: 460)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("许愿柳")
                .font(.system(size: 13, weight: .semibold))
            Text("Wishing-Willow")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            if let scan = store.lastScan {
                Text(scan, format: .dateTime.hour().minute().second())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            Text("两栏一致与否由你判断 —— 这就是全部设计")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .willowGlass(.capsule)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct EmptyStateView: View {
    let directoryExists: Bool
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(directoryExists ? "还没有任何一轮" : "插件还没跑过")
                .font(.system(size: 12, weight: .medium))
            Text(directoryExists
                 ? "装好插件的会话说一句话之后，这里就会出现。"
                 : "这个目录由插件创建，读方不碰它 —— 它不存在，就是「插件一次都没跑过」的证据。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}
