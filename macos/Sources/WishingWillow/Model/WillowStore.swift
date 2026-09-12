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

    /// 实时读到的进行中这一轮，键是「会话|轮次」——换了一轮不串到新一轮上。
    /// 临时的：整轮结束后以插件在 Stop 写下的为准。
    private(set) var liveProgress: [String: TurnProgress] = [:]

    enum WithdrawKind: Sendable, Equatable { case interrupted, queued }
    struct Withdraw: Sendable, Equatable { let kind: WithdrawKind; let at: Date }
    /// 最近的撤回事件（按会话），只显示几秒，过期自动清掉。
    private(set) var recentWithdraw: [String: Withdraw] = [:]
    static let withdrawShown: TimeInterval = 2.5
    var onWithdraw: ((SessionState, WithdrawKind) -> Void)?

    func noteWithdraw(sessionId: String, kind: WithdrawKind) {
        let w = Withdraw(kind: kind, at: Date())
        recentWithdraw[sessionId] = w
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.withdrawShown))
            guard let self, self.recentWithdraw[sessionId] == w else { return }
            self.recentWithdraw[sessionId] = nil
            self.onLiveChange?()
        }
    }

    private func liveKey(_ s: SessionState) -> String? { s.record.turnId.map { "\(s.id)|\($0)" } }

    private func attachLive(_ s: SessionState, now: Date) -> SessionState {
        let lp = liveKey(s).flatMap { liveProgress[$0] }
        return SessionState(record: s.record, now: now,
                            liveLastEvent: lp?.lastEventAt ?? s.liveLastEvent,
                            liveInterruptedAt: lp?.interruptedAt)
    }

    /// 活的在前；再按最近一次动静排序——状态文件的时间和实时读到的最后一次落盘，取较晚的。
    /// 只看状态文件时间时，正在跑的会话（状态文件一轮内不更新）会排到刚结束的会话后面。
    static func sort(_ xs: [SessionState]) -> [SessionState] {
        xs.sorted { a, b in
            if a.isStale != b.isStale { return !a.isStale }
            return activity(a) > activity(b)
        }
    }

    static func activity(_ s: SessionState) -> Date {
        [s.record.updatedAt, s.liveLastEvent].compactMap { $0 }.max() ?? .distantPast
    }
    private let follower = TranscriptFollower()
    /// 已经触发过「声明到达」的轮次（会话|轮次）。实时读先到、Stop 后到，只展开一次。
    private var arrivedTurns: Set<String> = []
    private var liveTimer: Timer?
    /// 实时进度有实质变化（声明到了、多了一步、开始落盘）时回调——展开态据此重算高度。
    var onLiveChange: (() -> Void)?

    func progress(for s: SessionState) -> TurnProgress? {
        guard s.declaration == .inProgress || s.declaration == .interrupted, let k = liveKey(s) else { return nil }
        return liveProgress[k]
    }

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

        // 进行中的轮次每秒读一次聊天记录。没有进行中的轮次时什么都不读。
        let lt = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.sessions.contains(where: { $0.declaration == .inProgress }) else { return }
                self.refreshLive()
            }
        }
        lt.tolerance = 0.3
        RunLoop.main.add(lt, forMode: .common)
        liveTimer = lt
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        poll?.invalidate()
        poll = nil
        liveTimer?.invalidate()
        liveTimer = nil
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
            let lp = liveProgress["\(record.sessionId)|\(record.turnId ?? "")"]
            found.append(SessionState(record: record, now: now,
                                      liveLastEvent: lp?.lastEventAt, liveInterruptedAt: lp?.interruptedAt))
        }

        // 先排一次、读实时进度，再把实时事件挂回去——陈旧判定与排序都要用到它。
        // 以前要等下一次扫描（5 秒后）才挂上：app 刚启动时，状态文件超过 10 分钟没更新的进行中轮次被误判过期。
        sessions = Self.sort(found)
        refreshLive()
        found = sessions.map { attachLive($0, now: now) }

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

        sessions = Self.sort(found)

        // 首次扫描不算「刚开始」——那只是 app 启动时看到的既有状态。
        if primed, let s = started.max(by: { ($0.record.updatedAt ?? .distantPast) < ($1.record.updatedAt ?? .distantPast) }) {
            onTurnStarted?(s)
        }

        var arrived: [SessionState] = []
        for s in found {
            guard let turn = s.record.turnId else { continue }
            let has = s.record.decode?.isEmpty == false
            if let had = lastDecoded[s.id], had.turn == turn, !had.decoded, has, !s.isStale,
               !arrivedTurns.contains("\(s.id)|\(turn)") {
                arrivedTurns.insert("\(s.id)|\(turn)")
                arrived.append(s)
            }
            lastDecoded[s.id] = (turn, has)
        }
        if primed, let s = arrived.max(by: { ($0.record.updatedAt ?? .distantPast) < ($1.record.updatedAt ?? .distantPast) }) {
            onDeclarationArrived?(s)
        }
        primed = true
        onReload?()
    }

    /// 读进行中（以及刚被打断）各轮新增的聊天记录。只读不写。
    func refreshLive() {
        var next: [String: TurnProgress] = [:]
        var changed = false
        var interruptChanged = false
        var withdrawals: [(SessionState, WithdrawKind)] = []
        for s in sessions where s.declaration == .inProgress || s.declaration == .interrupted {
            guard let pid = s.record.pid, SessionState.processIsAlive(pid),
                  let path = s.record.transcriptPath, let off = s.record.transcriptOffset,
                  let key = liveKey(s) else { continue }
            guard let p = follower.progress(key: key, path: path, offset: off) else { continue }
            let old = liveProgress[key]
            if old?.decode != p.decode || old?.steps.count != p.steps.count
                || old?.firstWriteAt != p.firstWriteAt || old?.thinkingSeen != p.thinkingSeen { changed = true }
            if (old?.interruptedAt == nil) != (p.interruptedAt == nil) { interruptChanged = true }
            next[key] = p
            if primed {                                             // 启动时已有的事件不闪
                if p.decode != nil, p.interruptedAt == nil, !arrivedTurns.contains(key) {
                    arrivedTurns.insert(key)
                    onDeclarationArrived?(s)
                }
                if p.interruptedAt != nil, old != nil, old?.interruptedAt == nil { withdrawals.append((s, .interrupted)) }
                if p.withdrawnQueued.count > (old?.withdrawnQueued.count ?? p.withdrawnQueued.count) {
                    withdrawals.append((s, .queued))
                }
            } else if p.decode != nil {
                arrivedTurns.insert(key)
            }
        }
        if next.count != liveProgress.count { changed = true }
        liveProgress = next
        follower.forget(keeping: Set(next.keys))
        let current = Set(sessions.compactMap(liveKey))
        arrivedTurns.formIntersection(current)

        // 打断要立刻反映到声明状态上，不等下一次 5 秒的整体扫描。
        if interruptChanged {
            let now = Date()
            sessions = Self.sort(sessions.map { s in
                let lp = liveKey(s).flatMap { next[$0] }
                return SessionState(record: s.record, now: now,
                                    liveLastEvent: lp?.lastEventAt ?? s.liveLastEvent,
                                    liveInterruptedAt: lp?.interruptedAt)
            })
            changed = true
        }
        for (s, kind) in withdrawals {
            noteWithdraw(sessionId: s.id, kind: kind)
            let fresh = sessions.first { $0.id == s.id } ?? s
            onWithdraw?(fresh, kind)
            changed = true
        }
        if changed { onLiveChange?() }
    }

    private var primed = false
}
