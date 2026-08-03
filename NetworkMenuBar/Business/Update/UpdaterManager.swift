import Foundation
import Combine
import Sparkle

/// Sparkleによる自動アップデートを管理するクラス
/// 「アップデートを確認」ボタンから呼び出し、ダウンロード〜入れ替え〜再起動まで自動で行う
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    /// 自動アップデートを有効にするか（ユーザー設定）
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// 現在アップデート確認が可能か
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true で起動時にバックグラウンドチェックが走る
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        // 確認可否をバインド
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// 手動でアップデートを確認（ユーザーがボタンを押した時）
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
