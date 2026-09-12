import Foundation

/// Which turn of each session you have actually looked at.
///
/// This lives in Application Support, **not** in `~/.claude/willow/`. The reader
/// never writes a byte into the plugin's directory — not "shouldn't", cannot be
/// confused into it, because it does not hold a writable path there at all.
///
/// A turn counts as seen only when you hover or open the detail window. The
/// six-second auto-expansion does **not** mark it seen: the panel appearing at
/// the top of the screen is not evidence that anyone looked at it.
@MainActor
final class SeenStore {
    private var seen: [String: String] = [:]      // sessionId → turnId
    private let url: URL
    private let ephemeral: Bool

    /// 不落盘的一份，给离屏快照用：快照必须可复现，不能取决于这台机器上
    /// 恰好读过哪几轮。
    init(ephemeral: Bool) {
        self.ephemeral = ephemeral
        url = URL(fileURLWithPath: "/dev/null")
    }

    init() {
        ephemeral = false
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("WishingWillow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("seen.json")
        if let data = try? Data(contentsOf: url),
           let d = try? JSONDecoder().decode([String: String].self, from: data) {
            seen = d
        }
    }

    func isUnread(_ s: SessionState) -> Bool {
        guard let turn = s.record.turnId else { return false }
        return seen[s.id] != turn
    }

    /// 测试与快照用：直接把某一轮标成已读。
    func markSeen(sessionId: String, turnId: String) {
        seen[sessionId] = turnId
        persist()
    }

    func markSeen(_ s: SessionState) {
        guard let turn = s.record.turnId, seen[s.id] != turn else { return }
        seen[s.id] = turn
        persist()
    }

    /// Forget sessions that no longer have state. Keeps the file from growing
    /// forever without ever deleting anything the plugin owns.
    func forgetMissing(keeping ids: Set<String>) {
        let before = seen.count
        seen = seen.filter { ids.contains($0.key) }
        if seen.count != before { persist() }
    }

    private func persist() {
        if ephemeral { return }
        guard let data = try? JSONEncoder().encode(seen) else { return }
        let tmp = url.appendingPathExtension("\(getpid()).tmp")
        do {
            try data.write(to: tmp)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
