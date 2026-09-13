import Testing
import Foundation
@testable import WishingWillow

/// 真值那一关：读磁盘上**插件真正写出来的**状态文件。
///
/// 上面那些用例是我按自己理解手写的，只能证明理解自洽。这个项目今天已经三次
/// 栽在「判据和被判据的东西同源」上：测试绕过了配置文件、fixture 照着写代码的
/// 同一份文档手写、现场按自己以为的样子造。所以至少要有一关，它读的东西
/// 不是我造的。
///
/// 没有文件时不静默通过：打出 SKIP 并报出扫了几个。跳过不是通过。
@Suite("真实状态文件")
struct LiveStateTests {
    init() { Lang.current = .zh }


    @Test("磁盘上的状态文件全部能解码")
    func decodesEveryRealFile() throws {
        let dir = WillowStore.defaultDirectory
        let fm = FileManager.default

        guard fm.fileExists(atPath: dir.path),
              let names = try? fm.contentsOfDirectory(atPath: dir.path)
        else {
            print("⊘ SKIP —— \(dir.path) 不存在。插件还没跑过，这一关未验证，不等于通过。")
            return
        }

        let files = names.filter { $0.hasSuffix(".json") }
        guard !files.isEmpty else {
            print("⊘ SKIP —— \(dir.path) 里没有状态文件。这一关未验证，不等于通过。")
            return
        }

        var ok = 0
        var failures: [String] = []
        for name in files {
            let url = dir.appendingPathComponent(name)
            do {
                let data = try Data(contentsOf: url)
                let r = try JSONDecoder().decode(WillowRecord.self, from: data)
                #expect(r.sessionId.isEmpty == false)
                ok += 1
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        print("✓ 真实文件 \(ok)/\(files.count) 解码通过")
        #expect(failures.isEmpty, "解码失败：\(failures.joined(separator: "; "))")
    }
}
