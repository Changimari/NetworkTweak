import Foundation

/// スキャン結果の1エントリ
struct ScanResult: Identifiable {
    var id: String { ipAddress }
    let ipAddress: String
    var macAddress: String
    var hostname: String
    var vendor: String
    var isAlive: Bool         // pingに応答したか

    /// IPを数値化（ソート用）
    var ipNumeric: UInt32 {
        let parts = ipAddress.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4 else { return 0 }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }
}

/// 同一セグメント（/24）をスキャンして生存ホストを列挙する
@MainActor
final class NetworkScanner: ObservableObject {
    @Published private(set) var results: [ScanResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0
    @Published private(set) var totalCount = 254
    @Published private(set) var baseNetwork = ""   // 例: "192.168.0"

    private let pingConcurrency = 64

    /// 結果をクリア
    func clear() {
        guard !isScanning else { return }
        results = []
        scannedCount = 0
        baseNetwork = ""
    }

    /// スキャン開始
    /// - Parameter localIP: スキャン基準となるアダプタのIPv4アドレス
    func scan(localIP: String) async {
        guard !isScanning else { return }
        let octets = localIP.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return }
        let base = "\(octets[0]).\(octets[1]).\(octets[2])"

        isScanning = true
        results = []
        scannedCount = 0
        baseNetwork = base

        let targets = (1...254).map { "\(base).\($0)" }
        totalCount = targets.count

        // Phase 1: ping掃引（ARPキャッシュも埋まる）
        let alive = await pingSweep(targets)

        // Phase 2: ARPテーブルからMAC取得
        let arpMap = await Self.readARPTable()

        // 生存ホスト or ARPに載っているホストを対象に
        var candidates = Set(alive)
        for ip in arpMap.keys where ip.hasPrefix(base + ".") {
            candidates.insert(ip)
        }

        // Phase 3: ホスト名（逆引き）とベンダーを解決
        var rows: [ScanResult] = []
        await withTaskGroup(of: ScanResult.self) { group in
            for ip in candidates {
                let mac = arpMap[ip] ?? ""
                let isAlive = alive.contains(ip)
                group.addTask {
                    let hostname = await Self.reverseDNS(ip) ?? ""
                    let vendor = mac.isEmpty ? "" : (OUILookup.shared.vendor(for: mac) ?? "")
                    return ScanResult(
                        ipAddress: ip,
                        macAddress: mac,
                        hostname: hostname,
                        vendor: vendor,
                        isAlive: isAlive
                    )
                }
            }
            for await row in group {
                rows.append(row)
            }
        }

        rows.sort { $0.ipNumeric < $1.ipNumeric }
        results = rows
        isScanning = false
    }

    // MARK: - Ping掃引

    private func pingSweep(_ targets: [String]) async -> Set<String> {
        var alive = Set<String>()
        var index = 0

        while index < targets.count {
            let chunk = Array(targets[index..<min(index + pingConcurrency, targets.count)])
            let chunkAlive = await withTaskGroup(of: (String, Bool).self) { group -> [String] in
                for ip in chunk {
                    group.addTask { (ip, await Self.ping(ip)) }
                }
                var found: [String] = []
                for await (ip, ok) in group where ok {
                    found.append(ip)
                }
                return found
            }
            alive.formUnion(chunkAlive)
            index += chunk.count
            scannedCount = index
        }
        return alive
    }

    // MARK: - 低レベルユーティリティ（バックグラウンド実行）

    /// 1回pingして応答があればtrue
    nonisolated private static func ping(_ ip: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-W", "500", "-t", "1", ip]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// ARPテーブルを読み取り IP→MAC のマップを返す
    nonisolated private static func readARPTable() async -> [String: String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                process.arguments = ["-a", "-n"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: [:])
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                var map: [String: String] = [:]

                // 例: "? (192.168.0.1) at 40:ae:30:3:8e:7e on en0 ifscope [ethernet]"
                for line in output.split(separator: "\n") {
                    let s = String(line)
                    guard let ipStart = s.range(of: "("),
                          let ipEnd = s.range(of: ")", range: ipStart.upperBound..<s.endIndex) else { continue }
                    let ip = String(s[ipStart.upperBound..<ipEnd.lowerBound])

                    guard let atRange = s.range(of: " at "),
                          let onRange = s.range(of: " on ", range: atRange.upperBound..<s.endIndex) else { continue }
                    let rawMac = String(s[atRange.upperBound..<onRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    guard rawMac.contains(":"), rawMac != "(incomplete)" else { continue }

                    map[ip] = normalizeMAC(rawMac)
                }
                continuation.resume(returning: map)
            }
        }
    }

    /// MACをゼロ埋め・小文字に正規化（arpは "3:8e" のように短縮するため）
    nonisolated private static func normalizeMAC(_ mac: String) -> String {
        mac.split(separator: ":")
            .map { $0.count == 1 ? "0\($0)" : String($0) }
            .joined(separator: ":")
            .lowercased()
    }

    /// IPアドレスからホスト名を解決する
    /// LAN内の機器はユニキャストDNSでは引けないため、まずmDNS（Bonjour）を試し、
    /// ダメならユニキャストDNSの逆引きにフォールバックする
    nonisolated private static func reverseDNS(_ ip: String) async -> String? {
        if let mdns = await mDNSReverse(ip) {
            return mdns
        }
        return await unicastReverse(ip)
    }

    /// mDNS（Bonjour）でIPを逆引き。digで 224.0.0.251:5353 に問い合わせる
    nonisolated private static func mDNSReverse(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/dig")
                process.arguments = ["+short", "+time=1", "+tries=1", "-p", "5353", "@224.0.0.251", "-x", ip]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                // タイムアウト時は ";; connection timed out..." がstdoutに出るので弾く。
                // 妥当なホスト名の行だけを採用する。
                let validLine = output.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { line in
                        !line.isEmpty
                            && !line.hasPrefix(";")
                            && !line.contains(" ")   // エラー文言はスペースを含む
                    }
                guard var name = validLine else {
                    continuation.resume(returning: nil)
                    return
                }
                if name.hasSuffix(".") { name.removeLast() }
                if name.hasSuffix(".local") { name.removeLast(6) }
                continuation.resume(returning: name.isEmpty ? nil : name)
            }
        }
    }

    /// ユニキャストDNSの逆引き（getnameinfo）
    nonisolated private static func unicastReverse(_ ip: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_addr.s_addr = inet_addr(ip)

                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let ret = withUnsafePointer(to: &addr) { ptr -> Int32 in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                        getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &host, socklen_t(host.count),
                                    nil, 0, NI_NAMEREQD)
                    }
                }
                if ret == 0 {
                    let name = String(cString: host)
                    continuation.resume(returning: (name.isEmpty || name == ip) ? nil : name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
