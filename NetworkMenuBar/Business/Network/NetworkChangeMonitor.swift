import Foundation
import Network
import SystemConfiguration

/// ネットワーク変更を監視するクラス
@MainActor
final class NetworkChangeMonitor: ObservableObject {
    static let shared = NetworkChangeMonitor()

    @Published private(set) var isMonitoring = false
    @Published private(set) var lastNetworkChange: Date?

    private var pathMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "NetworkChangeMonitor")

    /// 前回のネットワーク識別子（SSID/インターフェース）
    private var previousNetworkIdentifier: String?

    /// コールバック
    var onNetworkChanged: (() async -> Void)?

    private init() {}

    /// 監視を開始
    func startMonitoring() {
        guard !isMonitoring else { return }

        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                await self?.handlePathUpdate(path)
            }
        }
        pathMonitor?.start(queue: monitorQueue)
        isMonitoring = true

        // 初期状態を記録
        Task {
            previousNetworkIdentifier = await getCurrentNetworkIdentifier()
        }
    }

    /// 監視を停止
    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        isMonitoring = false
    }

    /// パス更新を処理
    private func handlePathUpdate(_ path: NWPath) async {
        // 接続状態の変化を確認
        guard path.status == .satisfied else {
            // 切断時は識別子をクリア
            previousNetworkIdentifier = nil
            return
        }

        let currentIdentifier = await getCurrentNetworkIdentifier()

        // ネットワークが変わったかチェック
        if let previous = previousNetworkIdentifier,
           let current = currentIdentifier,
           previous != current {
            // ネットワークが変わった
            lastNetworkChange = Date()
            await onNetworkChanged?()
        }

        previousNetworkIdentifier = currentIdentifier
    }

    /// 現在のネットワーク識別子を取得
    private func getCurrentNetworkIdentifier() async -> String? {
        // Wi-FiのSSIDまたはインターフェース名を取得
        if let ssid = getWiFiSSID() {
            return "wifi:\(ssid)"
        }

        // Wi-Fiでない場合はインターフェース情報を使用
        return getActiveInterfaceIdentifier()
    }

    /// Wi-FiのSSIDを取得
    private func getWiFiSSID() -> String? {
        // CWWiFiClientを使用してSSIDを取得
        // Note: これにはLocationの権限が必要な場合がある
        guard let interfaces = CWWiFiClient.shared().interfaces(),
              let interface = interfaces.first,
              let ssid = interface.ssid() else {
            return nil
        }
        return ssid
    }

    /// アクティブなインターフェースの識別子を取得
    private func getActiveInterfaceIdentifier() -> String? {
        var identifier: String?

        // SCDynamicStoreを使用してアクティブなインターフェースを取得
        guard let store = SCDynamicStoreCreate(nil, "NetworkChangeMonitor" as CFString, nil, nil) else {
            return nil
        }

        guard let globalIPv4Key = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primaryInterface = globalIPv4Key["PrimaryInterface"] as? String else {
            return nil
        }

        // ルーターのIPアドレスも識別子に含める
        if let router = globalIPv4Key["Router"] as? String {
            identifier = "\(primaryInterface):\(router)"
        } else {
            identifier = primaryInterface
        }

        return identifier
    }
}

// CoreWLANのインポート
import CoreWLAN
