import Testing
import Foundation
@testable import WishingWillow

/// 界面语言跟随系统首选语言（用户 2026-09-13：「ui 界面需要结合本地系统的配置来自动配置语言」）。
@Suite("界面语言")
struct LangTests {
    @Test("首选语言是中文（任何地区）→ 中文；首选是别的 → 英文；WILLOW_LANG 可强制")
    func resolve() {
        #expect(Lang.resolve(environment: [:], preferred: ["zh-Hans-GB", "en-GB"]) == .zh)
        #expect(Lang.resolve(environment: [:], preferred: ["zh-Hant-TW"]) == .zh)
        #expect(Lang.resolve(environment: [:], preferred: ["en-GB", "zh-Hans-GB"]) == .en)
        #expect(Lang.resolve(environment: [:], preferred: ["ja-JP"]) == .en)
        #expect(Lang.resolve(environment: [:], preferred: []) == .en)
        #expect(Lang.resolve(environment: ["WILLOW_LANG": "en"], preferred: ["zh-Hans-GB"]) == .en)
        #expect(Lang.resolve(environment: ["WILLOW_LANG": "zh"], preferred: ["en-GB"]) == .zh)
    }
}
