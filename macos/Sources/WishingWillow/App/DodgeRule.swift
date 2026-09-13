import CoreGraphics
import Foundation

/// 菜单栏滑出来时给它让路。
///
/// 用户的菜单栏是自动隐藏的（`_HIHideMenuBar = 1`）：鼠标碰到屏幕顶边，菜单栏才滑下来，
/// 占的正是刘海那条带子（这台机器 28pt）。收起态的两翼和胶囊就在这条带子里，
/// 会盖住刘海两侧的菜单和状态栏图标（用户 2026-09-13 报）。
///
/// **什么时候让、什么时候回，跟着菜单栏窗口本身走，不自己计时。** 窗口列表里 layer 24、属于 Window Server 的菜单栏窗口
/// 一出现就让；鼠标离开带子后，它的 y 开始往负走（开始收）就回。
/// 2026-09-13 本机实测（发真实鼠标事件、读窗口位置、录屏逐帧对齐）：窗口出现与开始收回的时刻，和画面开始动相差不到一帧；
/// 滑出约 0.1 秒、先快后慢，收回约 0.13 秒、近乎匀速。
/// 先前按「碰到顶边就让、离开带子 0.35 秒再回」自己计时，还每 0.1 秒才看一次鼠标：菜单栏收完，
/// 灵动岛还在下面挂约 0.25 秒——用户说「和顶边栏弹出和收回的速度应该一致，动画效果也要一致」。
/// 这里只做判定与曲线，纯函数，好测；读鼠标、读窗口列表和逐帧推进在 IslandController。
enum DodgeRule {
    /// 屏幕顶边那条带子（菜单栏滑出来占的地方）。AppKit 屏幕坐标，y 向上。
    static func band(screen: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: screen.minX, y: screen.maxY - height, width: screen.width, height: height)
    }

    /// 鼠标在不在带子里。顶边那一行算在里面（`CGRect.contains` 不含上边界）。
    static func inBand(_ p: CGPoint, _ band: CGRect) -> Bool {
        p.x >= band.minX && p.x <= band.maxX && p.y >= band.minY && p.y <= band.maxY + 1
    }

    /// 没在让路时，值不值得去查菜单栏：收起态画着东西、鼠标在带子里、又不在灵动岛上。
    /// 让不让最终看菜单栏窗口在不在（shouldStart），所以带子里任何一行都可以查：鼠标从菜单栏往下、岛已经回位，
    /// 又回到还开着的菜单栏上，也要重新让。鼠标直接落在灵动岛上是悬停，不让。读窗口列表比读鼠标贵，只在带子里查。
    static func wantsMenuBarCheck(active: Bool, pointer: CGPoint, band: CGRect, island: CGRect) -> Bool {
        guard active, inBand(pointer, band) else { return false }
        return !island.insetBy(dx: -2, dy: -2).contains(pointer)
    }

    /// 菜单栏窗口已经在屏幕上（正在滑出或已经出来）就让。还没出来就不让，免得凭空往下跳一下。
    static func shouldStart(menuBarY: CGFloat?) -> Bool { menuBarY != nil }

    /// 让路中要不要回。收起态不再画东西就回；鼠标还在带子里、或有下拉菜单开着，就不回；
    /// 否则看菜单栏窗口：没了、或 y 已经往负走（开始收），就回。
    /// 也试过不等窗口、按鼠标离开的时刻起算：录屏里岛反而比菜单栏晚约 80 毫秒起步、途中露出 11pt 的缝（2026-09-13），
    /// 原因没查清，退回等窗口。等窗口时收回仍比菜单栏晚约两帧起步、途中最宽 6pt 的缝——这是现在的已知差距。
    static func shouldEnd(active: Bool, pointerInBand: Bool, menuBarY: CGFloat?, popUpOpen: Bool) -> Bool {
        guard active else { return true }
        if pointerInBand || popUpOpen { return false }
        guard let y = menuBarY else { return true }
        return y < 0
    }

    /// 发现菜单栏在动的那一刻，灵动岛该在哪。窗口列表里的菜单栏位置不是逐帧更新的，而且比画面早三四十毫秒：
    /// 滑出时第一次读到 y = −17（露出四成），画面才刚开始动；收回时第一次读到 y = −7（露出七成半），画面还露着近九成。
    /// 2026-09-13 两次录屏逐帧：从 0 或到底起跑，岛落后菜单栏三四帧，收回时露出最宽 11pt 的缝；
    /// 按读数原样追上去、再用缓出曲线，岛又领先两帧，滑出时露出 8pt 的缝；追到四分之三、收回补一半、改匀速，又落后一两帧。
    /// 两头夹出来：曲线用匀速，滑出追到读数的九成，收回直接追到读数。只往前追，不往回拉。
    static func catchUp(current: CGFloat, depth: CGFloat, barY: CGFloat?, barHeight: CGFloat, down: Bool) -> CGFloat {
        guard let y = barY, barHeight > 0 else { return current }
        let read = max(0, min(1, (barHeight + y) / barHeight))
        let shown = down ? read * 0.9 : read
        let there = depth * shown
        return down ? max(current, there) : min(current, there)
    }

    /// 本机菜单栏在画面上走完一趟的时长（2026-09-13 录屏逐帧量苹果标志的位置）：滑出约 0.1 秒，收回约 0.13 秒。
    static let downDuration: TimeInterval = 0.10
    static let upDuration: TimeInterval = 0.13

    /// 让路的进度曲线。画面上的菜单栏两个方向都近乎匀速（逐帧位置差大致相等）；
    /// 先前用读数拟合的缓出曲线前半段太快，岛会冲到菜单栏前面去。
    static func eased(_ p: Double, down: Bool) -> Double {
        max(0, min(1, p))
    }
}
