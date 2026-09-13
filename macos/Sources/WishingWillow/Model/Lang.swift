import Foundation

/// 界面语言：跟随系统首选语言（系统设置 → 通用 → 语言与地区）。首选是中文就显示中文，其余一律英文。
///
/// 用成对写法 `L("中文", "English")`，不用 String Catalog：本 app 用 SwiftPM 编译后由 Makefile 手工装配 .app，
/// SwiftPM 的资源包不会自动进包，`Text` 字面量的本地化查找会落空、界面静默退回源语言。成对写法没有这个坑，
/// 中英两句也挨在一起，改一处时另一处就在眼前。
///
/// `WILLOW_LANG=zh|en` 可以强制指定——拍英文版截图、跑固定语言的测试时用。
enum Lang: Sendable, Equatable {
    case zh, en

    nonisolated(unsafe) static var current: Lang = resolve()

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        preferred: [String] = Locale.preferredLanguages) -> Lang {
        if let forced = environment["WILLOW_LANG"]?.lowercased() {
            if forced.hasPrefix("zh") { return .zh }
            if forced.hasPrefix("en") { return .en }
        }
        return preferred.first?.lowercased().hasPrefix("zh") == true ? .zh : .en
    }
}

/// 一句界面文案的中英两种写法，按当前语言取一种。
func L(_ zh: String, _ en: String) -> String { Lang.current == .zh ? zh : en }
