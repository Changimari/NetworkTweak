import SwiftUI

/// ネットワークスキャン画面
/// 選択したアダプタと同じセグメント（/24）の .1〜.254 をスキャンして一覧表示する
struct NetworkScanView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @ObservedObject var scanner: NetworkScanner
    @State private var selectedAdapterID: String?

    /// IPv4を持つスキャン可能なアダプタ
    private var scannableAdapters: [NetworkAdapter] {
        appState.networkManager.adapters.filter { adapter in
            let ip = adapter.ipConfiguration?.ipv4Address ?? ""
            return ip.split(separator: ".").count == 4 && !ip.hasPrefix("169.254")
        }
    }

    private var selectedAdapter: NetworkAdapter? {
        scannableAdapters.first { $0.id == selectedAdapterID } ?? scannableAdapters.first
    }

    private var localIP: String? {
        selectedAdapter?.ipConfiguration?.ipv4Address
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controlBar
            Divider()
            resultsTable
            Divider()
            footer
        }
        .frame(width: 660, height: 520)
        .onAppear {
            if selectedAdapterID == nil {
                selectedAdapterID = scannableAdapters.first?.id
            }
        }
    }

    // MARK: - ヘッダー

    private var header: some View {
        HStack {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text("ネットワークスキャン")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - コントロールバー

    private var controlBar: some View {
        HStack(spacing: 12) {
            // アダプタ選択
            Picker("アダプタ", selection: Binding(
                get: { selectedAdapterID ?? scannableAdapters.first?.id ?? "" },
                set: { selectedAdapterID = $0 }
            )) {
                ForEach(scannableAdapters) { adapter in
                    Text("\(adapter.displayName) (\(adapter.ipConfiguration?.ipv4Address ?? ""))")
                        .tag(adapter.id)
                }
            }
            .frame(maxWidth: 280)
            .disabled(scanner.isScanning)

            Spacer()

            if let ip = localIP {
                let base = baseNetwork(from: ip)
                Text("\(base).1 〜 \(base).254")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button {
                guard let ip = localIP else { return }
                Task { await scanner.scan(localIP: ip) }
            } label: {
                if scanner.isScanning {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6)
                        Text("\(scanner.scannedCount)/\(scanner.totalCount)")
                            .font(.caption)
                            .monospacedDigit()
                    }
                } else {
                    Label("スキャン開始", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(localIP == nil || scanner.isScanning)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - 結果テーブル

    private var resultsTable: some View {
        Group {
            if scanner.results.isEmpty && !scanner.isScanning {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "wifi")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("「スキャン開始」でセグメント内の機器を検索します")
                        .foregroundColor(.secondary)
                        .font(.callout)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                Table(scanner.results) {
                    TableColumn("") { row in
                        Circle()
                            .fill(row.isAlive ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                    }
                    .width(20)

                    TableColumn("IPアドレス") { row in
                        Text(row.ipAddress)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .width(min: 110, ideal: 120)

                    TableColumn("ホスト名") { row in
                        Text(row.hostname)
                            .textSelection(.enabled)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("MACアドレス") { row in
                        Text(row.macAddress)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 120, ideal: 140)

                    TableColumn("ベンダー") { row in
                        Text(row.vendor)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .width(min: 120, ideal: 160)
                }
            }
        }
    }

    // MARK: - フッター

    private var footer: some View {
        HStack {
            if !scanner.results.isEmpty {
                let aliveCount = scanner.results.filter { $0.isAlive }.count
                Text("\(scanner.results.count) 台検出（応答 \(aliveCount) 台）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !scanner.results.isEmpty {
                Button {
                    scanner.clear()
                } label: {
                    Label("クリア", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(scanner.isScanning)

                Button {
                    exportCSV()
                } label: {
                    Label("CSV", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - ヘルパー

    private func baseNetwork(from ip: String) -> String {
        let o = ip.split(separator: ".")
        guard o.count == 4 else { return ip }
        return "\(o[0]).\(o[1]).\(o[2])"
    }

    private func exportCSV() {
        var csv = "IPアドレス,ホスト名,MACアドレス,ベンダー,応答\n"
        for r in scanner.results {
            func esc(_ s: String) -> String { "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            csv += "\(esc(r.ipAddress)),\(esc(r.hostname)),\(esc(r.macAddress)),\(esc(r.vendor)),\(r.isAlive ? "○" : "×")\n"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "network-scan.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
