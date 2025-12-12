import AppKit
import SwiftUI
import Combine

/// メニューバーのステータスアイテムを管理するクラス
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var eventMonitor: Any?
    private let appState: AppState
    private let speedMonitor = NetworkSpeedMonitor()
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState

        // ステータスバーにアイテムを作成
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // ポップオーバーを作成
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 450)
        popover.behavior = .transient
        popover.animates = true

        super.init()

        // ボタンを設定
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 外部クリックでポップオーバーを閉じる
        setupEventMonitor()

        // 速度監視を設定
        setupSpeedMonitoring()
    }

    /// 速度監視を設定
    private func setupSpeedMonitoring() {
        // 速度が更新されたらメニューバーを更新
        speedMonitor.$downloadSpeed
            .combineLatest(speedMonitor.$uploadSpeed)
            .sink { [weak self] download, upload in
                self?.updateMenuBarWithSpeed(download: download, upload: upload)
            }
            .store(in: &cancellables)

        // 設定に応じて監視を開始
        if appState.settings.showSpeedInMenuBar {
            speedMonitor.startMonitoring(interval: appState.settings.refreshInterval)
        }

        // 設定の変更を監視
        appState.$settings
            .dropFirst() // 初回の値は無視
            .sink { [weak self] settings in
                self?.handleSettingsChange(settings)
            }
            .store(in: &cancellables)
    }

    /// 設定変更を処理
    private func handleSettingsChange(_ settings: AppSettings) {
        if settings.showSpeedInMenuBar {
            speedMonitor.startMonitoring(interval: settings.refreshInterval)
        } else {
            speedMonitor.stopMonitoring()
            if let button = statusItem.button {
                button.title = ""
            }
        }
    }

    /// メニューバーを速度表示で更新
    private func updateMenuBarWithSpeed(download: Double, upload: Double) {
        guard appState.settings.showSpeedInMenuBar else {
            // 速度表示が無効の場合はアイコンのみ
            if let button = statusItem.button {
                button.image = createMenuBarIcon()
                button.title = ""
            }
            return
        }

        if let button = statusItem.button {
            button.image = createMenuBarIcon()

            let downloadStr = NetworkSpeedMonitor.formatSpeed(download, unit: appState.settings.speedUnit)
            let uploadStr = NetworkSpeedMonitor.formatSpeed(upload, unit: appState.settings.speedUnit)

            button.title = " ↓\(downloadStr) ↑\(uploadStr)"
        }
    }

    /// 速度表示設定を更新
    func updateSpeedDisplay(enabled: Bool) {
        if enabled {
            speedMonitor.startMonitoring(interval: appState.settings.refreshInterval)
        } else {
            speedMonitor.stopMonitoring()
            if let button = statusItem.button {
                button.title = ""
            }
        }
    }

    /// ポップオーバーの表示/非表示を切り替え
    @objc func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    /// ポップオーバーを表示
    private func showPopover() {
        // 毎回新しいビューを作成（.taskが確実に実行されるように）
        let contentView = MainPopoverView()
            .environmentObject(appState)
        popover.contentViewController = NSHostingController(rootView: contentView)

        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// ポップオーバーを非表示
    private func hidePopover() {
        popover.performClose(nil)
    }

    /// ステータスアイコンを更新
    func updateIcon(isConnected: Bool) {
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
        }
    }

    /// メニューバー用のカスタムアイコンを作成
    private func createMenuBarIcon() -> NSImage? {
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return NSImage(systemSymbolName: "network", accessibilityDescription: "NetworkTweak")
    }

    /// 外部クリック監視を設定
    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.hidePopover()
            }
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // speedMonitorはStatusBarControllerと一緒に解放されるため、
        // タイマーも自動的にinvalidateされる
    }
}
