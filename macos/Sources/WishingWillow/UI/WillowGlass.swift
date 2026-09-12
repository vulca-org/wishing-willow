import SwiftUI

/// 这个 app 只有三处用玻璃：会话栏、警示条、退出按钮。内容面板一律不用 ——
/// 那两行是全部产品，要靠读来比较，所以放在不透明的底上、全对比度。
///
/// 收成一个 modifier 有两个理由。一是让「只有三处」这条规则在代码里看得见，
/// 加第四处必须动这个文件。二是给离屏渲染一条退路：`glassEffect` 在没有活合成器
/// 的时候不只是不画玻璃，**连它包住的内容一起吞掉**，于是 `--snapshot` 出来的图里
/// 那三处会是空白 —— 又一次「坏掉的样子和正常的样子分不开」。
enum WillowGlass {
    /// `--snapshot` 模式下置为 true。只影响渲染退路，不影响任何逻辑。
    nonisolated(unsafe) static var offscreen = false
}

enum WillowGlassShape {
    case capsule
    case rounded(CGFloat)
}

private struct WillowGlassModifier: ViewModifier {
    let shape: WillowGlassShape
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        let base: AnyShapeStyle = tint.map { AnyShapeStyle($0.opacity(0.12)) }
            ?? AnyShapeStyle(.quaternary.opacity(0.55))

        switch shape {
        case .capsule:
            if WillowGlass.offscreen {
                content.background(base, in: .capsule)
            } else {
                content
                    .background(base, in: .capsule)
                    .glassEffect(glass, in: .capsule)
            }
        case .rounded(let r):
            if WillowGlass.offscreen {
                content.background(base, in: .rect(cornerRadius: r))
            } else {
                content
                    .background(base, in: .rect(cornerRadius: r))
                    .glassEffect(glass, in: .rect(cornerRadius: r))
            }
        }
    }

    private var glass: Glass {
        tint.map { .regular.tint($0.opacity(0.16)) } ?? .regular
    }
}

extension View {
    func willowGlass(_ shape: WillowGlassShape, tint: Color? = nil) -> some View {
        modifier(WillowGlassModifier(shape: shape, tint: tint))
    }
}
