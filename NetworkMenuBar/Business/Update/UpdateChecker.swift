import Foundation
import AppKit

/// GitHub Releaseの情報
struct GitHubRelease: Codable {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    let assets: [GitHubAsset]
    let publishedAt: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case assets
        case publishedAt = "published_at"
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

/// アップデート情報
struct UpdateInfo {
    let currentVersion: String
    let latestVersion: String
    let releaseNotes: String
    let downloadUrl: String
    let releasePageUrl: String
    let isUpdateAvailable: Bool
}

/// アップデートチェッカー
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var updateInfo: UpdateInfo?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var error: String?

    private let githubRepo = "Changimari/NetworkTweak"
    private let userDefaultsKey = "lastUpdateCheck"

    /// 現在のアプリバージョン
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private init() {
        lastCheckDate = UserDefaults.standard.object(forKey: userDefaultsKey) as? Date
    }

    /// アップデートを確認
    func checkForUpdates() async {
        guard !isChecking else { return }

        isChecking = true
        error = nil

        defer {
            isChecking = false
            lastCheckDate = Date()
            UserDefaults.standard.set(lastCheckDate, forKey: userDefaultsKey)
        }

        do {
            let release = try await fetchLatestRelease()
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")

            // DMGアセットを探す
            let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
            let downloadUrl = dmgAsset?.browserDownloadUrl ?? release.htmlUrl

            let isUpdateAvailable = compareVersions(current: currentVersion, latest: latestVersion) == .orderedAscending

            updateInfo = UpdateInfo(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                releaseNotes: release.body,
                downloadUrl: downloadUrl,
                releasePageUrl: release.htmlUrl,
                isUpdateAvailable: isUpdateAvailable
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 最新リリースを取得
    private func fetchLatestRelease() async throws -> GitHubRelease {
        let urlString = "https://api.github.com/repos/\(githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noReleasesFound
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// バージョン比較
    private func compareVersions(current: String, latest: String) -> ComparisonResult {
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(currentParts.count, latestParts.count)

        for i in 0..<maxLength {
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            let latestPart = i < latestParts.count ? latestParts[i] : 0

            if currentPart < latestPart {
                return .orderedAscending
            } else if currentPart > latestPart {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    /// ダウンロードページを開く
    func openDownloadPage() {
        guard let urlString = updateInfo?.downloadUrl ?? updateInfo?.releasePageUrl,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// リリースページを開く
    func openReleasePage() {
        guard let urlString = updateInfo?.releasePageUrl,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// GitHubリポジトリページを開く
    func openRepositoryPage() {
        guard let url = URL(string: "https://github.com/\(githubRepo)") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum UpdateError: LocalizedError {
    case noReleasesFound
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .noReleasesFound:
            return "リリースが見つかりませんでした"
        case .serverError(let code):
            return "サーバーエラー: \(code)"
        }
    }
}
