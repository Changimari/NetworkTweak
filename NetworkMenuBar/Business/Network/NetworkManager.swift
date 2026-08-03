import Foundation
import Combine

/// 設定バックアップ用の構造体
struct NetworkConfigBackup: Codable {
    let serviceName: String
    let config: IPConfiguration
    let dnsServers: [String]
    let timestamp: Date
}

/// ネットワーク情報を管理するクラス
@MainActor
final class NetworkManager: ObservableObject {
    @Published private(set) var adapters: [NetworkAdapter] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: NetworkError?
    @Published private(set) var externalIP: String?

    private let networkSetupCommand = NetworkSetupCommand()
    private var refreshTimer: Timer?

    /// 設定バックアップ（サービス名をキーとして保存）
    private var configBackups: [String: NetworkConfigBackup] = [:]

    /// このアプリから無効化したサービス名
    @Published private(set) var disabledByApp: Set<String> = []

    /// ユーザーが最後にIP設定を適用した時刻
    /// 適用直後のWi-Fiリンクのゆらぎを「AP切り替え」と誤認して自動リセットしないための抑制に使う
    private(set) var lastUserApply: Date = .distantPast

    /// 接続中のアダプタのみを返す
    var connectedAdapters: [NetworkAdapter] {
        adapters.filter { $0.status == .connected }
    }

