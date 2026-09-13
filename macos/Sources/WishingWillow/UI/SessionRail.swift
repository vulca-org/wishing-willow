import SwiftUI

/// 一个会话一枚 pill。玻璃用在这里 —— 它是外壳，需要一点深度，
/// 而且不跟下面那两行文字抢注意力。
///
/// 不用 `ScrollView`：横向滚动的条目在弹出面板里得先滑到才看得见，
/// 而这一栏的全部作用就是让人一眼看出「哪个会话亮着黄灯」。
/// 默认两行封顶，多出来的收进一枚 `+N`，按一下展开 —— 那是第三处、也是最后一处玻璃。
struct SessionRail: View {
    let sessions: [SessionState]
    let selected: String?
    let pick: (String) -> Void

    @State private var expanded = false

    private static let collapsedRows = 2

    var body: some View {
        container {
            WrapLayout(spacing: 6, lineSpacing: 6,
                       maxRows: expanded ? nil : Self.collapsedRows) {
                ForEach(sessions) { s in
                    Button { pick(s.id) } label: { pill(s) }
                        .buttonStyle(.plain)
                }
            }
            .overlay(alignment: .bottomTrailing) { overflow }
        }
    }

    @ViewBuilder
    private var overflow: some View {
        if sessions.count > 6 {
            Button { expanded.toggle() } label: {
                Text(expanded ? L("收起", "Less") : "+\(sessions.count - 6)")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .willowGlass(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    /// `GlassEffectContainer` 在离屏渲染里什么都不画，连子视图一起吞掉。
    @ViewBuilder
    private func container(@ViewBuilder _ content: () -> some View) -> some View {
        if Offscreen.isRendering { content() } else { GlassEffectContainer(spacing: 6, content: content) }
    }

    private func pill(_ s: SessionState) -> some View {
        HStack(spacing: 5) {
            dot(s)
            Text(s.tag ?? s.workspace)
                .font(.system(size: 11, weight: s.id == selected ? .medium : .regular))
                .lineLimit(1)
        }
        .foregroundStyle(s.isStale ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .willowGlass(.capsule, tint: s.id == selected ? .accentColor : nil)
    }

    /// 圆点编的是「谁说了什么」，不是「对不对」：
    /// 红 = 插件读不到输入（事实）；琥珀 = 模型自己标了 ⚠（转发它的判断）；
    /// 空心 = 本轮没声明（事实）；中性实心 = 声明了。
    ///
    /// **已声明不用绿色** —— 绿色会被读成「已核对、没问题」，而这个工具
    /// 从不核对两栏是否一致。用了绿色，它就在替人做那个判断。
    private func dot(_ s: SessionState) -> some View {
        let size: CGFloat = 6
        return Group {
            if s.declaration == .undeclared {
                Circle().strokeBorder(Color.secondary, lineWidth: 1)
            } else {
                Circle().fill(color(s))
            }
        }
        .frame(width: size, height: size)
        .opacity(s.isStale ? 0.4 : 1)
    }

    private func color(_ s: SessionState) -> Color {
        if s.isStale { return .secondary }
        if s.declaration == .unreadable { return .red }
        if s.flaggedByModel { return .orange }
        return .secondary
    }
}

/// 按容器宽度换行排列，可选行数上限。
///
/// 自己写而不是用 `ScrollView`/`LazyVGrid`：这一栏要在两种环境下都布局得出来 ——
/// 实机上的弹出面板，和 `ImageRenderer` 的离屏渲染。`ScrollView` 在后者里不布局，
/// 于是快照会把「整栏都不见」画得跟「一个会话都没有」一模一样。
struct WrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var maxRows: Int?

    struct Row { var indices: [Int] = []; var height: CGFloat = 0; var width: CGFloat = 0 }

    private func rows(_ sizes: [CGSize], width: CGFloat) -> [Row] {
        var out: [Row] = []
        var row = Row()
        for (i, size) in sizes.enumerated() {
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                out.append(row)
                if let maxRows, out.count >= maxRows { return out }
                row = Row()
                row.indices = [i]; row.width = size.width; row.height = size.height
            } else {
                row.indices.append(i)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.indices.isEmpty { out.append(row) }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 460
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let laid = rows(sizes, width: width)
        let height = laid.reduce(0) { $0 + $1.height } + max(0, CGFloat(laid.count - 1)) * lineSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(sizes, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(sizes[i]))
                x += sizes[i].width + spacing
            }
            y += row.height + lineSpacing
        }
    }
}
