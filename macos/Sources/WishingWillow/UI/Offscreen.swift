import SwiftUI

/// 离屏渲染（`--snapshot`）开着没有。
///
/// `ImageRenderer` 没有活的合成器，好几种 AppKit 撑着的 SwiftUI 容器在它下面
/// **不是画得难看，是整个不画，连子视图一起吞掉**：`glassEffect`、
/// `GlassEffectContainer`、`ScrollView`、`HSplitView`、`List`。已经踩到三批。
///
/// 每次的症状都一样：那块东西消失了，而「消失」和「本来就没东西」在图上
/// 分不开 —— 这正是这个项目从头到尾在对付的那种失败。所以凡是用到这几种容器
/// 的地方，都要在这里查一下，给离屏一条等价的布局，而不是让它悄悄空掉。
enum Offscreen {
    nonisolated(unsafe) static var isRendering = false
}
