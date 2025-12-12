import Foundation

/// networksetupコマンドのSwiftラッパー
final class NetworkSetupCommand {

    // MARK: - Query Commands

    /// 全ネットワークサービスを取得
    func listAllNetworkServices() async throws -> [String] {
        let output = try await runCommand(["-listallnetworkservices"])
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.contains("*") && !$0.starts(with: "An asterisk") }
        return lines
    }

    /// ハードウェアポートを取得
    func listHardwarePorts() async throws -> [(port: String, device: String)] {
        let output = try await runCommand(["-listallhardwareports"])
        var results: [(port: String, device: String)] = []

        let lines = output.components(separatedBy: .newlines)
        var currentPort: String?

        for line in lines {
            if line.starts(with: "Hardware Port:") {
                currentPort = line.replacingOccurrences(of: "Hardware Port: ", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.starts(with: "Device:"), let port = currentPort {
                let device = line.replacingOccurrences(of: "Device: ", with: "").trimmingCharacters(in: .whitespaces)
                results.append((port: port, device: device))
                currentPort = nil
            }
        }

        return results
    }

    /// サービス名とデバイスIDのマッピングを取得
    func listNetworkServiceOrder() async throws -> [(service: String, device: String)] {
        let output = try await runCommand(["-listnetworkserviceorder"])
        var results: [(service: String, device: String)] = []

        let lines = output.components(separatedBy: .newlines)
        var currentService: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // (1) Service Name 形式の行
            if let match = trimmed.range(of: #"^\(\d+\)\s+(.+)$"#, options: .regularExpression) {
                let servicePart = trimmed[match]
                // 番号を除去してサービス名を取得
                if let spaceIndex = servicePart.firstIndex(of: " ") {
                    currentService = String(servicePart[servicePart.index(after: spaceIndex)...])
                }
            }
            // (Hardware Port: ..., Device: en0) 形式の行
            else if trimmed.starts(with: "(Hardware Port:"), let service = currentService {
                if let deviceRange = trimmed.range(of: "Device: ") {
                    let afterDevice = trimmed[deviceRange.upperBound...]
                    if let endParen = afterDevice.firstIndex(of: ")") {
                        let device = String(afterDevice[..<endParen])
                        results.append((service: service, device: device))
                    }
                }
                currentService = nil
            }
        }

        return results
    }

    /// 特定サービスのIP情報を取得
    func getInfo(for service: String) async throws -> IPConfiguration {
        let output = try await runCommand(["-getinfo", service])
        return parseIPConfiguration(from: output)
    }

    /// DNSサーバーを取得
    func getDNSServers(for service: String) async throws -> [String] {
        let output = try await runCommand(["-getdnsservers", service])
        if output.contains("There aren't any DNS Servers") {
            return []
        }
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    /// MACアドレスを取得
    func getMACAddress(for device: String) async throws -> String? {
        guard !device.isEmpty else { return nil }
        let output = try await runCommand(["-getmacaddress", device])
        // 出力例: "Ethernet Address: 00:11:22:33:44:55 (Hardware Port: Wi-Fi)"
        if let range = output.range(of: "Ethernet Address: ") {
            let afterAddress = output[range.upperBound...]
            if let spaceIndex = afterAddress.firstIndex(of: " ") {
                return String(afterAddress[..<spaceIndex])
            } else if let newlineIndex = afterAddress.firstIndex(of: "\n") {
                return String(afterAddress[..<newlineIndex])
            }
        }
        return nil
    }

    /// インターフェースのリンク状態を取得（ifconfigを使用）
    func getInterfaceStatus(for device: String) async throws -> Bool {
        guard !device.isEmpty else { return false }
        let output = try await runIfconfig([device])
        // ifconfigの出力から "status: active" を探す
        // status: active = 接続中、status: inactive = 未接続
        return output.contains("status: active")
    }

    /// ifconfigコマンドを実行
    private func runIfconfig(_ arguments: [String]) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw NetworkError.commandExecutionFailed("ifconfig出力の読み取りに失敗しました")
        }

        return output
    }

    // MARK: - Configuration Commands (要管理者権限)

    /// DHCPに設定
    func setDHCP(service: String) async throws {
        try await runCommandWithPrivileges(["-setdhcp", service])
    }

    /// 固定IPを設定
    func setManualIP(service: String, ip: String, subnet: String, router: String) async throws {
        try await runCommandWithPrivileges(["-setmanual", service, ip, subnet, router])
    }

    /// DNSサーバーを設定
    func setDNSServers(service: String, servers: [String]) async throws {
        if servers.isEmpty {
            try await runCommandWithPrivileges(["-setdnsservers", service, "Empty"])
        } else {
            try await runCommandWithPrivileges(["-setdnsservers", service] + servers)
        }
    }

    // MARK: - Private Methods

    /// コマンドを実行
    private func runCommand(_ arguments: [String]) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw NetworkError.commandExecutionFailed("コマンド出力の読み取りに失敗しました")
        }

        if process.terminationStatus != 0 {
            throw NetworkError.commandExecutionFailed(output)
        }

        return output
    }

    /// 管理者権限でコマンドを実行
    private func runCommandWithPrivileges(_ arguments: [String]) async throws {
        // sudoers設定が完了している場合はsudoを使用
        if PrivilegeManager.shared.isSetupCompleted {
            try await runCommandWithSudo(arguments)
        } else {
            try await runCommandWithAppleScript(arguments)
        }
    }

    /// sudoでコマンドを実行（パスワード不要）
    private func runCommandWithSudo(_ arguments: [String]) async throws {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["/usr/sbin/networksetup"] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "不明なエラー"
            throw NetworkError.commandExecutionFailed(output)
        }
    }

    /// AppleScriptで管理者権限を取得してコマンドを実行
    private func runCommandWithAppleScript(_ arguments: [String]) async throws {
        // 引数をエスケープ（スペースを含む引数のためにシングルクォートで囲む）
        let escapedArgs = arguments.map { arg -> String in
            // シングルクォート内のシングルクォートをエスケープ
            let escaped = arg.replacingOccurrences(of: "'", with: "'\\''")
            return "'\(escaped)'"
        }.joined(separator: " ")

        let command = "/usr/sbin/networksetup \(escapedArgs)"

        let script = "do shell script \"\(command)\" with administrator privileges"

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            scriptObject.executeAndReturnError(&error)
            if let error = error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "不明なエラー"
                throw NetworkError.commandExecutionFailed(message)
            }
        } else {
            throw NetworkError.commandExecutionFailed("AppleScriptの作成に失敗しました")
        }
    }

    /// IP設定をパース
    private func parseIPConfiguration(from output: String) -> IPConfiguration {
        var config = IPConfiguration()

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: ": ")
            guard parts.count >= 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "IP address":
                config.ipv4Address = value
            case "Subnet mask":
                config.subnetMask = value
            case "Router":
                config.router = value
            case "IPv6 IP address":
                config.ipv6Address = value
            default:
                break
            }
        }

        // DHCPかManualかを判定
        if output.contains("DHCP Configuration") {
            config.configureIPv4 = .dhcp
        } else if output.contains("Manually Using") {
            config.configureIPv4 = .manual
        }

        return config
    }
}
