import Foundation

/// IP設定を表すモデル
struct IPConfiguration: Codable, Equatable {
    var configureIPv4: IPv4ConfigMethod
    var ipv4Address: String?
    var subnetMask: String?
    var router: String?                 // デフォルトゲートウェイ
    var dnsServers: [String]

    // IPv6（オプション）
    var configureIPv6: IPv6ConfigMethod?
    var ipv6Address: String?
    var ipv6PrefixLength: Int?
    var ipv6Router: String?

    init(
        configureIPv4: IPv4ConfigMethod = .dhcp,
        ipv4Address: String? = nil,
        subnetMask: String? = nil,
        router: String? = nil,
        dnsServers: [String] = [],
        configureIPv6: IPv6ConfigMethod? = nil,
        ipv6Address: String? = nil,
        ipv6PrefixLength: Int? = nil,
        ipv6Router: String? = nil
    ) {
        self.configureIPv4 = configureIPv4
        self.ipv4Address = ipv4Address
        self.subnetMask = subnetMask
        self.router = router
        self.dnsServers = dnsServers
        self.configureIPv6 = configureIPv6
        self.ipv6Address = ipv6Address
        self.ipv6PrefixLength = ipv6PrefixLength
        self.ipv6Router = ipv6Router
    }
}

/// IPv4設定方法
enum IPv4ConfigMethod: String, Codable, CaseIterable {
    case dhcp = "DHCP"
    case manual = "Manual"
    case off = "Off"

    var displayName: String {
        switch self {
        case .dhcp: return "DHCP（自動）"
        case .manual: return "固定IP（手動）"
        case .off: return "オフ"
        }
    }
}

/// IPv6設定方法
enum IPv6ConfigMethod: String, Codable, CaseIterable {
    case automatic = "Automatic"
    case manual = "Manual"
    case linkLocal = "Link-local only"
    case off = "Off"

    var displayName: String {
        switch self {
        case .automatic: return "自動"
        case .manual: return "手動"
        case .linkLocal: return "リンクローカルのみ"
        case .off: return "オフ"
        }
    }
}
