import Foundation

/// ネットワークアダプタを表すモデル
struct NetworkAdapter: Identifiable, Hashable {
    let id: String                      // "en0", "en1" など
    let hardwarePort: String            // "Wi-Fi", "Ethernet" など
    let displayName: String             // ユーザー向け表示名
    let macAddress: String?             // MACアドレス
    let type: AdapterType               // アダプタ種別
    var status: ConnectionStatus        // 接続状態
    var ipConfiguration: IPConfiguration? // IP設定

    // Hashable準拠（idのみで比較）
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: NetworkAdapter, rhs: NetworkAdapter) -> Bool {
        lhs.id == rhs.id
    }

    /// アダプタに対応するSF Symbolアイコン名
    var iconName: String {
        switch type {
        case .wifi:
            return status == .connected ? "wifi" : "wifi.slash"
        case .ethernet, .thunderbolt, .usb:
            return status == .connected ? "cable.connector" : "cable.connector.slash"
        case .vpn:
            return "lock.shield"
        case .other:
            return "network"
        }
    }
}

/// アダプタ種別
enum AdapterType: String, CaseIterable {
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
    case thunderbolt = "Thunderbolt Bridge"
    case usb = "USB Ethernet"
    case vpn = "VPN"
    case other = "Other"

    /// ハードウェアポート名からアダプタ種別を判定
    static func from(hardwarePort: String) -> AdapterType {
        let lowercased = hardwarePort.lowercased()
        if lowercased.contains("wi-fi") || lowercased.contains("wifi") {
            return .wifi
        } else if lowercased.contains("ethernet") {
            return .ethernet
        } else if lowercased.contains("thunderbolt") {
            return .thunderbolt
        } else if lowercased.contains("usb") {
            return .usb
        } else if lowercased.contains("vpn") {
            return .vpn
        } else {
            return .other
        }
    }
}

/// 接続状態
enum ConnectionStatus: String {
    case connected = "Connected"
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .connected: return "接続中"
        case .disconnected: return "未接続"
        case .connecting: return "接続中..."
        case .unknown: return "不明"
        }
    }

    var color: String {
        switch self {
        case .connected: return "green"
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .unknown: return "gray"
        }
    }
}
