import Foundation

/// ネットワーク速度を監視するクラス
@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    @Published var downloadSpeed: Double = 0  // bytes per second
    @Published var uploadSpeed: Double = 0    // bytes per second

    private var timer: Timer?
    private var previousBytesReceived: UInt64 = 0
    private var previousBytesSent: UInt64 = 0
    private var previousTimestamp: Date?

    /// 監視を開始
    func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()

        // 初期値を取得
        let stats = getNetworkStats()
        previousBytesReceived = stats.bytesReceived
        previousBytesSent = stats.bytesSent
        previousTimestamp = Date()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSpeed()
            }
        }
    }

    /// 監視を停止
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        downloadSpeed = 0
        uploadSpeed = 0
    }

    /// 速度を更新
    private func updateSpeed() {
        let currentStats = getNetworkStats()
        let currentTime = Date()

        guard let previousTime = previousTimestamp else {
            previousBytesReceived = currentStats.bytesReceived
            previousBytesSent = currentStats.bytesSent
            previousTimestamp = currentTime
            return
        }

        let timeInterval = currentTime.timeIntervalSince(previousTime)
        guard timeInterval > 0 else { return }

        // ダウンロード速度（bytes/sec）
        if currentStats.bytesReceived >= previousBytesReceived {
            let bytesReceived = currentStats.bytesReceived - previousBytesReceived
            downloadSpeed = Double(bytesReceived) / timeInterval
        }

        // アップロード速度（bytes/sec）
        if currentStats.bytesSent >= previousBytesSent {
            let bytesSent = currentStats.bytesSent - previousBytesSent
            uploadSpeed = Double(bytesSent) / timeInterval
        }

        previousBytesReceived = currentStats.bytesReceived
        previousBytesSent = currentStats.bytesSent
        previousTimestamp = currentTime
    }

    /// ネットワーク統計を取得
    private func getNetworkStats() -> (bytesReceived: UInt64, bytesSent: UInt64) {
        var bytesReceived: UInt64 = 0
        var bytesSent: UInt64 = 0

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return (0, 0)
        }

        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee

            // AF_LINKのインターフェースのみ（ネットワークデータリンク層）
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: interface.ifa_name)
                // en*, bridge* などの物理インターフェースのみ
                if name.hasPrefix("en") || name.hasPrefix("bridge") {
                    if let data = interface.ifa_data {
                        let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                        bytesReceived += UInt64(networkData.ifi_ibytes)
                        bytesSent += UInt64(networkData.ifi_obytes)
                    }
                }
            }

            guard let next = interface.ifa_next else { break }
            ptr = next
        }

        return (bytesReceived, bytesSent)
    }

    /// 速度を人間が読める形式にフォーマット
    nonisolated static func formatSpeed(_ bytesPerSecond: Double, unit: SpeedUnit = .adaptive) -> String {
        switch unit {
        case .bitsPerSecond:
            return formatBits(bytesPerSecond * 8)
        case .bytesPerSecond:
            return formatBytes(bytesPerSecond)
        case .adaptive:
            return formatBytes(bytesPerSecond)
        }
    }

    nonisolated private static func formatBytes(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond < 1024 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else if bytesPerSecond < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1024)
        } else if bytesPerSecond < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSecond / (1024 * 1024))
        } else {
            return String(format: "%.1f GB/s", bytesPerSecond / (1024 * 1024 * 1024))
        }
    }

    nonisolated private static func formatBits(_ bitsPerSecond: Double) -> String {
        if bitsPerSecond < 1000 {
            return String(format: "%.0f bps", bitsPerSecond)
        } else if bitsPerSecond < 1000 * 1000 {
            return String(format: "%.1f Kbps", bitsPerSecond / 1000)
        } else if bitsPerSecond < 1000 * 1000 * 1000 {
            return String(format: "%.1f Mbps", bitsPerSecond / (1000 * 1000))
        } else {
            return String(format: "%.1f Gbps", bitsPerSecond / (1000 * 1000 * 1000))
        }
    }
}
