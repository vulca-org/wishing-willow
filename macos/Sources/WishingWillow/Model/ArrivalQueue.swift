/// 声明到达的排队。
///
/// 两个会话先后到达时，先前的做法是后到的直接顶掉正在展开的那个——你刚读到一半的「我读成了」
/// 被换成另一个会话的。实测两天里 60 秒内先后到达 2 次、5 分钟内 12 次，不多，但每一次都是
/// 读到一半被换掉。改为：正在展示时后到的排在后面，当前这个收起后再轮到它。
struct ArrivalQueue: Equatable {
    private(set) var waiting: [String] = []

    /// 返回 true = 现在就展示；false = 已排队（或本来就在展示）。
    mutating func offer(_ id: String, showing: String?) -> Bool {
        guard let showing else { return true }
        if showing == id { return false }
        if !waiting.contains(id) { waiting.append(id) }
        return false
    }

    /// 取下一个还活着的会话；等待期间结束了的直接丢掉。
    mutating func next(alive: Set<String>) -> String? {
        while let first = waiting.first {
            waiting.removeFirst()
            if alive.contains(first) { return first }
        }
        return nil
    }
}
