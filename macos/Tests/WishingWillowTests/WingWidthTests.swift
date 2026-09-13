import Testing
@testable import WishingWillow

/// 收起态两翼的宽度按右翼标签定。中文 6 字的标签照旧 92；英文标签插件允许 14 个字符，要放得下；再长也有上限。
@MainActor
@Suite("两翼宽度")
struct WingWidthTests {
    @Test("中文 6 字 = 92；英文 14 字符放得下且不超过上限；空标签 = 92；超长封顶")
    func widths() {
        #expect(IslandController.wingWidth(label: "修上传测试") == IslandController.wing)
        #expect(IslandController.wingWidth(label: nil) == IslandController.wing)
        #expect(IslandController.wingWidth(label: "") == IslandController.wing)
        let english = IslandController.wingWidth(label: "Fix upload tes")
        #expect(english > IslandController.wing)
        #expect(english <= IslandController.wingMax)
        #expect(IslandController.wingWidth(label: String(repeating: "Withdrawn ", count: 6)) == IslandController.wingMax)
    }
}
