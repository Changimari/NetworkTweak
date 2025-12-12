import Foundation

/// ネットワーク関連のエラー
enum NetworkError: LocalizedError {
    case adapterNotFound(String)
    case configurationFailed(String)
    case authorizationFailed
    case authorizationDenied
    case commandExecutionFailed(String)
    case invalidIPAddress(String)
    case invalidSubnetMask(String)
    case networkServiceNotFound(String)
    case profileNotFound(UUID)
    case profileSaveFailed
    case externalIPFetchFailed

    var errorDescription: String? {
        switch self {
        case .adapterNotFound(let id):
            return "ネットワークアダプタが見つかりません: \(id)"
        case .configurationFailed(let message):
            return "設定の変更に失敗しました: \(message)"
        case .authorizationFailed:
            return "管理者権限の取得に失敗しました"
        case .authorizationDenied:
            return "管理者権限が拒否されました"
        case .commandExecutionFailed(let message):
            return "コマンドの実行に失敗しました: \(message)"
        case .invalidIPAddress(let address):
            return "無効なIPアドレスです: \(address)"
        case .invalidSubnetMask(let mask):
            return "無効なサブネットマスクです: \(mask)"
        case .networkServiceNotFound(let service):
            return "ネットワークサービスが見つかりません: \(service)"
        case .profileNotFound(let id):
            return "プロファイルが見つかりません: \(id)"
        case .profileSaveFailed:
            return "プロファイルの保存に失敗しました"
        case .externalIPFetchFailed:
            return "外部IPアドレスの取得に失敗しました"
        }
    }
}
