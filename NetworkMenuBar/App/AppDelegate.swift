import AppKit
import SwiftUI
import Network

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var appState: AppState?
    private var networkMonitor: NWPathMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初回起動時に全ての権限設定を行う
        Task {
            await requestAllPermissions()
        }

        // AppStateを初期化
        appState = AppState()
        // メニューバーコントローラーを初期化
        statusBarController = StatusBarController(appState: appState!)
    }

    /// 初回起動時に全ての権限を要求
    private func requestAllPermissions() async {
        // 1. ローカルネットワークアクセスをトリガー（pingを実行）
        triggerLocalNetworkPermission()

        // 2. 管理者権限のセットアップ
        await setupPrivilegesIfNeeded()
    }

    /// ローカルネットワーク権限をトリガー
    private func triggerLocalNetworkPermission() {
        // NWPathMonitorでネットワーク状態を監視開始（これで権限ダイアログがトリガーされる）
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { path in
            // ネットワーク状態の変更を検知
            print("Network status: \(path.status)")
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .background))

        // 追加でpingを実行してローカルネットワーク権限を確実にトリガー
        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-c", "1", "-W", "100", "192.168.1.1"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    /// 権限設定が未完了の場合、セットアップを実行
    private func setupPrivilegesIfNeeded() async {
        let privilegeManager = PrivilegeManager.shared

        if !privilegeManager.isSetupCompleted {
            do {
                try await privilegeManager.performInitialSetup()
            } catch {
                // エラーが発生してもアプリは続行（手動でパスワード入力が必要になる）
                print("権限設定エラー: \(error.localizedDescription)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // クリーンアップ処理
        networkMonitor?.cancel()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
