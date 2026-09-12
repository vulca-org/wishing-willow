import SwiftUI

/// 刘海形状：顶部两角向外凹（「肩」），下方两角圆。
///
/// 先前用下方圆角矩形，顶边两角是直角，贴着屏幕上沿读起来是「一块贴上去的黑条」。
/// 真实刘海与 boring.notch 都是凹肩——黑色从屏幕边缘流下来。参数取自 boring.notch 源码：
/// 收起 top 6 / bottom 14，展开 top 19 / bottom 24。
///
/// 形状宽度包含两侧的肩：主体宽 = rect.width − 2 × topRadius，内容要按 topRadius 内缩。
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * t) / 2, max(0, rect.height - t))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }

    static let closed = (top: CGFloat(6), bottom: CGFloat(14))
    static let open = (top: CGFloat(19), bottom: CGFloat(24))
}
