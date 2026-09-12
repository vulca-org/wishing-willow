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

        // 活的在前，然后按最近更新排序。
        sessions = found.sorted {
            if $0.isStale != $1.isStale { return !$0.isStale }
            return ($0.record.updatedAt ?? .distantPast) > ($1.record.updatedAt ?? .distantPast)
        }
    }
}
