import Foundation
import SwiftUI
import Combine

/// アプリ全体の状態を管理するクラス
@MainActor
final class AppState: ObservableObject {
    @Published var networkManager: NetworkManager
    @Published var settings: AppSettings
    @Published var ipMemoStore: IPMemoStore
    @Published var networkChangeMonitor: NetworkChangeMonitor
    let networkScanner = NetworkScanner()  // スキャン結果をシート再表示後も保持

    private var cancellables = Set<AnyCancellable>()

    /// ネットワーク変更ハンドラの多重実行を防ぐフラグ
    private var isHandlingNetworkChange = false

    init() {
        self.networkManager = NetworkManager()
        self.settings = AppSettings.load()
        self.ipMemoStore = IPMemoStore()
        self.networkChangeMonitor = NetworkChangeMonitor.shared

        // IPMemoStoreの変更をAppStateに転送
        ipMemoStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // ネットワーク変更監視の設定
        setupNetworkChangeMonitor()
    }

    func saveSettings() {
        settings.save()
    }

    /// ネットワーク変更監視を設定
    private func setupNetworkChangeMonitor() {
        networkChangeMonitor.onWiFiLinkChanged = { [weak self] in
            guard let self = self else { return }
            await self.handleWiFiLinkChanged()
        }

        // 監視を開始
        networkChangeMonitor.startMonitoring()
    }

    /// Wi-FiのAPが切り替わった時の処理
    ///
    /// 固定IPのまま別APに移動するとネットに繋がらなくなるため、
    /// AP切り替えを検知したら固定IPを問答無用でDHCPに戻す。
    /// 機器設定用APで再び固定にしたい時は手動で設定する。
    private func handleWiFiLinkChanged() async {
        guard settings.autoResetOnNetworkChange else { return }
        guard !isHandlingNetworkChange else { return }
        isHandlingNetworkChange = true
        defer { isHandlingNetworkChange = false }

        // ユーザーが直前に固定IPを適用した場合、そのリンクのゆらぎで戻さない（誤リセット防止）
        if Date().timeIntervalSince(networkManager.lastUserApply) < 15 {
            return
        }

        await networkManager.fetchAdapters()

        // Wi-Fiアダプタを特定（接続中のみ対象）
        guard let wifi = networkManager.adapters.first(where: { $0.type == .wifi }) else { return }
        guard wifi.status == .connected else { return }

        // 固定IPならDHCPに戻す（DHCPのままなら何もしない）
        if wifi.ipConfiguration?.configureIPv4 == .manual {
            try? await networkManager.emergencyResetToDHCP(serviceName: wifi.hardwarePort)
        }
    }
}

/// アプリ設定
struct AppSettings: Codable {
    var launchAtLogin: Bool = false
    var showSpeedInMenuBar: Bool = false
    var speedUnit: SpeedUnit = .adaptive
    var refreshInterval: TimeInterval = 2.0
    var showIPv6: Bool = false
    var externalIPCheckURL: String = "https://api.ipify.org"
    var autoFillGateway: Bool = true  // ゲートウェイ自動補完
    var autoResetOnNetworkChange: Bool = true  // Wi-Fi切り替え時に自動でDHCPに戻す

    private static let key = "AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.key)
        }
    }
}

enum SpeedUnit: String, Codable, CaseIterable {
    case bitsPerSecond = "bps"
    case bytesPerSecond = "B/s"
    case adaptive = "Auto"

    var displayName: String {
        switch self {
        case .bitsPerSecond: return "ビット/秒 (bps)"
        case .bytesPerSecond: return "バイト/秒 (B/s)"
        case .adaptive: return "自動"
        }
    }
}
