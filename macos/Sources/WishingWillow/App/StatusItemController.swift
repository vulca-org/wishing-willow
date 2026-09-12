import AppKit
import SwiftUI

/// The always-on strip, and the two things that open out of it.
///
/// `NSStatusItem` rather than a panel over the notch, and that is a deliberate
/// retreat. Every notch app — boring.notch, Alcove, NotchNook — puts an
/// `NSPanel` at `level = .mainMenu + 3` over the same rectangle, and **macOS
/// does not arbitrate between them**: whoever ordered front last wins, and the
/// hover goes to whatever is on top. The notch is first-come-first-served
/// ground. The menu bar is the opposite: the system lays it out, overlap is
/// impossible, and it works on external displays and Macs with no notch.
///
/// The cost is honest and must not be hidden: in a fullscreen app the menu bar
/// hides, and so does this. A notch panel would survive that. Notch mode is a
/// future opt-in that has to stand down when another notch app is running.
@MainActor
final class StatusItemController: NSResponder {
    private let store: WillowStore
    private let seen = SeenStore()

    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var detail: NSWindow?
    private var tracking: NSTrackingArea?
    private var autoCollapse: Timer?

    init(store: WillowStore) {
        self.store = store
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不从 nib 里来") }

    func start() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let label = NSHostingView(rootView: CompactLabel(store: store, seen: seen))
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])

        popover.behavior = .applicationDefined
        popover.animates = false

        store.onTurnStarted = { [weak self] s in self?.flash(for: s) }
        store.start()
        refreshTracking()
    }

    /// Hover is the primary way in — the design calls for it explicitly, and a
    /// `MenuBarExtra` cannot do it, which is why this file exists at all.
    private func refreshTracking() {
        guard let button = item.button else { return }
        if let t = tracking { button.removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        button.addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        expand(markSeen: true)
    }

    override func mouseExited(with event: NSEvent) {
        // 未读和 ⚠ 两态不自动收回：报警要留在那儿等人看见。
        // 而悬停本身已经把它标成已读了，所以这里收回是对的。
        collapse()
    }

    /// Six seconds, static, right after a turn starts. Not a marquee: reading
    /// moving text costs more than reading still text, and the signal is only
    /// useful in the seconds right after you press enter — a ticker delivers on
    /// its own schedule, not yours. Motion is for alerting; stillness carries
    /// content.
    private func flash(for session: SessionState) {
        expand(markSeen: false)
        autoCollapse?.invalidate()
        autoCollapse = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
    }

    private func expand(markSeen: Bool) {
        guard let button = item.button, !popover.isShown else { return }
        if markSeen, let s = store.sessions.first { seen.markSeen(s) }
        popover.contentViewController = NSHostingController(
            rootView: PanelView(store: store).frame(width: 460)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    private func collapse() {
        autoCollapse?.invalidate()
        autoCollapse = nil
        if popover.isShown { popover.performClose(nil) }
    }

    @objc private func clicked() {
        collapse()
        if let w = detail, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "许愿柳"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: DetailView(store: store, seen: seen))
        detail = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for s in store.sessions { seen.markSeen(s) }
    }
}
