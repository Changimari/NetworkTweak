import SwiftUI
import Carbon

/// アダプタ詳細ビュー
struct AdapterDetailView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    let adapter: NetworkAdapter

    @State private var configMethod: IPv4ConfigMethod = .dhcp
    @State private var ipAddress: String = ""
    @State private var subnetMask: String = ""
    @State private var router: String = ""
    @State private var dnsServers: [String] = []
    @State private var newDNS: String = ""
    @State private var isApplying: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                    Text("戻る")
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(adapter.displayName)
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 接続状態
                    statusSection

                    Divider()

                    // IPv4設定
                    ipv4Section

                    Divider()

                    // DNS設定
                    dnsSection

                    Divider()

                    // 適用ボタン
                    applyButton
                }
                .padding()
            }
        }
        .frame(width: 320, height: 500)
        .onAppear {
            loadCurrentConfig()
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    /// 接続状態セクション
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(adapter.status == .connected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text("接続状態: \(adapter.status.displayName)")
            }

            if let mac = adapter.macAddress {
                HStack {
                    Text("MACアドレス:")
                        .foregroundColor(.secondary)
                    Text(mac)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
    }

    /// IPv4設定セクション
    private var ipv4Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IPv4設定")
                .font(.headline)

            Picker("設定方法", selection: $configMethod) {
                ForEach(IPv4ConfigMethod.allCases, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.segmented)
            // loadCurrentConfigで常に現在のIPをロード済みのため、
            // 手動切替時は自動でプリフィルされる（追加処理不要）

            if configMethod == .manual {
                VStack(alignment: .leading, spacing: 8) {
                    IPTextField(text: $ipAddress, placeholder: "IPアドレス")
                        .onChange(of: ipAddress) { _, newValue in
                            autoFillGateway(from: newValue)
                        }
                    IPTextField(text: $subnetMask, placeholder: "サブネットマスク")
                    IPTextField(text: $router, placeholder: "ルーター（空欄可 - 機器設定用）")

                    HStack {
                        if router.isEmpty {
                            Label("ゲートウェイ未設定：他のアダプタの通信に影響しません", systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            ipAddress = ""
                            subnetMask = "255.255.255.0"
                            router = ""
                        } label: {
                            Label("全クリア", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                    }
                }
            } else if configMethod == .dhcp {
                if let ip = adapter.ipConfiguration?.ipv4Address, !ip.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        infoRow("IPアドレス", value: ip)
                        if let subnet = adapter.ipConfiguration?.subnetMask, !subnet.isEmpty {
                            infoRow("サブネット", value: subnet)
                        }
                        if let gateway = adapter.ipConfiguration?.router,
                           !gateway.isEmpty && gateway != "(null)" {
                            infoRow("ルーター", value: gateway)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    /// DNS設定セクション
    private var dnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DNSサーバー")
                .font(.headline)

            // DNSプリセットボタン
            HStack(spacing: 8) {
                DNSPresetButton(
                    label: "Google",
                    icon: "g.circle.fill",
                    color: .blue
                ) {
                    dnsServers = ["8.8.8.8", "8.8.4.4"]
                }

                DNSPresetButton(
                    label: "Cloudflare",
                    icon: "cloud.circle.fill",
                    color: .orange
                ) {
                    dnsServers = ["1.1.1.1", "1.0.0.1"]
                }

                DNSPresetButton(
                    label: "クリア",
                    icon: "xmark.circle.fill",
                    color: .gray
                ) {
                    dnsServers = []
                }
            }

            // 現在のDNSサーバー一覧
            if !dnsServers.isEmpty {
                VStack(spacing: 4) {
                    ForEach(dnsServers.indices, id: \.self) { index in
                        HStack {
                            Text(dnsServers[index])
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button {
                                dnsServers.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }

            // カスタムDNS追加
            HStack {
                IPTextField(text: $newDNS, placeholder: "カスタムDNSを追加")

                Button {
                    if !newDNS.isEmpty {
                        dnsServers.append(newDNS)
                        newDNS = ""
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newDNS.isEmpty)
            }
        }
    }

    /// 適用ボタン
    private var applyButton: some View {
        Button {
            applyConfiguration()
        } label: {
            HStack {
                if isApplying {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Text("適用（管理者権限が必要）")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isApplying)
    }

    /// 情報行
    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text("\(label):")
            Text(value)
                .textSelection(.enabled)
        }
    }

    /// ゲートウェイ自動補完
    private func autoFillGateway(from ip: String) {
        // 設定が無効なら何もしない
        guard appState.settings.autoFillGateway else { return }

        // ルーターが既に入力されていたら上書きしない
        guard router.isEmpty else { return }

        // IPアドレスからゲートウェイを推測（最後のオクテットを1にする）
        let components = ip.split(separator: ".")
        if components.count == 4,
           let _ = Int(components[3]) {
            let gateway = "\(components[0]).\(components[1]).\(components[2]).1"
            router = gateway
        }
    }

    /// 現在の設定を読み込み
    private func loadCurrentConfig() {
        if let config = adapter.ipConfiguration {
            configMethod = config.configureIPv4

            // モードに関係なく常に現在のIP情報をロードする
            // DHCPモード時はフィールド非表示なので影響なし
            // 手動に切り替えた瞬間にプリフィルされた状態で表示される
            ipAddress = config.ipv4Address ?? ""
            subnetMask = (config.subnetMask ?? "").isEmpty ? "255.255.255.0" : config.subnetMask!
            let routerValue = config.router ?? ""
            router = (routerValue == "(null)") ? "" : routerValue

            // DNSは(null)を除外
            dnsServers = config.dnsServers.filter { $0 != "(null)" && !$0.isEmpty }
        }
    }

    /// 設定を適用
    private func applyConfiguration() {
        isApplying = true

        // ゲートウェイが空の場合はnilにする（ifconfigモードで設定）
        let routerValue: String? = (configMethod == .manual && !router.isEmpty) ? router : nil

        let config = IPConfiguration(
            configureIPv4: configMethod,
            ipv4Address: configMethod == .manual ? ipAddress : nil,
            subnetMask: configMethod == .manual ? subnetMask : nil,
            router: routerValue,
            dnsServers: dnsServers
        )

        Task {
            do {
                try await appState.networkManager.applyConfiguration(
                    config,
                    to: adapter.displayName,
                    deviceId: adapter.id
                )
                await MainActor.run {
                    isApplying = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isApplying = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

/// IP入力専用テキストフィールド（半角キーボード切替）
struct IPTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.bezelStyle = .roundedBezel
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: IPTextField

        init(_ parent: IPTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            var newValue = textField.stringValue

            // 全角を半角に変換
            if let converted = newValue.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
                newValue = converted
            }
            // 句読点も変換
            newValue = newValue
                .replacingOccurrences(of: "。", with: ".")
                .replacingOccurrences(of: "、", with: ",")
                .replacingOccurrences(of: "：", with: ":")

            if newValue != textField.stringValue {
                textField.stringValue = newValue
            }
            parent.text = newValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            // ASCII入力モードに切り替え
            if let source = TISCopyInputSourceForLanguage("en" as CFString)?.takeRetainedValue() {
                TISSelectInputSource(source)
            }
        }
    }
}

/// DNSプリセットボタン
struct DNSPresetButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
