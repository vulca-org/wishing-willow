import AppKit
import SwiftUI

/// `--selfshot <目录>` —— 让 app 把**自己真实的界面**拍下来。
///
/// 为什么要有这个：`ImageRenderer`（`--snapshot`）画的不是真实界面。它没有活的
/// 合成器，玻璃不画、材质不画、深浅色也不是系统实际给的那套，于是我按那些图
/// 改了半天样式，改的是一个和屏幕上不一样的东西。系统截屏又要屏幕录制权限，
/// 这台机器上拿不到。
///
/// `cacheDisplay(in:to:)` 拍的是 app 自己的视图层级，**不需要任何权限**，
/// 而且走的是真实合成器 —— 玻璃、vibrancy、外观模式全都是真的。
/// 它拍不到的只有一样：这些窗口在整块屏幕上的位置。那一点必须说明，不能混过去。
@MainActor
enum SelfShot {
    static func run(outputDirectory: String) {
        let out = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let store = WillowStore(directory: fixtureDirectory())
        let controller = StatusItemController(store: store)
        controller.start()

        // 先浅色后深色，各拍一轮。
        var pending: [(String, NSAppearance.Name)] = [
            ("light", .aqua), ("dark", .darkAqua),
        ]

        func next() {
            guard !pending.isEmpty else {
                print(try! FileManager.default.contentsOfDirectory(atPath: out.path).sorted().joined(separator: "\n"))
                app.terminate(nil)
                return
            }
            let (name, appearance) = pending.removeFirst()
            NSApp.appearance = NSAppearance(named: appearance)
            controller.presentForCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                capture(controller.captureTargets(), prefix: name, into: out)
                if name == "light" { dumpGeometry(into: out) }
                controller.dismissAfterCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next() }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { next() }
        app.run()
    }

    /// 位置是 cacheDisplay 拍不到的那一样，但它不需要画面也能量：
    /// CGWindowListCopyWindowInfo 给窗口坐标不要屏幕录制权限（只有标题会被抹掉）。
    /// 拿它和刘海的实际坐标比，「弹出来的东西在不在灵动岛的位置」就是一个数，不是一个印象。
    private static func dumpGeometry(into dir: URL) {
        var lines: [String] = []
        lines.append("screenCapturePreflight=\(CGPreflightScreenCaptureAccess())")
        if let screen = NSScreen.main {
            let f = screen.frame
            lines.append("screen=\(Int(f.width))x\(Int(f.height))")
            if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
                lines.append("notch.x=\(Int(l.width))...\(Int(f.width - r.width)) notch.h=\(Int(screen.safeAreaInsets.top))")
            } else {
                lines.append("notch=none")
            }
        }
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        for w in info where (w[kCGWindowOwnerPID as String] as? Int32) == getpid() {
            let b = w[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let layer = w[kCGWindowLayer as String] as? Int ?? -1
            lines.append("window layer=\(layer) x=\(Int(b["X"] ?? -1)) y=\(Int(b["Y"] ?? -1)) w=\(Int(b["Width"] ?? -1)) h=\(Int(b["Height"] ?? -1))")
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: dir.appendingPathComponent("geometry.txt"), atomically: true, encoding: .utf8)
    }

    private static func capture(_ targets: [(String, NSView)], prefix: String, into dir: URL) {
        for (label, view) in targets {
            let bounds = view.bounds
            guard bounds.width > 1, bounds.height > 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: bounds)
            else { continue }
            view.cacheDisplay(in: bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent("\(prefix)-\(label).png"))
        }
    }

    static func fixtureDirectoryForDemo() -> URL { fixtureDirectory() }

    /// 固定样例，和 `--snapshot` 用同一批，好让两条路拍的是同一件事。
    private static func fixtureDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("willow-selfshot-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, json) in Snapshot.selfShotFixtures {
            try? Data(json.utf8).write(to: dir.appendingPathComponent(name))
        }
        try? Data(Snapshot.sampleLog.utf8).write(to: dir.appendingPathComponent("sess-a.log.jsonl"))
        return dir
    }
}