    /// このアプリから無効化されたアダプタのみを返す
    var disabledAdapters: [NetworkAdapter] {
        adapters.filter { $0.status == .disabled && disabledByApp.contains($0.hardwarePort) }
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
                let serviceInfo = serviceOrder.first { $0.service == service.name }
                let deviceId = serviceInfo?.device ?? ""

                // 無効化されたサービスの場合
                if service.isDisabled {
                    let macAddress = try? await networkSetupCommand.getMACAddress(for: deviceId)
                    let adapter = NetworkAdapter(
                        id: deviceId.isEmpty ? service.name : deviceId,
                        hardwarePort: service.name,
                        displayName: service.name,
                        macAddress: macAddress,
                        type: AdapterType.from(hardwarePort: service.name),
                        status: .disabled,
                        ipConfiguration: nil
                    )
                    newAdapters.append(adapter)
                    continue
                }

                // IP設定を取得
                let ipConfig = try? await networkSetupCommand.getInfo(for: service.name)

                // MACアドレスを取得
                let macAddress = try? await networkSetupCommand.getMACAddress(for: deviceId)

                // 接続状態を判定（ifconfigのstatus: activeを確認）
                let isLinkActive = (try? await networkSetupCommand.getInterfaceStatus(for: deviceId)) ?? false
                let status: ConnectionStatus = isLinkActive ? .connected : .disconnected

                let adapter = NetworkAdapter(
                    id: deviceId.isEmpty ? service.name : deviceId,
                    hardwarePort: service.name,
                    displayName: service.name,
                    macAddress: macAddress,
                    type: AdapterType.from(hardwarePort: service.name),
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

    /// ネットワークサービスを有効化（オフから復帰）
    func enableService(serviceName: String) async throws {
        try await networkSetupCommand.setNetworkServiceEnabled(service: serviceName, enabled: true)
        // 有効化後はDHCPで復帰
        try await networkSetupCommand.setDHCP(service: serviceName)
        try await networkSetupCommand.setDNSServers(service: serviceName, servers: [])
        disabledByApp.remove(serviceName)
        await fetchAdapters()
    }

    /// IP設定を変更（管理者権限が必要）
    /// - Parameters:
    ///   - config: 適用するIP設定
    ///   - serviceName: ネットワークサービス名
    ///   - deviceId: デバイスID（en0, en1等）。ゲートウェイなし設定時にifconfigで使用
    func applyConfiguration(_ config: IPConfiguration, to serviceName: String, deviceId: String? = nil) async throws {
        // ユーザー適用の時刻を記録（この直後の自動リセットを抑制するため）
        lastUserApply = Date()

        // 変更前の設定をバックアップ
        await backupCurrentConfig(for: serviceName)

        if config.configureIPv4 == .off {
            // ネットワークサービスを無効化
            try await networkSetupCommand.setNetworkServiceEnabled(service: serviceName, enabled: false)
            disabledByApp.insert(serviceName)
        } else if config.configureIPv4 == .dhcp {
            // DHCPに設定
            try await networkSetupCommand.setDHCP(service: serviceName)
            // DHCPの場合、DNSもDHCPから取得するようにリセット
            try await networkSetupCommand.setDNSServers(service: serviceName, servers: [])
        } else if config.configureIPv4 == .manual {
            guard let ip = config.ipv4Address,
                  let subnet = config.subnetMask else {
                throw NetworkError.invalidIPAddress("IPアドレスとサブネットマスクは必須です")
            }

            let routerValue = config.router ?? ""
            let hasRouter = !routerValue.isEmpty

            if hasRouter {
                // ゲートウェイあり: networksetupで設定（デフォルトルートも設定される）
                try await networkSetupCommand.setManualIP(
                    service: serviceName,
                    ip: ip,
                    subnet: subnet,
                    router: routerValue
                )
            } else {
                // ゲートウェイなし: networksetupで空ルーター指定
                // デフォルトルートを張らない = 他アダプタのネット接続を壊さない
                try await networkSetupCommand.setManualIPWithoutRouter(
                    service: serviceName,
                    ip: ip,
                    subnet: subnet
                )
            }

            // DNS設定
            if !config.dnsServers.isEmpty {
                try await networkSetupCommand.setDNSServers(
                    service: serviceName,
                    servers: config.dnsServers
                )
            } else if hasRouter {
                // ゲートウェイありでDNS未指定の場合のみ公開DNSをフォールバック
                try await networkSetupCommand.setDNSServers(
                    service: serviceName,
                    servers: ["8.8.8.8", "1.1.1.1"]
                )
            }
            // ゲートウェイなしでDNS未指定の場合は何もしない（到達不可能なので）
        }

        // 設定を再読み込み
        await fetchAdapters()
    }

    /// DHCPに切り替え
    func switchToDHCP(serviceName: String) async throws {
        // 変更前の設定をバックアップ
        await backupCurrentConfig(for: serviceName)

        try await networkSetupCommand.setDHCP(service: serviceName)
        // DNSもDHCPから取得するようにリセット
        try await networkSetupCommand.setDNSServers(service: serviceName, servers: [])
        await fetchAdapters()
    }

    // MARK: - Backup & Restore

    /// 現在の設定をバックアップ
    private func backupCurrentConfig(for serviceName: String) async {
        do {
            let config = try await networkSetupCommand.getInfo(for: serviceName)
            let dnsServers = try await networkSetupCommand.getDNSServers(for: serviceName)

            let backup = NetworkConfigBackup(
                serviceName: serviceName,
                config: config,
                dnsServers: dnsServers,
                timestamp: Date()
            )
            configBackups[serviceName] = backup
        } catch {
            // バックアップ失敗はログに記録するのみ（設定変更は続行）
            print("Failed to backup config for \(serviceName): \(error)")
        }
    }

    /// バックアップがあるか確認
    func hasBackup(for serviceName: String) -> Bool {
        return configBackups[serviceName] != nil
    }

    /// バックアップから設定を復元
    func restoreFromBackup(serviceName: String) async throws {
        guard let backup = configBackups[serviceName] else {
            throw NetworkError.commandExecutionFailed("バックアップが見つかりません")
        }

        let config = backup.config

        if config.configureIPv4 == .dhcp {
            try await networkSetupCommand.setDHCP(service: serviceName)
            try await networkSetupCommand.setDNSServers(service: serviceName, servers: [])
        } else if config.configureIPv4 == .manual {
            if let ip = config.ipv4Address,
               let subnet = config.subnetMask,
               let router = config.router {
                try await networkSetupCommand.setManualIP(
                    service: serviceName,
                    ip: ip,
                    subnet: subnet,
                    router: router
                )
            }

            // バックアップしたDNS設定を復元
            if !backup.dnsServers.isEmpty {
                try await networkSetupCommand.setDNSServers(
                    service: serviceName,
                    servers: backup.dnsServers
                )
            }
        }

        // 復元後にバックアップを削除
        configBackups.removeValue(forKey: serviceName)

        await fetchAdapters()
    }

    /// 緊急リセット: DHCPに戻す
    func emergencyResetToDHCP(serviceName: String) async throws {
        try await networkSetupCommand.setDHCP(service: serviceName)
        try await networkSetupCommand.setDNSServers(service: serviceName, servers: [])
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
