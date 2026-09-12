import SwiftUI

/// `--snapshot <目录>` —— 把面板的每一种状态各渲染成一张 PNG。
///
/// 存在的理由有两个。一是视觉工作没有图就不能声称做完，而截屏要屏幕录制权限、
/// 还要接管用户的屏幕去点菜单栏；这条路不需要任何权限。二是它渲染的是**真实的
/// 读取链路**：先把样例写成状态文件，再让 `WillowStore` 从磁盘读回来 ——
/// 解码、派生、排序全都走一遍，而不是直接构造 View 的入参。
///
/// 诚实边界：`ImageRenderer` 离屏渲染没有活的合成器背景，**玻璃层会被画成扁平的**。
/// 这些图证明的是布局、文案和四种状态，不证明玻璃效果。
@MainActor
enum Snapshot {

    enum Kind { case panel, strip, detail }

    struct Scene {
        let name: String
        let files: [(String, String)]   // 文件名 → JSON
        var kind: Kind = .panel
        var seen: [String] = []         // 这些会话的当前一轮算「已读」
        var logs: [(String, String)] = []
    }

    /// 把常亮层放进一段真实尺寸的菜单栏里，好看出它到底占多大。
    struct MenuBarStrip: View {
        let store: WillowStore
        let seen: SeenStore
        var body: some View {
            HStack(spacing: 10) {
                Spacer()
                CompactLabel(store: store, seen: seen)
                Text("100%   16:52").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: 560, height: 28)
            .background(Color(white: 0.10))
            .environment(\.colorScheme, .dark)
        }
    }

    static func run(outputDirectory: String) -> Int32 {
        Offscreen.isRendering = true
        let fm = FileManager.default
        let outDir = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        var written: [String] = []
        for scene in scenes {
            let stateDir = fm.temporaryDirectory
                .appendingPathComponent("willow-snap-\(scene.name)-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: stateDir, withIntermediateDirectories: true)
            for (name, json) in scene.files {
                try? Data(json.utf8).write(to: stateDir.appendingPathComponent(name))
            }
            for (name, jsonl) in scene.logs {
                try? Data(jsonl.utf8).write(to: stateDir.appendingPathComponent(name))
            }

            let store = WillowStore(directory: stateDir)
            store.reload()

            let seenStore = SeenStore(ephemeral: true)
            for id in scene.seen { seenStore.markSeen(sessionId: id, turnId: "\(id)-turn") }

            let content: AnyView = switch scene.kind {
            case .panel:   AnyView(PanelView(store: store).frame(width: 460))
            case .strip:   AnyView(MenuBarStrip(store: store, seen: seenStore))
            case .detail:  AnyView(DetailView(store: store, seen: seenStore).frame(width: 640, height: 420))
            }

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2

            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else {
                FileHandle.standardError.write(Data("渲染失败：\(scene.name)\n".utf8))
                return 1
            }

            let out = outDir.appendingPathComponent("\(scene.name).png")
            do { try png.write(to: out) } catch {
                FileHandle.standardError.write(Data("写盘失败：\(out.path) \(error)\n".utf8))
                return 1
            }
            written.append(out.lastPathComponent)
            try? fm.removeItem(at: stateDir)
        }

        print(written.joined(separator: "\n"))
        return 0
    }

    /// 给 --selfshot 用的一批：一个两栏不一致的、一个未声明的、一个陈旧的。
    static var selfShotFixtures: [(String, String)] {
        guard let first = scenes.first(where: { $0.name == "01-declared-but-drifting" }) else { return [] }
        return first.files
    }

    // MARK: - 样例

    private static var now: String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(.now)
    }
    private static var pid: Int32 { ProcessInfo.processInfo.processIdentifier }

