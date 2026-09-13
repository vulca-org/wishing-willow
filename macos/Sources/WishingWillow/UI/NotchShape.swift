import SwiftUI

/// 刘海形状：顶部两角向外凹（「肩」），下方两角圆。
///
/// 先前用下方圆角矩形，顶边两角是直角，贴着屏幕上沿读起来是「一块贴上去的黑条」。
/// 真实刘海与 boring.notch 都是凹肩——黑色从屏幕边缘流下来。参数取自 boring.notch 源码：
/// 收起 top 6 / bottom 14，展开 top 19 / bottom 24。
///
/// 形状宽度包含两侧的肩：主体宽 = rect.width − 2 × topRadius，内容要按 topRadius 内缩。
///
/// **给菜单栏让路**（`drop` > 0）：主体往下挪 `drop`，从物理刘海底边长出来——
/// 一截和刘海同宽的颈（盖在刘海里，看不见）接着主体，接口两侧是倒角；主体两端从凹肩变成全圆，读作一枚挂在刘海下的胶囊。
/// 先前整块平顶黑条原样平移：刘海和黑条上下堆着，刘海的圆底角和平顶之间漏两个亮三角，
/// 两端的小凹肩戳进灰色菜单栏——用户说「还是很丑」（2026-09-13）。
/// 颈画在 rect 上方（y < 0）：调用方把整块形状下移 `drop`，颈的顶端正好落回屏幕上沿。
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// 主体此刻往下让了多少；0 = 贴着刘海，与原来的形状逐点相同。
    var drop: CGFloat = 0
    /// 让到底是多少（菜单栏高度），用来算进度：两端的凹肩在前 40% 收掉，之后长成全圆。
    var dropDepth: CGFloat = 0
    /// 颈宽 = 物理刘海宽。没有物理刘海（外接屏）或挂在刘海下方让路时给 0：不画颈，只是一枚贴着菜单栏的胶囊。
    var stemWidth: CGFloat = 0

    static let fillet: CGFloat = 10
    /// 颈往屏幕上沿之外多伸一截（窗口顶边会裁掉）。偏移与形状参数是两条动画，逐帧录屏里收尾那几帧差不到 1pt，
    /// 颈顶就在刘海下沿露出一行亮像素（2026-09-13 逐帧：让到底前后各 3 帧）。
    static let stemReach: CGFloat = 6

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(topRadius, .init(bottomRadius, drop)) }
        set { topRadius = newValue.first; bottomRadius = newValue.second.first; drop = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let t0 = min(topRadius, rect.width / 4)
        let progress = dropDepth > 0 ? max(0, min(1, drop / dropDepth)) : 0
        let left = rect.minX + t0, right = rect.maxX - t0
        let half = max(0, (right - left) / 2)
        let mid = rect.midX
        // 顶角：先收凹肩，再长凸圆角；两者不同时出现。凹肩只在贴着屏幕上沿时成立，离开上沿就是两只翘起的小角——
        // 先前让出 40% 才收掉，逐帧录屏里半空中两端各翘一只（2026-09-13），所以让出 15% 就收掉。
        let shoulder = t0 * max(0, 1 - progress / 0.15)
        var round = min(bottomRadius, rect.height / 2) * max(0, (progress - 0.15) / 0.85)
        round = min(round, half)
        let b = min(bottomRadius, half, max(0, rect.height - max(shoulder, round)))
        // 颈与倒角：挤不下就先缩倒角、再缩颈。
        var stem = drop > 0 ? stemWidth / 2 : 0
        stem = min(stem, max(0, half - round))
        // 倒角半路上更大、到底收成 10pt：像从刘海里拉出来的一滴，停稳后接口收紧。回刘海时反过来。
        let fillet = min(Self.fillet * (progress + sin(.pi * progress)), drop, max(0, half - round - stem))

        var p = Path()
        if stem > 0 {
            p.move(to: CGPoint(x: mid - stem, y: rect.minY - drop - Self.stemReach))
            p.addLine(to: CGPoint(x: mid - stem, y: rect.minY - fillet))
            p.addQuadCurve(to: CGPoint(x: mid - stem - fillet, y: rect.minY),
                           control: CGPoint(x: mid - stem, y: rect.minY))
        }
        if shoulder > 0 {
            if stem > 0 { p.addLine(to: CGPoint(x: left - shoulder, y: rect.minY)) }
            else { p.move(to: CGPoint(x: left - shoulder, y: rect.minY)) }
            p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + shoulder), control: CGPoint(x: left, y: rect.minY))
        } else {
            if stem > 0 { p.addLine(to: CGPoint(x: left + round, y: rect.minY)) }
            else { p.move(to: CGPoint(x: left + round, y: rect.minY)) }
            p.addQuadCurve(to: CGPoint(x: left, y: rect.minY + round), control: CGPoint(x: left, y: rect.minY))
        }
        p.addLine(to: CGPoint(x: left, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: left + b, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: right - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - b), control: CGPoint(x: right, y: rect.maxY))
        if shoulder > 0 {
            p.addLine(to: CGPoint(x: right, y: rect.minY + shoulder))
            p.addQuadCurve(to: CGPoint(x: right + shoulder, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        } else {
            p.addLine(to: CGPoint(x: right, y: rect.minY + round))
            p.addQuadCurve(to: CGPoint(x: right - round, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        }
        if stem > 0 {
            p.addLine(to: CGPoint(x: mid + stem + fillet, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: mid + stem, y: rect.minY - fillet),
                           control: CGPoint(x: mid + stem, y: rect.minY))
            p.addLine(to: CGPoint(x: mid + stem, y: rect.minY - drop - Self.stemReach))
        }
        p.closeSubpath()
        return p
    }

    static let closed = (top: CGFloat(6), bottom: CGFloat(14))
    static let open = (top: CGFloat(19), bottom: CGFloat(24))
}
