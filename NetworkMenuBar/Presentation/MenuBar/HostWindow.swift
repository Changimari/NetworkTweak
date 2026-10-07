import AppKit
import SwiftUI

/// SwiftUIビューを通常のウィンドウで開くためのヘルパー。
/// メニューバーの小さなポップオーバーからシートを出すとmacOS 26で表示が崩れるため、
/// 設定・スキャン・詳細などはこのウィンドウで開く。
/// close()が呼ばれるまで自身を保持する。
@MainActor
final class HostWindow: NSWindowController, NSWindowDelegate {
    private static var retained: [HostWindow] = []

    /// `content` にはウィンドウを閉じるクロージャが渡される（旧 dismiss() の置き換え）
    init<V: View>(title: String, size: CGSize, @ViewBuilder content: (@escaping () -> Void) -> V) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        super.init(window: window)
        var close: () -> Void = {}
        window.contentViewController = NSHostingController(rootView: content({ close() }))
        close = { [weak self] in self?.close() }
        window.delegate = self
        window.center()
        window.isReleasedWhenClosed = false
        HostWindow.retained.append(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        // ポップオーバーと同じく、メニューバーアイコンの真下・中央揃えに出す（ポップオーバーは閉じる）
        StatusBarController.closePopover?()
        if let window, let icon = StatusBarController.iconScreenFrame {
            let screen = NSScreen.screens.first { $0.frame.intersects(icon) } ?? NSScreen.main
            if let vf = screen?.visibleFrame {
                let w = window.frame.width
                let x = min(max(icon.midX - w / 2, vf.minX + 8), vf.maxX - w - 8)
                window.setFrameTopLeftPoint(NSPoint(x: x, y: min(icon.minY, vf.maxY) - 6))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        HostWindow.retained.removeAll { $0 === self }
    }
}
