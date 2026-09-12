import Foundation
import Observation

/// Reads `~/.claude/willow/*.json` and keeps the UI in step with it.
///
/// Read-only by construction: this type opens files and never writes one. If
/// the directory is missing it stays empty rather than creating it — the
/// plugin owns that directory, and a reader that creates it would make "the
/// plugin never ran" indistinguishable from "the plugin ran and found nothing".
@MainActor
@Observable
final class WillowStore {
    private(set) var sessions: [SessionState] = []
    private(set) var lastScan: Date?
    private(set) var directoryExists = false

    let directory: URL
    /// 一轮刚开始时回调。
    ///
    /// 这是「哪个会话是你正在看的那个」唯一不用猜的判据：capture 写下记录，
    /// 意味着**有人刚按了回车**。后台代理跑完一轮不会触发它，所以不会出现
    /// 「你在 A 会话打字、面板弹出 B 的标签」。
    var onTurnStarted: ((SessionState) -> Void)?

    /// 每次扫描之后调用。灵动岛靠它在「有没有活动会话」变化时重新定宽。
    var onReload: (() -> Void)?

    /// 同一轮里，上一次扫描还没有声明、这一次有了——声明刚到达。
    /// 灵动岛在这一刻展开（用户选的方案）：一展开就有内容可读，而不是在按回车时空展开。
    var onDeclarationArrived: ((SessionState) -> Void)?
    private var lastDecoded: [String: (turn: String, decoded: Bool)] = [:]

    private var lastTurnIds: [String: String] = [:]
    private var watcher: DirectoryWatcher?
    private var poll: Timer?

    init(directory: URL = WillowStore.defaultDirectory) {
        self.directory = directory
    }

    nonisolated static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["WILLOW_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/willow", isDirectory: true)
    }

    func start() {
        reload()
        watcher = DirectoryWatcher(url: directory) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()

        // FSEvents does not fire for a directory that does not exist yet, and the
        // plugin creates it on its first turn. A slow poll covers that gap and the
        // staleness clock, which changes with no file event at all.
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        poll?.invalidate()
        poll = nil
    }

    func reload() {
        let now = Date()
        lastScan = now
        directoryExists = FileManager.default.fileExists(atPath: directory.path)

        guard directoryExists,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else {
            sessions = []
            return
        }

        var found: [SessionState] = []
        for name in names where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(WillowRecord.self, from: data)
            else { continue }   // 半写入或旧格式：跳过，下一次扫描会看到完整的
            found.append(SessionState(record: record, now: now))
        }

        // 一轮刚开始 = turnId 变了、还没有解码、而且这一轮确实问了。
        var started: [SessionState] = []
        for s in found {
            guard let turn = s.record.turnId else { continue }
            let changed = lastTurnIds[s.id] != turn
            lastTurnIds[s.id] = turn
            if changed, s.record.decode == nil, s.record.reminded == true, !s.isStale {
                started.append(s)
            }
        }

        // 活的在前，然后按最近更新排序。
        sessions = found.sorted {
            if $0.isStale != $1.isStale { return !$0.isStale }
            return ($0.record.updatedAt ?? .distantPast) > ($1.record.updatedAt ?? .distantPast)
        }

        // 首次扫描不算「刚开始」——那只是 app 启动时看到的既有状态。
        if primed, let s = started.max(by: { ($0.record.updatedAt ?? .distantPast) < ($1.record.updatedAt ?? .distantPast) }) {
            onTurnStarted?(s)
        }

        var arrived: [SessionState] = []
        for s in found {
            guard let turn = s.record.turnId else { continue }
            let has = s.record.decode?.isEmpty == false
            if let had = lastDecoded[s.id], had.turn == turn, !had.decoded, has, !s.isStale { arrived.append(s) }
            lastDecoded[s.id] = (turn, has)
        }
        if primed, let s = arrived.max(by: { ($0.record.updatedAt ?? .distantPast) < ($1.record.updatedAt ?? .distantPast) }) {
            onDeclarationArrived?(s)
        }
        primed = true
        onReload?()
    }

    private var primed = false
}
