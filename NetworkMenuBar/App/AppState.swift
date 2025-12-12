import Foundation
import SwiftUI
import Combine

/// アプリ全体の状態を管理するクラス
@MainActor
final class AppState: ObservableObject {
    @Published var networkManager: NetworkManager
    @Published var settings: AppSettings
    @Published var ipMemoStore: IPMemoStore

    private var cancellables = Set<AnyCancellable>()

    init() {
        self.networkManager = NetworkManager()
        self.settings = AppSettings.load()
        self.ipMemoStore = IPMemoStore()

        // IPMemoStoreの変更をAppStateに転送
        ipMemoStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func saveSettings() {
        settings.save()
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
