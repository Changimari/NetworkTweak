import SwiftUI
import ServiceManagement

/// 設定画面
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var updateChecker = UpdateChecker.shared
    @StateObject private var updater = UpdaterManager.shared
    @Environment(\.dismiss) var dismiss
    @State private var launchAtLogin: Bool = false
    @State private var showSpeedInMenuBar: Bool = false
    @State private var refreshInterval: Double = 2.0
    @State private var showIPv6: Bool = false
    @State private var autoFillGateway: Bool = true
    @State private var autoResetOnNetworkChange: Bool = true
    @State private var showEmergencyReset = false
    @State private var isResetting = false

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("設定")
                    .font(.headline)
                Spacer()
                Button("閉じる") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            TabView {
                generalSettingsTab
                    .tabItem {
                        Label("一般", systemImage: "gearshape")
                    }

                displaySettingsTab
                    .tabItem {
                        Label("表示", systemImage: "eye")
                    }

                aboutTab
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .padding(.top, 10)
        }
        .frame(width: 400, height: 450)
        .onAppear {
            loadSettings()
        }
    }

    /// 一般設定タブ
    private var generalSettingsTab: some View {
        Form {
            Section {
                Toggle("ログイン時に起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Picker("更新間隔", selection: $refreshInterval) {
                    Text("1秒").tag(1.0)
                    Text("2秒").tag(2.0)
                    Text("5秒").tag(5.0)
                    Text("10秒").tag(10.0)
                }
                .onChange(of: refreshInterval) { _, newValue in
                    appState.settings.refreshInterval = newValue
                    appState.saveSettings()
                }
            }

            Section("IP設定") {
                Toggle("デフォルトゲートウェイを自動補完", isOn: $autoFillGateway)
                    .onChange(of: autoFillGateway) { _, newValue in
                        appState.settings.autoFillGateway = newValue
                        appState.saveSettings()
                    }

                Toggle("Wi-Fi切り替え時に自動でDHCPに戻す", isOn: $autoResetOnNetworkChange)
                    .onChange(of: autoResetOnNetworkChange) { _, newValue in
                        appState.settings.autoResetOnNetworkChange = newValue
                        appState.saveSettings()
                    }
                    .help("Wi-FiのAPが切り替わった時、固定IP設定を自動でDHCPに戻します。機器設定用APからネットの繋がるAPに移動した時に、ネットが繋がらなくなるのを防ぎます。")
            }

            Section("トラブルシューティング") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("緊急リセット")
                        Text("接続中の全アダプタをDHCPに戻します")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        showEmergencyReset = true
                    } label: {
                        Text(isResetting ? "リセット中..." : "リセット")
                    }
                    .tint(.orange)
                    .disabled(isResetting)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("緊急リセット", isPresented: $showEmergencyReset) {
            Button("キャンセル", role: .cancel) {}
            Button("リセット", role: .destructive) {
                performEmergencyReset()
            }
        } message: {
            Text("接続中の全ネットワークアダプタをDHCPにリセットします。\nネット接続に問題がある場合に使用してください。")
        }
    }

    /// 表示設定タブ
    private var displaySettingsTab: some View {
        Form {
            Section {
                Toggle("メニューバーに通信速度を表示", isOn: $showSpeedInMenuBar)
                    .onChange(of: showSpeedInMenuBar) { _, newValue in
                        appState.settings.showSpeedInMenuBar = newValue
                        appState.saveSettings()
                    }

                Toggle("IPv6情報を表示", isOn: $showIPv6)
                    .onChange(of: showIPv6) { _, newValue in
                        appState.settings.showIPv6 = newValue
                        appState.saveSettings()
                    }

                Picker("速度表示単位", selection: $appState.settings.speedUnit) {
                    ForEach(SpeedUnit.allCases, id: \.self) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// このアプリについてタブ
    /// アプリのバージョン表記（例: "1.0.0 (1)"）
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? updateChecker.currentVersion
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var aboutTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 44))
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))

                VStack(spacing: 3) {
                    Text("NetworkTweak")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Version \(versionText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Switch between DHCP and static IP and scan your local network — right from the menu bar.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Divider().padding(.horizontal, 40)

                // アップデートセクション
                updateSection

                Divider().padding(.horizontal, 40)

                // リンク
                HStack(spacing: 20) {
                    if let url = URL(string: "https://github.com/Changimari/NetworkTweak") {
                        Link(destination: url) {
                            Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    if let url = URL(string: "https://github.com/Changimari/NetworkTweak/issues") {
                        Link(destination: url) {
                            Label("Support", systemImage: "questionmark.circle")
                        }
                    }
                }
                .font(.caption)

                // 帰属表示（IEEE OUIデータ）
                VStack(spacing: 3) {
                    Text("Acknowledgements")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Text("Device manufacturer names are derived from the IEEE MA-L (OUI) Public Listing.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .padding(.horizontal, 24)

                Text("© 2026 NetworkTweak. All rights reserved.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit NetworkTweak")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    /// 緊急リセットを実行
    private func performEmergencyReset() {
        isResetting = true
        Task {
            for adapter in appState.networkManager.connectedAdapters {
                do {
                    try await appState.networkManager.emergencyResetToDHCP(serviceName: adapter.hardwarePort)
                } catch {
                    print("Emergency reset failed for \(adapter.hardwarePort): \(error)")
                }
            }
            isResetting = false
        }
    }

    /// アップデートセクション（Sparkle）
    private var updateSection: some View {
        VStack(spacing: 8) {
            Button {
                updater.checkForUpdates()
            } label: {
                Label("Check for Updates", systemImage: "arrow.down.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(!updater.canCheckForUpdates)

            Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    /// 設定を読み込み
    private func loadSettings() {
        launchAtLogin = appState.settings.launchAtLogin
        showSpeedInMenuBar = appState.settings.showSpeedInMenuBar
        refreshInterval = appState.settings.refreshInterval
        showIPv6 = appState.settings.showIPv6
        autoFillGateway = appState.settings.autoFillGateway
        autoResetOnNetworkChange = appState.settings.autoResetOnNetworkChange
    }

    /// ログイン時起動を設定
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            appState.settings.launchAtLogin = enabled
            appState.saveSettings()
        } catch {
            print("ログイン時起動の設定に失敗: \(error)")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
