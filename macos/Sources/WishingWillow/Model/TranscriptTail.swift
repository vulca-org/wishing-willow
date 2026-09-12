import Foundation

/// 一轮进行中的真实进度，从 Claude Code 的聊天记录里读出来。
///
/// 为什么要读：2026-09-12 用今天 7 轮真实数据量过，插件只在整轮结束时读声明，
/// 声明写出后在后台躺着没显示的时间中位 280 秒、最长 31 分钟——等你看到时，
/// 模型早按那个理解干完了。聊天记录是边写边落盘的，而 7/7 轮里声明都早于第一次工具调用。
///
/// 这里读到的声明是**临时的**：整轮结束后以插件在 Stop 时写下的为准。
/// 解析规则与插件 extract 是两份实现，由 TranscriptTailTests 用同一批回放用例对照钉住。
struct TurnProgress: Sendable, Equatable {
    struct Step: Sendable, Equatable {
        var at: Date?
        var text: String
    }

    var firstWriteAt: Date?
    var lastEventAt: Date?
    /// 只记「有没有思考过」：思考块在聊天记录里没有文字，想了什么读不到。
    var thinkingSeen = false
    var decode: String?
    var tag: String?
    var declaredAt: Date?
    var steps: [Step] = []
    /// 你按了打断。聊天记录里会出现一条「[Request interrupted by user]」的用户消息
    /// （2026-09-12 盘点两天记录：17 次，写法只有这一种）。打断不触发 Stop，不读这一条，
    /// 灵动岛会一直停在「回答中」。
    var interruptedAt: Date?
    /// 撤回的排队消息。这种撤回不经过插件钩子，状态文件毫无变化，只有聊天记录里有一行
    /// （两天 92 次排队移除，88 次是系统通知，4 次是用户自己的文字）。
    var withdrawnQueued: [String] = []
    /// 模型停下来等你做选择：AskUserQuestion 选择题或 ExitPlanMode 批准计划，还没收到回答。
    /// 这段时间模型什么都不写（本机 89 次中位 88 秒、最长 1,357 秒），只看落盘会以为它卡住或已结束。
    /// 问题与回答靠 tool_use 的 id 与回答里的 tool_use_id 对上（89/89 对）。
    struct Choice: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case question, plan }
        var id: String
        var kind: Kind
        var at: Date?
        var header: String?
        var question: String?
        var options: [String]
        var count: Int
    }
    var pendingChoice: Choice?

    mutating func ingest(_ row: [String: Any]) {
        guard (row["isSidechain"] as? Bool) != true else { return }
        let at = (row["timestamp"] as? String).flatMap(WillowRecord.parseISO8601)
        switch row["type"] as? String {
        case "assistant": break
        case "user": noteInterrupt(row, at: at); noteToolResult(row); return
        case "queue-operation": noteQueueRemove(row); return
        default: return
        }
        if firstWriteAt == nil { firstWriteAt = at }
        if let at { lastEventAt = at }
        let message = row["message"] as? [String: Any]
        if let s = message?["content"] as? String {
            absorb(s, at: at)
            return
        }
        guard let blocks = message?["content"] as? [[String: Any]] else { return }
        for b in blocks {
            switch b["type"] as? String {
            case "thinking":
                thinkingSeen = true
            case "text":
                if let s = b["text"] as? String { absorb(s, at: at) }
            case "tool_use":
                steps.append(Step(at: at, text: TranscriptTail.describe(
                    tool: b["name"] as? String ?? "", input: b["input"] as? [String: Any] ?? [:])))
                noteChoice(b, at: at)
            default:
                break
            }
        }
    }

    private mutating func noteInterrupt(_ row: [String: Any], at: Date?) {
        let c = (row["message"] as? [String: Any])?["content"]
        let text = (c as? String) ?? (c as? [[String: Any]])?
            .compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ")
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              t.hasPrefix("[Request interrupted by user") else { return }
        if interruptedAt == nil { interruptedAt = at ?? Date() }
        pendingChoice = nil                                  // 打断就不再等你选了
    }

    private mutating func noteChoice(_ b: [String: Any], at: Date?) {
        let input = b["input"] as? [String: Any] ?? [:]
        let id = b["id"] as? String ?? ""
        switch b["name"] as? String {
        case "AskUserQuestion":
            let qs = input["questions"] as? [[String: Any]] ?? []
            let first = qs.first
            pendingChoice = Choice(id: id, kind: .question, at: at,
                                   header: first?["header"] as? String,
                                   question: first?["question"] as? String,
                                   options: (first?["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String },
                                   count: max(1, qs.count))
        case "ExitPlanMode":
            // 计划是 markdown，取第一行非空内容当题面（去掉标题的 #）。
            let title = (input["plan"] as? String)?
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces)) }
                .first { !$0.isEmpty }
            pendingChoice = Choice(id: id, kind: .plan, at: at, header: "计划", question: title, options: [], count: 1)
        default:
            break
        }
    }

    private mutating func noteToolResult(_ row: [String: Any]) {
        guard let pending = pendingChoice,
              let blocks = (row["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
        if blocks.contains(where: { ($0["type"] as? String) == "tool_result" && ($0["tool_use_id"] as? String) == pending.id }) {
            pendingChoice = nil
        }
    }

    private mutating func noteQueueRemove(_ row: [String: Any]) {
        guard (row["operation"] as? String) == "remove",
              let c = (row["content"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !c.isEmpty, !c.hasPrefix("<task-notification") else { return }
        withdrawnQueued.append(c)
    }

    private mutating func absorb(_ text: String, at: Date?) {
        guard decode == nil, let hit = TranscriptTail.scanMessage(text) else { return }
        decode = hit.decode
        tag = hit.tag
        declaredAt = at
    }
}

enum TranscriptTail {
    static let scanLines = 12

    nonisolated(unsafe) private static let decodeRE = try! NSRegularExpression(
        pattern: #"^\s*(?:我读成了|我理解为|How I read it|Read as)\s*[：:]\s*(.+?)\s*$"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let tagRE = try! NSRegularExpression(
        pattern: #"^\s*(?:标签|Tag)\s*[：:]\s*(.+?)\s*$"#, options: [.caseInsensitive])
    nonisolated(unsafe) private static let indentedRE = try! NSRegularExpression(pattern: #"^\s{4,}\S"#)

    /// 与插件 extract.mjs 的 scanMessage 同一套规则：前 12 个有效行；跳过代码栅栏、引用块、缩进代码。
    static func scanMessage(_ message: String) -> (decode: String, tag: String?)? {
        var seen = 0
        var fence: Character? = nil
        var decode: String? = nil
        var tag: String? = nil
        for raw in message.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let kind = t.first!
                if fence == kind { fence = nil } else if fence == nil { fence = kind }
                continue
            }
            if fence != nil { continue }
            if t.isEmpty || t.hasPrefix(">") { continue }
            if matches(indentedRE, line) { continue }
            seen += 1
            if seen > scanLines { break }
            if decode == nil, let g = group(decodeRE, line) { decode = g.isEmpty ? nil : g }
            if tag == nil, let g = group(tagRE, line) { tag = g.isEmpty ? nil : g }
            if decode != nil && tag != nil { break }
        }
        guard let d = decode else { return nil }
        return (d, tag)
    }

    /// 工具调用变成一句人话。字段选择来自今天真实记录的盘点：Bash 663/663 次带 description。
    static func describe(tool: String, input: [String: Any]) -> String {
        func str(_ k: String) -> String? {
            guard let v = (input[k] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        func base(_ p: String?) -> String? { p.map { ($0 as NSString).lastPathComponent } }
        let text: String
        switch tool {
        case "Bash": text = str("description") ?? "运行命令"
        case "Read": text = "读 " + (base(str("file_path")) ?? "文件")
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            text = "改 " + (base(str("file_path") ?? str("notebook_path")) ?? "文件")
        case "Grep", "Glob": text = str("pattern").map { "找 " + $0 } ?? "搜索文件"
        case "WebSearch": text = str("query").map { "搜 " + $0 } ?? "联网搜索"
        case "WebFetch": text = "取 " + (str("url").flatMap { URL(string: $0)?.host } ?? "网页")
        case "Agent", "Task": text = str("description") ?? "派子代理"
        case "ToolSearch": text = "加载工具"
        default:
            text = tool.hasPrefix("mcp__") ? (tool.components(separatedBy: "__").last ?? tool) : tool
        }
        return text.count > 60 ? String(text.prefix(59)) + "…" : text
    }

    /// 偏移为空时（续接会话的第一轮：Claude Code 按回车几毫秒后才新建文件，并把全部历史抄进去），
    /// 从文件末尾往回找与原话一致的最后一条真实用户消息，返回那一行的起始字节。
    /// **不能当成 0**：2026-09-12 实测那个会话抄进来 10.3 MB 历史，从头读会把前一天的旧声明当成这一轮的。
    static func locateTurnStart(path: String, prompt: String) -> Int? {
        let want = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !want.isEmpty, let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = Int((try? h.seekToEnd()) ?? 0)
        let window = min(size, 32 << 20)
        let base = size - window
        try? h.seek(toOffset: UInt64(base))
        guard let data = try? h.read(upToCount: window), !data.isEmpty else { return nil }
        let needle = Data("\"type\":\"user\"".utf8)
        var end = data.endIndex
        var hit: Int? = nil
        while end > data.startIndex {
            let lineStart = data[..<end].lastIndex(of: 0x0A).map { data.index(after: $0) } ?? data.startIndex
            if lineStart == data.startIndex && base > 0 { break }          // 窗口第一段是半行
            let line = data[lineStart..<end]
            if !line.isEmpty, line.range(of: needle) != nil,
               let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               userText(obj) == want {
                hit = base + (lineStart - data.startIndex)
                break                                                       // 往回找到的第一条就是最后一条
            }
            end = lineStart == data.startIndex ? data.startIndex : data.index(before: lineStart)
        }
        return hit
    }

    /// 真实用户消息的文字（不是工具结果、不是子代理、不是元消息），与插件判定一致。
    static func userText(_ row: [String: Any]) -> String? {
        guard (row["type"] as? String) == "user", (row["isSidechain"] as? Bool) != true,
              (row["isMeta"] as? Bool) != true else { return nil }
        let c = (row["message"] as? [String: Any])?["content"]
        if let s = c as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let arr = c as? [[String: Any]],
              !arr.contains(where: { ($0["type"] as? String) == "tool_result" }) else { return nil }
        return arr.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func group(_ re: NSRegularExpression, _ s: String) -> String? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
}

/// 边写边读：记住每一轮读到哪儿，下次只读新增的部分；半行留到读到换行再解析。
@MainActor
final class TranscriptFollower {
    private struct Cursor {
        var offset: Int
        var readTo: Int
        var remainder = Data()
        var progress = TurnProgress()
    }

    private var cursors: [String: Cursor] = [:]
    static let chunkCap = 4 << 20

    /// key 用「会话|轮次」：换了一轮自然从新偏移重来。
    func progress(key: String, path: String, offset: Int) -> TurnProgress? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = Int((try? h.seekToEnd()) ?? 0)
        // 文件比偏移还短 = 被重写过（例如 compact），偏移作废，定位不了这一轮，不瞎读。
        guard size >= offset else { cursors[key] = nil; return nil }
        var c = cursors[key] ?? Cursor(offset: offset, readTo: offset)
        if c.offset != offset || size < c.readTo { c = Cursor(offset: offset, readTo: offset) }
        if size > c.readTo {
            try? h.seek(toOffset: UInt64(c.readTo))
            let data = (try? h.read(upToCount: min(size - c.readTo, Self.chunkCap))) ?? Data()
            c.readTo += data.count
            let buf = c.remainder + data
            var start = buf.startIndex
            while let nl = buf[start...].firstIndex(of: 0x0A) {
                let line = Data(buf[start..<nl])
                if !line.isEmpty, let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                    c.progress.ingest(obj)
                }
                start = buf.index(after: nl)
            }
            c.remainder = Data(buf[start...])
        }
        cursors[key] = c
        return c.progress
    }

    func forget(keeping keys: Set<String>) {
        cursors = cursors.filter { keys.contains($0.key) }
    }
}
