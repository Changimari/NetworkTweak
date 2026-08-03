import Foundation
import Network
import SystemConfiguration
import CoreWLAN

/// ネットワーク変更を監視するクラス
/// Wi-Fiのリンク再接続（AP切り替え）を検知して通知する。
/// SSIDは使わない（位置情報権限が不要）。リンクの up/down イベントだけで判定する。
@MainActor
final class NetworkChangeMonitor: NSObject, ObservableObject {
    static let shared = NetworkChangeMonitor()

    @Published private(set) var isMonitoring = false
    @Published private(set) var lastNetworkChange: Date?

    private var wifiClient: CWWiFiClient?

    /// リンクイベントのデバウンス用
    private var debounceTask: Task<Void, Never>?

    /// Wi-Fiのリンクが再接続（AP切り替え）された時のコールバック
    var onWiFiLinkChanged: (() async -> Void)?

    private override init() {
        super.init()
    }

    /// 監視を開始
    func startMonitoring() {
        guard !isMonitoring else { return }

        let client = CWWiFiClient.shared()
        client.delegate = self
        // リンク変化イベント（接続/切断/AP切替）を監視。位置情報権限は不要。
        try? client.startMonitoringEvent(with: .linkDidChange)
        wifiClient = client
        isMonitoring = true
    }

    /// 監視を停止
    func stopMonitoring() {
        try? wifiClient?.stopMonitoringAllEvents()
        wifiClient?.delegate = nil
        wifiClient = nil
        debounceTask?.cancel()
        debounceTask = nil
        isMonitoring = false
    }

    /// リンクイベントを受けて、デバウンスしてからハンドラを呼ぶ
    private func handleLinkEvent() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            // 連続イベント（down→up）をまとめるため少し待つ
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            self.lastNetworkChange = Date()
            await self.onWiFiLinkChanged?()
        }
    }
}

// MARK: - CWEventDelegate

extension NetworkChangeMonitor: CWEventDelegate {
    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            self.handleLinkEvent()
        }
    }
}
