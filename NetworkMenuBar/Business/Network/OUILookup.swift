import Foundation

/// MACアドレスの先頭3オクテット（OUI）からベンダー名を引くユーティリティ
/// IEEE公式のOUIデータベース（Resources/oui.tsv）を使用する
final class OUILookup {
    static let shared = OUILookup()

    private var table: [String: String] = [:]
    private var loaded = false
    private let lock = NSLock()

    private init() {}

    /// MACアドレスからベンダー名を取得（不明ならnil）
    func vendor(for mac: String) -> String? {
        loadIfNeeded()

        // "80:b9:89:dd:2d:7b" → "80B989"
        let hex = mac
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        guard hex.count >= 6 else { return nil }
        let oui = String(hex.prefix(6))
        return table[oui]
    }

    private func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true

        guard let url = Bundle.main.url(forResource: "oui", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        for line in content.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            table[String(parts[0])] = String(parts[1])
        }
    }
}
