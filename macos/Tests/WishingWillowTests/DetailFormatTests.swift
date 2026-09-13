import Testing
import Foundation
@testable import WishingWillow

/// 用户实测：点击面板把时长写成「1,911 秒」。
@MainActor
@Suite("点击面板的格式")
struct DetailFormatTests {
    init() { Lang.current = .zh }

    @Test("时长按分秒写，不写四位数的秒")
    func duration() {
        #expect(DetailView.duration(8) == "8 秒")
        #expect(DetailView.duration(352) == "5 分 52 秒")
        #expect(DetailView.duration(1911) == "31 分 51 秒")
        #expect(DetailView.duration(1800) == "30 分")
        #expect(DetailView.duration(3720) == "1 小时 2 分")
    }
}
