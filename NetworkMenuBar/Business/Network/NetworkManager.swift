import Foundation
import Combine

/// ネットワーク情報を管理するクラス
@MainActor
final class NetworkManager: ObservableObject {
    @Published private(set) var adapters: [NetworkAdapter] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: NetworkError?
    @Published private(set) var externalIP: String?

    private let networkSetupCommand = NetworkSetupCommand()
    private var refreshTimer: Timer?

    /// 接続中のアダプタのみを返す
    var connectedAdapters: [NetworkAdapter] {
        adapters.filter { $0.status == .connected }
    }

    init() {
        Task {
            await fetchAdapters()
        }
    }

    /// 全アダプタの情報を取得
    func fetchAdapters() async {
        isLoading = true
        error = nil

        do {
            let services = try await networkSetupCommand.listAllNetworkServices()
            let serviceOrder = try await networkSetupCommand.listNetworkServiceOrder()

            var newAdapters: [NetworkAdapter] = []

            for service in services {
                // サービス名からデバイスIDを取得
                let serviceInfo = serviceOrder.first { $0.service == service }
                let deviceId = serviceInfo?.device ?? ""

                // IP設定を取得
                let ipConfig = try? await networkSetupCommand.getInfo(for: service)

                // MACアドレスを取得
                let macAddress = try? await networkSetupCommand.getMACAddress(for: deviceId)

                // 接続状態を判定（ifconfigのstatus: activeを確認）
                let isLinkActive = (try? await networkSetupCommand.getInterfaceStatus(for: deviceId)) ?? false
                let status: ConnectionStatus = isLinkActive ? .connected : .disconnected

                let adapter = NetworkAdapter(
                    id: deviceId.isEmpty ? service : deviceId,
                    hardwarePort: service,
                    displayName: service,
                    macAddress: macAddress,
                    type: AdapterType.from(hardwarePort: service),
                    status: status,
                    ipConfiguration: ipConfig
                )
                newAdapters.append(adapter)
            }

            self.adapters = newAdapters
        } catch let networkError as NetworkError {
            self.error = networkError
        } catch {
            self.error = .commandExecutionFailed(error.localizedDescription)
        }

        isLoading = false
    }

    /// 外部IPアドレスを取得
    func fetchExternalIP() async {
        guard let url = URL(string: "https://api.ipify.org") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let ip = String(data: data, encoding: .utf8) {
                self.externalIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            self.externalIP = nil
        }
    }

    /// IP設定を変更（管理者権限が必要）
    func applyConfiguration(_ config: IPConfiguration, to serviceName: String) async throws {
        if config.configureIPv4 == .dhcp {
            try await networkSetupCommand.setDHCP(service: serviceName)
        } else if config.configureIPv4 == .manual {
            guard let ip = config.ipv4Address,
                  let subnet = config.subnetMask,
                  let router = config.router else {
                throw NetworkError.invalidIPAddress("IP設定が不完全です")
            }
            try await networkSetupCommand.setManualIP(
                service: serviceName,
                ip: ip,
                subnet: subnet,
                router: router
            )
        }

        // DNS設定
        if !config.dnsServers.isEmpty {
            try await networkSetupCommand.setDNSServers(
                service: serviceName,
                servers: config.dnsServers
            )
        }

        // 設定を再読み込み
        await fetchAdapters()
    }

    /// DHCPに切り替え
    func switchToDHCP(serviceName: String) async throws {
        try await networkSetupCommand.setDHCP(service: serviceName)
        await fetchAdapters()
    }

    /// 定期更新を開始
    func startAutoRefresh(interval: TimeInterval) {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchAdapters()
            }
        }
    }

    /// 定期更新を停止
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// IPアドレスが有効かどうかを判定
    private func isValidIPAddress(_ ip: String?) -> Bool {
        guard let ip = ip, !ip.isEmpty else { return false }
        // 無効なIPアドレスを除外
        let invalidIPs = ["0.0.0.0", "none", ""]
        if invalidIPs.contains(ip.lowercased()) { return false }
        // 基本的なIPv4形式チェック
        let parts = ip.split(separator: ".")
        return parts.count == 4
    }
}
