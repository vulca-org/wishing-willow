import CoreGraphics
import Foundation

/// 菜单栏滑出来时给它让路。
///
/// 用户的菜单栏是自动隐藏的（`_HIHideMenuBar = 1`）：鼠标碰到屏幕顶边，菜单栏才滑下来，
/// 占的正是刘海那条带子（这台机器 28pt）。收起态的两翼和胶囊就在这条带子里，
/// 会盖住刘海两侧的菜单和状态栏图标（用户 2026-09-13 报）。
///
/// 照用户的方案：鼠标碰到屏幕最顶上那一行、又不在灵动岛上时，灵动岛整体往下让出一条菜单栏的高度；
/// 鼠标离开带子一小会儿、而且没有菜单开着，再回到刘海。鼠标直接落在灵动岛上是悬停，不让路。
/// 这里只做判定，纯函数，好测；动画与读鼠标在 IslandController。
enum DodgeRule {
    /// 离开带子多久才回刘海：鼠标从菜单栏往下移、路过让开的灵动岛时不来回弹。
    static let settle: TimeInterval = 0.35

    /// 屏幕顶边那条带子（菜单栏滑出来占的地方）。AppKit 屏幕坐标，y 向上。
    static func band(screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
    }

    /// 鼠标在不在带子里。顶边那一行算在里面（`CGRect.contains` 不含上边界）。
    static func inBand(_ p: CGPoint, _ band: CGRect) -> Bool {
        p.x >= band.minX && p.x <= band.maxX && p.y >= band.minY && p.y <= band.maxY + 1
    }

    /// 下一刻让不让。
    /// - active：收起态，而且两翼或胶囊画着东西（缩回刘海时本来就不挡）。
    /// - island：灵动岛连同胶囊在**不让路时**的位置。
    /// - outSince：让路之后鼠标离开带子的时刻，由调用方保存、下一次传回来。
    /// - menuOpen：有下拉菜单开着——菜单画在带子下面，鼠标离开带子时它还开着。
    static func next(dodging: Bool, active: Bool, pointer: CGPoint, band: CGRect, island: CGRect,
                     outSince: Date?, now: Date, menuOpen: Bool) -> (dodge: Bool, outSince: Date?) {
        guard active else { return (false, nil) }
        let here = inBand(pointer, band)
        if !dodging {
            // 菜单栏只在鼠标碰到最顶上那一行时才滑出来；带子里其余位置还没有菜单栏，先让就是凭空跳一下。
            let atEdge = here && pointer.y >= band.maxY - 1
            let onIsland = island.insetBy(dx: -2, dy: -2).contains(pointer)
            return (atEdge && !onIsland, nil)
        }
        if here || menuOpen { return (true, nil) }
        let since = outSince ?? now
        return (now.timeIntervalSince(since) < settle, since)
    }
}