    private static func record(
        id: String, cwd: String, turn: Int,
        prompt: String?, promptField: String??, decode: String?, tag: String? = nil, stamp: String? = nil
    ) -> String {
        func q(_ s: String?) -> String {
            guard let s else { return "null" }
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        // promptField: nil = 键不存在；.some(nil) = 键在但为 null
        let field: String
        switch promptField {
        case .none: field = ""
        case .some(let v): field = ",\"promptField\":\(q(v))"
        }
        return """
        {"schema":2,"sessionId":"\(id)","pid":\(pid),"cwd":"\(cwd)","turnId":"\(id)-turn",\
        "turnIndex":\(turn),"updatedAt":"\(stamp ?? now)","prompt":\(q(prompt))\(field),"reminded":true,\
        "decode":\(q(decode)),"tag":\(q(tag)),"endedAt":null}
        """
    }

    /// 三轮样例：一轮两栏不一致、一轮问了没答、一轮压根没问。
    /// 这三种在窗口里必须长得不一样 —— 合成一句「无声明」就是在制造
    /// 这个产品本该打破的那种沉默。
    static var sampleLog: String {
        let rows = [
            #"{"turnId":"t0","at":"2026-09-12T16:10:00.000Z","endedAt":null,"interrupted":true,"reminded":true,"origin":"user","prompt":"我测试了一下 效果还行，还有这个我输入的新指令冒出了黄色文字。","decode":"先确认黄色文字是什么、为什么出现。","tag":"查黄色文字"}"#,
            #"{"turnId":"t1","at":"2026-09-12T16:21:51.000Z","endedAt":"2026-09-12T16:26:40.000Z","reminded":true,"prompt":"继续吧，接下来怎么做？另外那个档案馆的外联要放进去吗？","decode":"⚠ 先把披露时限文件做掉，然后回答档案馆那条线该放在哪。","tag":"做披露文件"}"#,
            #"{"turnId":"t2","at":"2026-09-12T16:27:54.000Z","endedAt":"2026-09-12T16:28:02.000Z","reminded":false,"prompt":"好的 继续吧","decode":null,"tag":null}"#,
            #"{"turnId":"t2b","at":"2026-09-12T16:29:00.000Z","endedAt":"2026-09-12T16:29:04.000Z","interrupted":false,"reminded":false,"origin":"system","prompt":"<task-notification>\n<task-id>af705</task-id>","decode":null,"tag":null}"#,
            #"{"turnId":"t3","at":"2026-09-12T16:31:10.000Z","endedAt":"2026-09-12T16:33:05.000Z","reminded":true,"prompt":"把这个目录下所有脚本的错误处理过一遍，先不要改。","decode":null,"tag":null}"#,
        ]
        return rows.joined(separator: "\n") + "\n"
    }

    private static var scenes: [Scene] {
        let drifting = record(
            id: "sess-a", cwd: "/Users/me/dev/atlas", turn: 4,
            prompt: "场景之一不是唯一，同样也不局限于此场景。我们要大范围地找到这个问题里面的逻辑是什么，然后找到可以复用的解决方案。",
            promptField: .some("prompt"),
            decode: "⚠ 去那个仓库里逐文件审计检查表与 spec，找漂移的具体证据",
            tag: "审计仓库")

        let undeclared = record(
            id: "sess-b", cwd: "/Users/me/dev/ledger", turn: 2,
            prompt: "把这个目录下所有脚本的错误处理都过一遍，告诉我哪些地方会静默失败，先不要改。",
            promptField: .some("prompt"), decode: nil)

        let broken = record(
            id: "sess-c", cwd: "/Users/me/dev/tiles", turn: 1,
            prompt: nil, promptField: .some(nil), decode: nil)

        let stale = record(
            id: "sess-d", cwd: "/Users/me/dev/archive", turn: 9,
            prompt: "先别动，我看一下昨天那版是怎么写的。",
            promptField: .some("prompt"), decode: "只读，不改任何文件", tag: "读旧版本",
            stamp: Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                .format(.now.addingTimeInterval(-3600)))

        // 每一幕里把要展示的那个会话排在最前 —— 靠的是真实的排序规则（活的在前、最近更新在前），
        // 不是给 View 塞一个选中项。
        return [
            .init(name: "05-strip-flagged",
                  files: [("a.json", drifting), ("b.json", undeclared), ("d.json", stale)], kind: .strip),
            .init(name: "06-strip-quiet",
                  files: [("a.json", drifting), ("b.json", undeclared), ("d.json", stale)], kind: .strip,
                  seen: ["sess-a", "sess-b"]),
            .init(name: "07-strip-broken",
                  files: [("c.json", broken), ("d.json", stale)], kind: .strip),
            .init(name: "01-declared-but-drifting",
                  files: [("a.json", drifting), ("b.json", undeclared), ("d.json", stale)]),
            .init(name: "02-undeclared",
                  files: [("b.json", undeclared), ("d.json", stale)]),
            .init(name: "03-plugin-broken",
                  files: [("c.json", broken), ("d.json", stale)]),
            .init(name: "04-empty", files: []),
            .init(name: "08-detail",
                  files: [("a.json", drifting), ("b.json", undeclared), ("d.json", stale)],
                  kind: .detail, logs: [("sess-a.log.jsonl", sampleLog)]),
        ]
    }
}
