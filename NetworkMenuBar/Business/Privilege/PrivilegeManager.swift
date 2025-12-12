import Foundation

/// 管理者権限の設定を管理するクラス
final class PrivilegeManager {
    static let shared = PrivilegeManager()

    private let sudoersFilePath = "/etc/sudoers.d/NetworkMenuBar"
    private let setupCompletedKey = "PrivilegeSetupCompleted"

    private init() {}

    /// 権限設定が完了しているかどうか
    var isSetupCompleted: Bool {
        // sudoersファイルが存在するかチェック
        return FileManager.default.fileExists(atPath: sudoersFilePath)
    }

    /// 初回セットアップを実行（管理者パスワードを一度だけ要求）
    func performInitialSetup() async throws {
        guard !isSetupCompleted else { return }

        let username = NSUserName()
        let sudoersContent = "\(username) ALL=(ALL) NOPASSWD: /usr/sbin/networksetup"

        // AppleScriptで管理者権限を取得してsudoersファイルを作成
        let script = """
        do shell script "echo '\(sudoersContent)' > \(sudoersFilePath) && chmod 440 \(sudoersFilePath)" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "権限設定に失敗しました"
                throw PrivilegeError.setupFailed(message)
            }
        } else {
            throw PrivilegeError.setupFailed("AppleScriptの作成に失敗しました")
        }
    }

    /// 権限設定を削除
    func removeSetup() async throws {
        guard isSetupCompleted else { return }

        let script = """
        do shell script "rm -f \(sudoersFilePath)" with administrator privileges
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "権限削除に失敗しました"
                throw PrivilegeError.setupFailed(message)
            }
        }
    }
}

enum PrivilegeError: LocalizedError {
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .setupFailed(let message):
            return message
        }
    }
}
